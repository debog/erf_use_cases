#!/usr/bin/env python3
"""
Script to plot super-droplet fields from ERF AMR simulations at each timestep.

This script creates 2D (x-z) plots showing:
  1. Super-droplet moisture number density with AMR mesh overlay
  2. (Optional) Particle positions in the domain

Usage:
    python plot_superdroplets.py <run_directory> [options]

Examples:
    python plot_superdroplets.py .run_BF02_dry_bubble_AMR1.matrix.nproc00004
    python plot_superdroplets.py .run_BF02_dry_bubble_AMR1.matrix.nproc00004 --with-particles
    python plot_superdroplets.py .run_BF02_dry_bubble_AMR1.matrix.nproc00004 -o custom_plots
"""

import yt
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.collections import LineCollection
import sys
import os
import argparse
from glob import glob

# Disable yt info prints
yt.set_log_level("error")


def format_time(seconds):
    """Format time in seconds."""
    return f'{seconds:.1f} s'


def get_domain_extent(ds):
    """
    Extract physical domain extent from yt dataset.

    Returns:
        Tuple of (x_extent, y_extent, z_extent) in meters
    """
    domain_width = ds.domain_width.to('m').value
    return tuple(domain_width)


def get_midplane_slice(ds, field_name):
    """
    Extract a 2D slice at the y-midplane from a 3D field, properly handling AMR.

    Args:
        ds: yt dataset
        field_name: name of the field to extract

    Returns:
        Tuple of (x_coords, z_coords, field_2d) where field_2d is at y-midplane
    """
    # Use an arbitrary grid to sample the AMR hierarchy at finest resolution
    max_level = ds.max_level

    # Calculate dimensions at max level (assuming ref_ratio=2)
    base_dims = ds.domain_dimensions
    ref_ratio = 2 ** max_level
    dims_at_max = base_dims * ref_ratio

    # Create an arbitrary grid at max level - this samples the AMR hierarchy
    ag = ds.arbitrary_grid(left_edge=ds.domain_left_edge,
                           right_edge=ds.domain_right_edge,
                           dims=dims_at_max)

    # Get coordinates (convert from cm to m)
    x = np.array(ag['x'][:, 0, 0]) / 1e2  # cm to m
    y = np.array(ag['y'][0, :, 0]) / 1e2
    z = np.array(ag['z'][0, 0, :]) / 1e2

    # Get 3D field
    field_3d = np.array(ag[('boxlib', field_name)])  # Shape: (nx, ny, nz)

    # Extract midplane (middle index along y)
    midplane_idx = len(y) // 2
    field_2d = field_3d[:, midplane_idx, :].T  # Transpose to (nz, nx) for plotting

    return x, z, field_2d


def get_amr_mesh_lines(ds):
    """
    Extract AMR grid cell edges for visualization (shows actual computational mesh).

    Args:
        ds: yt dataset

    Returns:
        List of line segments showing all cell edges at all AMR levels
    """
    mesh_lines = []

    # Loop over all grid levels
    for level in range(ds.max_level + 1):
        grids_at_level = [g for g in ds.index.grids if g.Level == level]

        for grid in grids_at_level:
            # Get grid boundaries and cell sizes
            left_edge = grid.LeftEdge.to('m').value
            right_edge = grid.RightEdge.to('m').value
            dx = grid.dds.to('m').value  # Cell sizes (dx, dy, dz)

            x_min, y_min, z_min = left_edge
            x_max, y_max, z_max = right_edge
            dx_val, dy_val, dz_val = dx

            # Number of cells in each direction
            nx = int(np.round((x_max - x_min) / dx_val))
            nz = int(np.round((z_max - z_min) / dz_val))

            # Draw vertical lines (constant x)
            for i in range(nx + 1):
                x = x_min + i * dx_val
                mesh_lines.append([(x, z_min), (x, z_max)])

            # Draw horizontal lines (constant z)
            for k in range(nz + 1):
                z = z_min + k * dz_val
                mesh_lines.append([(x_min, z), (x_max, z)])

    return mesh_lines


