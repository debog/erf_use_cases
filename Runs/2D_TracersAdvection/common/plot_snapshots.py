#!/usr/bin/env python3
"""Plot tracer particle snapshots from ERF ParticleWoA run.

Usage: python plot_snapshots.py <run_dir>

Each plotfile produces a figure with two subplots:
  Left:  Eulerian tracer_particles_count on terrain-following mesh
  Right: Particle positions as scatter points on the same domain

Both subplots show the terrain surface.
"""

import glob
import os
import re
import sys

import matplotlib.pyplot as plt
from mpl_toolkits.axes_grid1 import make_axes_locatable
import numpy as np
import yt

yt.set_log_level("error")

if len(sys.argv) < 2:
    sys.exit(f"Usage: {sys.argv[0]} <run_dir>")

RUN_DIR = os.path.abspath(sys.argv[1])
OUT_DIR = os.path.join(RUN_DIR, "plots")
os.makedirs(OUT_DIR, exist_ok=True)

# Discover plotfiles sorted by index
plt_dirs = sorted(
    glob.glob(os.path.join(RUN_DIR, "plt?????")),
    key=lambda p: int(re.search(r"plt(\d+)", p).group(1)),
)
if not plt_dirs:
    sys.exit(f"No plotfiles found in {RUN_DIR}")

# y-slice index (midplane of the 8-cell y-direction)
JY = 4


def composite_particle_count(ds, field_name):
    """Composite particle count from all AMR levels onto the level-0 grid.

    Particle counts are deposited per-level (L0 counts particles on L0, L1
    counts particles on L1, etc.) so contributions are simply summed.
    Takes the y-midslice.  Fine-level cells are summed into their parent
    coarse cell.
    """
    base_dims = ds.domain_dimensions  # level-0 cell counts
    nx0, ny0, nz0 = base_dims

    domain_left = ds.domain_left_edge.v
    domain_width = ds.domain_width.v

    out = np.zeros((nx0, nz0))
    field_tuple = ("boxlib", field_name)

    for level in range(ds.max_level + 1):
        grids = [g for g in ds.index.grids if g.Level == level]
        for grid in grids:
            data = np.array(grid[field_tuple])  # (gx, gy, gz)
            jy_mid = data.shape[1] // 2
            grid_slice = data[:, jy_mid, :]  # midslice in y -> (gx, gz)

            left = grid.LeftEdge.v
            right = grid.RightEdge.v
            i0 = int(np.round((left[0] - domain_left[0]) / domain_width[0] * nx0))
            i1 = int(np.round((right[0] - domain_left[0]) / domain_width[0] * nx0))
            k0 = int(np.round((left[2] - domain_left[2]) / domain_width[2] * nz0))
            k1 = int(np.round((right[2] - domain_left[2]) / domain_width[2] * nz0))

            target_nx = i1 - i0
            target_nz = k1 - k0

            if grid_slice.shape[0] == target_nx and grid_slice.shape[1] == target_nz:
                out[i0:i1, k0:k1] += grid_slice
            else:
                # Fine grid: sum fine cells into coarse cells
                rx = grid_slice.shape[0] // target_nx
                rz = grid_slice.shape[1] // target_nz
                coarse = grid_slice.reshape(target_nx, rx, target_nz, rz).sum(axis=(1, 3))
                out[i0:i1, k0:k1] += coarse

    return out


def get_fine_mesh_segments(ds):
    """Extract terrain-following mesh line segments for fine AMR levels.

    Returns a list of (x_arr, z_arr) polyline pairs for each cell edge
    on levels > 0.
    """
    if ds.max_level == 0:
        return []

    has_terrain = ("boxlib", "z_phys") in ds.field_list
    segments = []
    field_tuple = ("boxlib", "z_phys") if has_terrain else None

    for level in range(1, ds.max_level + 1):
        grids = [g for g in ds.index.grids if g.Level == level]
        for grid in grids:
            if has_terrain:
                z_data = np.array(grid[field_tuple])  # (gx, gy, gz) cell-center z
                gx, gy, gz = z_data.shape
                jy_local = gy // 2
                z_cc = z_data[:, jy_local, :]  # (gx, gz)
            else:
                # Flat terrain: compute uniform z cell-centers from grid edges
                left = grid.LeftEdge.v
                right = grid.RightEdge.v
                shape = grid.ActiveDimensions
                gx, gy, gz = int(shape[0]), int(shape[1]), int(shape[2])
                dz = (right[2] - left[2]) / gz
                z_cc_1d = np.arange(gz) * dz + left[2] + 0.5 * dz
                z_cc = np.tile(z_cc_1d, (gx, 1))

            left = grid.LeftEdge.v
            right = grid.RightEdge.v
            dx_fine = (right[0] - left[0]) / gx

            # x cell edges
            x_edges = np.linspace(left[0], right[0], gx + 1)

            # z cell edges from cell centers (per column)
            z_edges = np.zeros((gx, gz + 1))
            z_edges[:, 0] = z_cc[:, 0] - 0.5 * (z_cc[:, 1] - z_cc[:, 0])
            z_edges[:, -1] = z_cc[:, -1] + 0.5 * (z_cc[:, -1] - z_cc[:, -2])
            for k in range(1, gz):
                z_edges[:, k] = 0.5 * (z_cc[:, k - 1] + z_cc[:, k])

            # Horizontal lines (constant k)
            z_edges_ext = np.vstack([z_edges, z_edges[-1:, :]])
            for k in range(gz + 1):
                segments.append((x_edges, z_edges_ext[:, k]))

            # Vertical lines (constant i)
            for i in range(gx + 1):
                if i < gx:
                    segments.append((np.full(gz + 1, x_edges[i]), z_edges[i, :]))
                else:
                    segments.append((np.full(gz + 1, x_edges[i]), z_edges[-1, :]))

    return segments


