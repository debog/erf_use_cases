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


def load_snapshot(pltdir):
    """Return mesh fields and particle positions from a plotfile."""
    ds = yt.load(pltdir)
    cg = ds.covering_grid(
        level=0, left_edge=ds.domain_left_edge, dims=ds.domain_dimensions
    )
    z_phys = cg["boxlib", "z_phys"].v[:, JY, :]        # (nx, nz)
    tc     = cg["boxlib", "tracer_particles_count"].v[:, JY, :]

    # Domain info
    dx = ds.domain_width[0].v / ds.domain_dimensions[0]
    nx, nz = z_phys.shape

    # Build cell-center x coordinates (uniform in x)
    x_cc = np.arange(nx) * dx + ds.domain_left_edge[0].v + 0.5 * dx

    # Terrain surface: bottom of the lowest cell row
    # z_phys gives cell-center height; approximate bottom edge
    terrain_z = z_phys[:, 0] - 0.5 * (z_phys[:, 1] - z_phys[:, 0])

    # Particle positions (all particles, not just midplane — quasi-2D domain)
    ad = ds.all_data()
    px = ad["all", "particle_position_x"].v
    pz = ad["all", "particle_position_z"].v

    time = float(ds.current_time)
    step = int(re.search(r"plt(\d+)", pltdir).group(1))

    return dict(
        x_cc=x_cc, z_phys=z_phys, terrain_z=terrain_z,
        tracer_count=tc,
        px=px, pz=pz,
        time=time, step=step,
        prob_lo=ds.domain_left_edge.v,
        prob_hi=ds.domain_right_edge.v,
    )


def plot_snapshot(data, outpath):
    """Create a two-panel figure for one snapshot."""
    fig, (ax_l, ax_r) = plt.subplots(1, 2, figsize=(16, 5), sharey=True)
    fig.suptitle(f"Step {data['step']},  t = {data['time']:.4f} s", fontsize=13)

    x_cc    = data["x_cc"]
    z_phys  = data["z_phys"]
    terrain = data["terrain_z"]
    tc      = data["tracer_count"]
    nx, nz  = z_phys.shape

    # Build 2D coordinate arrays for pcolormesh
    # x-edges (uniform)
    dx = x_cc[1] - x_cc[0]
    x_edges = np.concatenate([[x_cc[0] - 0.5 * dx], x_cc + 0.5 * dx])

    # z-edges from z_phys cell centers (per column)
    z_edges = np.zeros((nx, nz + 1))
    z_edges[:, 0] = z_phys[:, 0] - 0.5 * (z_phys[:, 1] - z_phys[:, 0])
    z_edges[:, -1] = z_phys[:, -1] + 0.5 * (z_phys[:, -1] - z_phys[:, -2])
    for k in range(1, nz):
        z_edges[:, k] = 0.5 * (z_phys[:, k - 1] + z_phys[:, k])

    # pcolormesh needs (nx+1, nz+1) vertex arrays
    z_ext = np.vstack([z_edges, z_edges[-1:, :]])  # repeat last row for right edge
    X2 = np.tile(x_edges[:, np.newaxis], (1, nz + 1))  # (nx+1, nz+1)
    Z2 = z_ext  # (nx+1, nz+1)

    # --- Left panel: tracer_particles_count ---
    tc_max = max(tc.max(), 1.0)
    pcm = ax_l.pcolormesh(X2, Z2, tc, cmap="YlOrRd", vmin=0, vmax=tc_max,
                           shading="flat")
    fig.colorbar(pcm, ax=ax_l, label="tracer count", shrink=0.8)

    ax_l.fill_between(x_cc, 0, terrain, color="saddlebrown", alpha=0.9, zorder=5)
    ax_l.plot(x_cc, terrain, color="black", linewidth=0.8, zorder=6)

    ax_l.set_xlim(data["prob_lo"][0], data["prob_hi"][0])
    ax_l.set_ylim(0, data["prob_hi"][2])
    ax_l.set_xlabel("x (m)")
    ax_l.set_ylabel("z (m)")
    ax_l.set_title("Tracer particle count (Eulerian)")
    ax_l.set_aspect("equal")

    # --- Right panel: particle scatter ---
    ax_r.fill_between(x_cc, 0, terrain, color="saddlebrown", alpha=0.9, zorder=5)
    ax_r.plot(x_cc, terrain, color="black", linewidth=0.8, zorder=6)

    if len(data["px"]) > 0:
        ax_r.scatter(data["px"], data["pz"], s=8, c="dodgerblue",
                     edgecolors="navy", linewidths=0.3, zorder=10, alpha=0.8)

    ax_r.set_xlim(data["prob_lo"][0], data["prob_hi"][0])
    ax_r.set_ylim(0, data["prob_hi"][2])
    ax_r.set_xlabel("x (m)")
    ax_r.set_title(f"Particle positions (N={len(data['px'])})")
    ax_r.set_aspect("equal")

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