def read_particle_file(run_dir, plotfile_name):
    """
    Read super-droplet particle positions from text file.

    Args:
        run_dir: run directory path
        plotfile_name: name of the plotfile (e.g., 'plt00100')

    Returns:
        Numpy array of particle positions (N, 3) or None if file not found
    """
    # ERF super-droplet output format: super_droplets_<step>.txt
    # Extract step number from plotfile name
    step = plotfile_name.replace('plt', '')
    particle_file = os.path.join(run_dir, f'super_droplets_{step}.txt')

    if not os.path.exists(particle_file):
        return None

    try:
        # Read particle file (assuming format: x y z ...)
        # Skip header if present
        data = np.loadtxt(particle_file, comments='#')
        if len(data.shape) == 1:
            data = data.reshape(1, -1)

        # Extract x, y, z coordinates (first 3 columns)
        if data.shape[1] >= 3:
            return data[:, :3]
        else:
            return None
    except Exception as e:
        print(f"Warning: Could not read particle file {particle_file}: {e}")
        return None


def plot_superdroplet_fields(ds, time, output_file, domain_extent,
                             with_particles=False, run_dir=None,
                             plotfile_name=None):
    """
    Create a 2-panel plot showing:
      1. Super-droplet moisture number density with AMR mesh
      2. (Optional) Particle positions

    Args:
        ds: yt dataset
        time: simulation time
        output_file: path to save the plot
        domain_extent: tuple of (x_extent, y_extent, z_extent) in meters
        with_particles: whether to include particle plot
        run_dir: run directory (needed for particle files)
        plotfile_name: name of plotfile (needed for particle files)
    """
    # Set up figure with proper aspect ratio
    x_extent_m = domain_extent[0]
    z_extent_m = domain_extent[2]

    # For figure size: width should be proportional to x_extent, height to z_extent
    # Use equal physical scaling: 1 meter in x = 1 meter in z on screen
    fig_height = 10
    aspect_ratio = x_extent_m / z_extent_m
    single_width = fig_height * aspect_ratio

    # Create subplots
    ncols = 2 if with_particles else 1
    fig, axes = plt.subplots(1, ncols, figsize=(single_width * ncols, fig_height))

    if ncols == 1:
        axes = [axes]  # Make it iterable

    # Check if number density field exists
    available_fields = [name for (_, name) in ds.field_list]
    field_name = 'super_droplets_moisture_number_density'

    if field_name not in available_fields:
        print(f"Warning: {field_name} not found in dataset")
        print(f"Available fields: {available_fields}")
        plt.close(fig)
        return

    # Extract 2D slice at midplane
    x, z, field_2d = get_midplane_slice(ds, field_name)

    # Get AMR mesh lines
    mesh_lines = get_amr_mesh_lines(ds)

    # ========================================================================
    # Panel 1: Number density with mesh overlay
    # ========================================================================
    ax = axes[0]

    # Plot number density as a color field
    extent = [x[0], x[-1], z[0], z[-1]]

    # Mask zero values for better visualization
    field_plot = np.copy(field_2d)
    field_plot[field_plot == 0] = np.nan

    # Check if we have any non-zero data
    has_data = np.any(np.isfinite(field_plot))

    if has_data:
        # Use log scale if range is large
        vmin = np.nanmin(field_plot)
        vmax = np.nanmax(field_plot)

        # Use coolwarm colormap (blue=low, white=mid, red=high)
        if vmax > 0 and vmin > 0 and (vmax / vmin > 100):
            from matplotlib.colors import LogNorm
            im = ax.imshow(field_plot, extent=extent, aspect='auto', origin='lower',
                          cmap='coolwarm', interpolation='bilinear', norm=LogNorm(vmin=vmin, vmax=vmax))
        else:
            im = ax.imshow(field_plot, extent=extent, aspect='auto', origin='lower',
                          cmap='coolwarm', interpolation='bilinear', vmin=vmin, vmax=vmax)
    else:
        # No data - show empty field with neutral color
        im = ax.imshow(np.zeros_like(field_2d), extent=extent, aspect='auto', origin='lower',
                      cmap='coolwarm', interpolation='bilinear', vmin=0, vmax=1)
        # Add text overlay
        ax.text(0.5, 0.5, 'No droplet data\n(all zeros)',
               ha='center', va='center', transform=ax.transAxes, fontsize=20,
               color='dimgray', bbox=dict(boxstyle='round', facecolor='white', alpha=0.7))

    # Add colorbar with better styling
    cbar = plt.colorbar(im, ax=ax, pad=0.02, fraction=0.046)
    cbar.set_label('Number density (#/m³)', fontsize=20)
    cbar.ax.tick_params(labelsize=16)

    # Overlay computational mesh with thin dark grey lines (almost black)
    lc = LineCollection(mesh_lines, colors='#222222', linewidths=0.3, alpha=0.8)
    ax.add_collection(lc)

    ax.set_xlabel('X (m)', fontsize=22)
    ax.set_ylabel('Z (m)', fontsize=22)
    ax.set_title(f'Super-droplet number density, t = {format_time(time)}', fontsize=26)
    ax.set_aspect('equal')  # Equal physical scaling: 1m in x = 1m in z
    ax.tick_params(labelsize=18)

    # ========================================================================
    # Panel 2 (optional): Particle positions
    # ========================================================================
    if with_particles:
        ax = axes[1]

        # Try to read particle positions
        particles = None
        if run_dir and plotfile_name:
            particles = read_particle_file(run_dir, plotfile_name)

        if particles is not None and len(particles) > 0:
            # Extract x and z coordinates (y-midplane projection)
            x_particles = particles[:, 0]
            y_particles = particles[:, 1]
            z_particles = particles[:, 2]

            # Plot particles as scatter
            ax.scatter(x_particles, z_particles, s=1, c='blue', alpha=0.5,
                      edgecolors='none', rasterized=True)

            ax.set_xlim(extent[0], extent[1])
            ax.set_ylim(extent[2], extent[3])
            ax.set_xlabel('X (m)', fontsize=22)
            ax.set_ylabel('Z (m)', fontsize=22)
            ax.set_title(f'Particle positions ({len(particles)} particles)', fontsize=26)
            ax.set_aspect('equal')  # Equal physical scaling: 1m in x = 1m in z
            ax.tick_params(labelsize=18)

            # Add AMR mesh to particle plot too
            ax.set_facecolor('#f0f0f0')  # Light gray background
            lc2 = LineCollection(mesh_lines, colors='#222222', linewidths=0.3, alpha=0.8)
            ax.add_collection(lc2)
        else:
            # No particles found - show empty plot with message
            ax.set_facecolor('#f0f0f0')  # Light gray background
            ax.text(0.5, 0.5, 'No particle data available',
                   ha='center', va='center', transform=ax.transAxes, fontsize=20,
                   color='darkgray')
            ax.set_xlim(extent[0], extent[1])
            ax.set_ylim(extent[2], extent[3])
            ax.set_xlabel('X (m)', fontsize=22)
            ax.set_ylabel('Z (m)', fontsize=22)
            ax.set_title('Particle positions', fontsize=26)
            ax.set_aspect('equal')  # Equal physical scaling: 1m in x = 1m in z
            ax.tick_params(labelsize=18)

    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close(fig)