def load_snapshot(pltdir):
    """Return mesh fields and particle positions from a plotfile."""
    ds = yt.load(pltdir)

    base_dims = ds.domain_dimensions
    nx0, ny0, nz0 = base_dims

    # z_phys from level-0 covering grid (terrain mesh doesn't change with AMR)
    has_terrain = ("boxlib", "z_phys") in ds.field_list
    if has_terrain:
        cg = ds.covering_grid(
            level=0, left_edge=ds.domain_left_edge, dims=ds.domain_dimensions
        )
        z_phys = cg["boxlib", "z_phys"].v[:, JY, :]        # (nx, nz)
    else:
        # Flat terrain: uniform z grid
        dz = ds.domain_width[2].v / nz0
        z_cc_1d = np.arange(nz0) * dz + ds.domain_left_edge[2].v + 0.5 * dz
        z_phys = np.tile(z_cc_1d, (nx0, 1))  # (nx, nz) uniform

    # Eulerian fields from level-0 covering grid
    cg0 = ds.covering_grid(
        level=0, left_edge=ds.domain_left_edge, dims=ds.domain_dimensions
    )
    density  = cg0["boxlib", "density"].v[:, JY, :]
    pressure = cg0["boxlib", "pressure"].v[:, JY, :]
    x_vel    = cg0["boxlib", "x_velocity"].v[:, JY, :]
    z_vel    = cg0["boxlib", "z_velocity"].v[:, JY, :]

    # Check if tracer particle fields exist
    has_particles = ("boxlib", "tracer_particles_count") in ds.field_list

    tc = None
    px = np.array([])
    pz = np.array([])
    if has_particles:
        tc = composite_particle_count(ds, "tracer_particles_count")
        ad = ds.all_data()
        px = ad["all", "particle_position_x"].v
        pz = ad["all", "particle_position_z"].v

    # Fine-level mesh segments for overlay
    fine_mesh = get_fine_mesh_segments(ds)

    # Domain info
    dx = ds.domain_width[0].v / ds.domain_dimensions[0]
    nx, nz = z_phys.shape

    # Build cell-center x coordinates (uniform in x)
    x_cc = np.arange(nx) * dx + ds.domain_left_edge[0].v + 0.5 * dx

    # Terrain surface: bottom of the lowest cell row
    # z_phys gives cell-center height; approximate bottom edge
    terrain_z = z_phys[:, 0] - 0.5 * (z_phys[:, 1] - z_phys[:, 0])

    time = float(ds.current_time)
    step = int(re.search(r"plt(\d+)", pltdir).group(1))

    return dict(
        x_cc=x_cc, z_phys=z_phys, terrain_z=terrain_z,
        density=density, pressure=pressure,
        x_vel=x_vel, z_vel=z_vel,
        tracer_count=tc,
        has_particles=has_particles,
        fine_mesh=fine_mesh,
        px=px, pz=pz,
        time=time, step=step,
        prob_lo=ds.domain_left_edge.v,
        prob_hi=ds.domain_right_edge.v,
    )