def plot_all_timesteps(run_dir, output_dir, with_particles=False):
    """
    Plot super-droplet fields from all timesteps in a run directory.

    Args:
        run_dir: path to the run directory containing plt* subdirectories
        output_dir: directory to save plots (will be created if doesn't exist)
        with_particles: whether to include particle position plots
    """
    # Find all plotfiles (directories only, ignore plt.visit file)
    all_plt = glob(os.path.join(run_dir, 'plt*'))
    plotfiles = sorted([f for f in all_plt
                       if os.path.isdir(f) and os.path.basename(f) != 'plt.visit'])

    if not plotfiles:
        print(f"No plotfiles found in {run_dir}")
        return

    print(f"Found {len(plotfiles)} plotfiles")

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Get domain info from first plotfile
    print("Loading first plotfile to check domain...")
    ds = yt.load(plotfiles[0])
    domain_extent = get_domain_extent(ds)

    print(f"Domain extent: {domain_extent[0]:.1f} m x {domain_extent[1]:.1f} m x {domain_extent[2]:.1f} m")
    print(f"Max AMR level: {ds.max_level}")

    # Process each plotfile
    for i, pltfile in enumerate(plotfiles):
        plotfile_name = os.path.basename(pltfile)
        print(f"\nProcessing {plotfile_name} ({i+1}/{len(plotfiles)})...")

        # Load data
        ds = yt.load(pltfile)
        time = float(ds.current_time)

        # Create plot
        output_file = os.path.join(output_dir, f'superdroplets_{plotfile_name}.png')
        plot_superdroplet_fields(ds, time, output_file, domain_extent,
                                with_particles=with_particles,
                                run_dir=run_dir,
                                plotfile_name=plotfile_name)

        print(f"  Saved {output_file}")

    print(f"\nAll plots saved to {output_dir}/")