def plot_snapshot(data, outpath):
    """Create a panel figure for one snapshot.

    With particles (3x2):
      Row 0: density,              pressure
      Row 1: x-velocity,           z-velocity
      Row 2: tracer particle count, particle positions

    Without particles (2x2):
      Row 0: density,              pressure
      Row 1: x-velocity,           z-velocity
    """
    has_particles = data["has_particles"]
    nrows = 3 if has_particles else 2
    figheight = 10 if has_particles else 7
    fig, axes = plt.subplots(nrows, 2, figsize=(20, figheight), sharex=True, sharey=True)
    fig.suptitle(f"Step {data['step']},  t = {data['time']:.4f} s", fontsize=14)

    x_cc    = data["x_cc"]
    z_phys  = data["z_phys"]
    terrain = data["terrain_z"]
    nx, nz  = z_phys.shape

    # Build 2D coordinate arrays for pcolormesh
    dx = x_cc[1] - x_cc[0]
    x_edges = np.concatenate([[x_cc[0] - 0.5 * dx], x_cc + 0.5 * dx])

    z_edges = np.zeros((nx, nz + 1))
    z_edges[:, 0] = z_phys[:, 0] - 0.5 * (z_phys[:, 1] - z_phys[:, 0])
    z_edges[:, -1] = z_phys[:, -1] + 0.5 * (z_phys[:, -1] - z_phys[:, -2])
    for k in range(1, nz):
        z_edges[:, k] = 0.5 * (z_phys[:, k - 1] + z_phys[:, k])

    z_ext = np.vstack([z_edges, z_edges[-1:, :]])
    X2 = np.tile(x_edges[:, np.newaxis], (1, nz + 1))
    Z2 = z_ext

    def add_terrain(ax):
        ax.fill_between(x_cc, 0, terrain, color="saddlebrown", alpha=0.9, zorder=5)
        ax.plot(x_cc, terrain, color="black", linewidth=0.8, zorder=6)

    def add_fine_mesh(ax):
        fine_kw = dict(color="blue", linewidth=0.15, alpha=0.4, zorder=3)
        for x_seg, z_seg in data.get("fine_mesh", []):
            ax.plot(x_seg, z_seg, **fine_kw)

    def add_colorbar(ax, pcm):
        divider = make_axes_locatable(ax)
        cax = divider.append_axes("right", size="2%", pad=0.05)
        fig.colorbar(pcm, cax=cax)

    def format_ax(ax):
        ax.set_xlim(data["prob_lo"][0], data["prob_hi"][0])
        ax.set_ylim(0, data["prob_hi"][2])
        ax.set_aspect("equal")

    # --- (0,0) Density ---
    ax = axes[0, 0]
    pcm = ax.pcolormesh(X2, Z2, data["density"], cmap="viridis", shading="flat")
    add_colorbar(ax, pcm)
    add_terrain(ax)
    add_fine_mesh(ax)
    ax.set_title("Density")
    ax.set_ylabel("z (m)")
    format_ax(ax)

    # --- (0,1) Pressure ---
    ax = axes[0, 1]
    pcm = ax.pcolormesh(X2, Z2, data["pressure"], cmap="viridis", shading="flat")
    add_colorbar(ax, pcm)
    add_terrain(ax)
    add_fine_mesh(ax)
    ax.set_title("Pressure")
    format_ax(ax)

    # --- (1,0) x-velocity ---
    ax = axes[1, 0]
    pcm = ax.pcolormesh(X2, Z2, data["x_vel"], cmap="RdBu_r", shading="flat")
    add_colorbar(ax, pcm)
    add_terrain(ax)
    add_fine_mesh(ax)
    ax.set_title("x-velocity")
    ax.set_ylabel("z (m)")
    if not has_particles:
        ax.set_xlabel("x (m)")
    format_ax(ax)

    # --- (1,1) z-velocity ---
    ax = axes[1, 1]
    vmax_w = max(abs(data["z_vel"].min()), abs(data["z_vel"].max()), 1e-6)
    pcm = ax.pcolormesh(X2, Z2, data["z_vel"], cmap="RdBu_r",
                        vmin=-vmax_w, vmax=vmax_w, shading="flat")
    add_colorbar(ax, pcm)
    add_terrain(ax)
    add_fine_mesh(ax)
    ax.set_title("z-velocity")
    if not has_particles:
        ax.set_xlabel("x (m)")
    format_ax(ax)

    if has_particles:
        # --- (2,0) Tracer particle count ---
        ax = axes[2, 0]
        tc = data["tracer_count"]
        tc_max = max(tc.max(), 1.0)
        pcm = ax.pcolormesh(X2, Z2, tc, cmap="YlOrRd", vmin=0, vmax=tc_max,
                            shading="flat")
        add_colorbar(ax, pcm)
        add_terrain(ax)
        add_fine_mesh(ax)
        ax.set_title("Tracer particle count (Eulerian)")
        ax.set_xlabel("x (m)")
        ax.set_ylabel("z (m)")
        format_ax(ax)

        # --- (2,1) Particle scatter ---
        ax = axes[2, 1]
        add_terrain(ax)
        if len(data["px"]) > 0:
            ax.scatter(data["px"], data["pz"], s=8, c="dodgerblue",
                       edgecolors="navy", linewidths=0.3, zorder=10, alpha=0.8)
        ax.set_title(f"Particle positions (N={len(data['px'])})")
        ax.set_xlabel("x (m)")
        format_ax(ax)

    fig.tight_layout()
    fig.savefig(outpath, dpi=150, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    for pdir in plt_dirs:
        step = int(re.search(r"plt(\d+)", pdir).group(1))
        outpath = os.path.join(OUT_DIR, f"snapshot_{step:05d}.png")
        print(f"Plotting {os.path.basename(pdir)} ...", end=" ", flush=True)
        data = load_snapshot(pdir)
        plot_snapshot(data, outpath)
        print("done")
    print(f"\nPlots saved to {OUT_DIR}/")