def main():
    parser = argparse.ArgumentParser(
        description="""
Plot super-droplet fields from ERF AMR simulations.

This script creates 2D (x-z) plots at the y-midplane showing:
  1. Super-droplet moisture number density with AMR mesh overlay
  2. (Optional) Particle positions in the domain (with --with-particles)

The plots maintain the physical aspect ratio of the simulation domain and are
suitable for quasi-2D simulations (e.g., ny=4 cells in y-direction).
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s .run_BF02_dry_bubble_AMR1.matrix.nproc00004
  %(prog)s .run_BF02_dry_bubble_AMR1.matrix.nproc00004 --with-particles
  %(prog)s .run_BF02_dry_bubble_AMR1.matrix.nproc00004 -o custom_plots

Output:
  Creates one PNG file per timestep in the output directory:
  - superdroplets_plt*.png : 2D plots showing number density with AMR mesh
                              and optionally particle positions

Plot Layout:
  Without --with-particles: Single panel showing number density with mesh
  With --with-particles:    Two panels side-by-side (density + particles)

Requirements:
  Python packages: yt, numpy, matplotlib
  Install: pip install yt numpy matplotlib

Technical Details:
  - Extracts 2D slice at y-midplane (index ny//2)
  - Uses 'coolwarm' colormap (blue=low, white=mid, red=high)
  - Log-scale applied when dynamic range exceeds 100×
  - Bilinear interpolation for smooth rendering
  - Computational mesh shown as thin dark lines (#222222, linewidth=0.3, alpha=0.8)
  - All cell edges rendered at all AMR levels
  - Particles read from super_droplets_<step>.txt if available
  - Physical aspect ratio preserved with ax.set_aspect('equal')

Notes:
  - This is designed for 2D cases (few cells in y-direction)
  - All AMR levels are processed and visualized
  - Particle files are optional; plots work without them
  - Output directory is created if it doesn't exist
        """
    )

    parser.add_argument('run_directory',
                       help='Path to ERF run directory containing plt* subdirectories')
    parser.add_argument('-o', '--output-dir', dest='output_dir',
                       help='Output directory for plots (default: <run_directory>/plots)')
    parser.add_argument('--with-particles', action='store_true',
                       help='Include particle position plots in second panel')

    args = parser.parse_args()

    run_dir = args.run_directory
    output_dir = args.output_dir if args.output_dir else os.path.join(run_dir, 'plots')

    if not os.path.isdir(run_dir):
        print(f"Error: {run_dir} is not a valid directory")
        sys.exit(1)

    print("=" * 70)
    print("ERF Super-Droplet Plotting Script")
    print("=" * 70)
    print(f"Processing run directory: {run_dir}")
    print(f"Output directory: {output_dir}")
    print(f"Include particles: {args.with_particles}")
    print("=" * 70)

    plot_all_timesteps(run_dir, output_dir, with_particles=args.with_particles)

    print("\nDone!")


if __name__ == '__main__':
    main()
