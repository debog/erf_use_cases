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

    Manually composites data from all AMR levels to ensure coarse regions are filled.

    Args:
        ds: yt dataset
        field_name: name of the field to extract

    Returns:
        Tuple of (x_coords, z_coords, field_2d) where field_2d is at y-midplane
    """
    max_level = ds.max_level
    base_dims = ds.domain_dimensions
    field_tuple = ('boxlib', field_name)

    # Calculate finest resolution dimensions
    if max_level > 0:
        dims_finest = base_dims * (2 ** max_level)
    else:
        dims_finest = base_dims

    # Initialize output arrays at finest resolution
    # Start by getting base level data
    cg0 = ds.covering_grid(level=0,
                           left_edge=ds.domain_left_edge,
                           dims=base_dims,
                           fields=[field_tuple])

    # Get coordinates at finest level (we'll use these for output)
    x_fine = np.linspace(float(ds.domain_left_edge[0].to('m').value),
                        float(ds.domain_right_edge[0].to('m').value),
                        dims_finest[0])
    z_fine = np.linspace(float(ds.domain_left_edge[2].to('m').value),
                        float(ds.domain_right_edge[2].to('m').value),
                        dims_finest[2])

    # Get base level data
    field_3d_base = np.array(cg0[field_tuple])  # Shape: (nx0, ny0, nz0)
    y_mid_idx = field_3d_base.shape[1] // 2
    field_2d_base = field_3d_base[:, y_mid_idx, :].T  # (nz0, nx0)

    print(f"  Level 0: shape={field_2d_base.shape}, min={np.min(field_2d_base):.2e}, max={np.max(field_2d_base):.2e}")

    # If no AMR, just return base level upsampled
    if max_level == 0:
        # Need to match output resolution
        from scipy.ndimage import zoom
        zoom_factors = (dims_finest[2] / base_dims[2], dims_finest[0] / base_dims[0])
        field_2d_fine = zoom(field_2d_base, zoom_factors, order=0)  # Nearest neighbor
        return x_fine, z_fine, field_2d_fine

    # Otherwise, composite all levels
    # Upsample base level to finest resolution
    from scipy.ndimage import zoom
    zoom_factors = (dims_finest[2] / base_dims[2], dims_finest[0] / base_dims[0])
    field_2d_composite = zoom(field_2d_base, zoom_factors, order=0)

    # Now overlay finer levels
    for level in range(1, max_level + 1):
        # Get data at this level
        dims_at_level = base_dims * (2 ** level)
        cg = ds.covering_grid(level=level,
                             left_edge=ds.domain_left_edge,
                             dims=dims_at_level,
                             fields=[field_tuple])

        field_3d_level = np.array(cg[field_tuple])
        y_mid_idx = field_3d_level.shape[1] // 2
        field_2d_level = field_3d_level[:, y_mid_idx, :].T  # (nz_level, nx_level)

        print(f"  Level {level}: shape={field_2d_level.shape}, min={np.min(field_2d_level):.2e}, max={np.max(field_2d_level):.2e}")

        # Upsample if not at finest level yet
        if level < max_level:
            zoom_factors = (dims_finest[2] / dims_at_level[2], dims_finest[0] / dims_at_level[0])
            field_2d_level = zoom(field_2d_level, zoom_factors, order=0)

        # Overlay: replace values where this level has non-zero data
        mask = field_2d_level > 0  # Or use a better criterion
        field_2d_composite[mask] = field_2d_level[mask]

    return x_fine, z_fine, field_2d_composite


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


def read_particle_positions(ds):
    """
    Read super-droplet particle positions from plotfile dataset.

    Args:
        ds: yt dataset

    Returns:
        Numpy array of particle positions (N, 3) in meters, or None if no particles
    """
    pcname = "super_droplets_moisture"

    try:
        # Check if particle data exists
        particle_fields = [name for (_, name) in ds.field_list if name.startswith("particle_")]

        if not particle_fields:
            print(f"  No particle data found in plotfile")
            return None

        # Get particle position field names
        pos_fields = [
            (pcname, "particle_position_x"),
            (pcname, "particle_position_y"),
            (pcname, "particle_position_z")
        ]

        # Load particle data using covering grid
        cg = ds.covering_grid(0, ds.domain_left_edge, ds.domain_dimensions, fields=pos_fields)

        # Extract positions
        x_particles = np.array(cg[pos_fields[0]])  # In code units (cm)
        y_particles = np.array(cg[pos_fields[1]])
        z_particles = np.array(cg[pos_fields[2]])

        # Convert from cm to m
        x_particles = x_particles / 100.0
        y_particles = y_particles / 100.0
        z_particles = z_particles / 100.0

        # Stack into (N, 3) array
        positions = np.column_stack([x_particles, y_particles, z_particles])

        print(f"  Read {len(positions)} particles from plotfile")

        return positions

    except Exception as e:
        print(f"  WARNING: Could not read particles from plotfile: {e}")
        return None


def plot_superdroplet_fields(ds, time, output_file, domain_extent,
                             with_particles=False):
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
    """
    # Set up figure with proper aspect ratio
    # Plot region: x=[50, 150] (100m), z=[0, 100] (100m)
    plot_x_extent = 100.0  # 150 - 50
    plot_z_extent = domain_extent[2]  # Full z extent

    # For figure size: match the plot region aspect ratio
    plot_aspect = plot_x_extent / plot_z_extent

    # Create subplots - side-by-side if particles are included
    if with_particles:
        ncols = 2
        fig_height = 12
        fig_width = fig_height * plot_aspect * ncols
        fig, axes = plt.subplots(1, ncols, figsize=(fig_width, fig_height))
        axes = list(axes)  # Make it iterable
    else:
        fig_height = 12
        fig_width = fig_height * plot_aspect
        fig, axes = plt.subplots(1, 1, figsize=(fig_width, fig_height))
        axes = [axes]  # Make it iterable

    # Check if number density field exists
    available_fields = [name for (_, name) in ds.field_list]
    field_name = 'super_droplets_moisture_number_density'

    if field_name not in available_fields:
        print(f"  WARNING: {field_name} not found in dataset")
        print(f"  Available fields containing 'droplet': {[f for f in available_fields if 'droplet' in f.lower()]}")
        plt.close(fig)
        return

    # Extract 2D slice at midplane
    try:
        x, z, field_2d = get_midplane_slice(ds, field_name)
    except Exception as e:
        print(f"  ERROR extracting slice: {e}")
        plt.close(fig)
        return

    # Debug: check field statistics
    field_min = np.nanmin(field_2d) if np.any(np.isfinite(field_2d)) else np.nan
    field_max = np.nanmax(field_2d) if np.any(np.isfinite(field_2d)) else np.nan
    field_nonzero = np.sum(field_2d > 0)
    print(f"  Field stats: min={field_min:.2e}, max={field_max:.2e}, nonzero cells={field_nonzero}")

    # Get AMR mesh lines
    mesh_lines = get_amr_mesh_lines(ds)

    # ========================================================================
    # Panel 1: Number density with mesh overlay
    # ========================================================================
    ax = axes[0]

    # Plot number density as a color field
    extent = [x[0], x[-1], z[0], z[-1]]

    # Check if we have any non-zero data (use small threshold for floating point)
    threshold = 1e-15  # Increased threshold for better detection
    has_data = np.any(field_2d > threshold)

    # Mask zero/small values for better visualization
    field_plot = np.copy(field_2d)
    field_plot[field_plot < threshold] = np.nan

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
    ax.set_xlim(50, 150)  # Set x-axis range
    ax.set_aspect('equal')  # Equal physical scaling: 1m in x = 1m in z
    ax.tick_params(labelsize=18)

    # ========================================================================
    # Panel 2 (right): Particle positions (optional)
    # ========================================================================
    if with_particles:
        ax = axes[1]  # Second column

        # Try to read particle positions from the dataset
        particles = read_particle_positions(ds)

        if particles is not None and len(particles) > 0:
            # Extract x and z coordinates
            x_particles = particles[:, 0]
            y_particles = particles[:, 1]
            z_particles = particles[:, 2]

            # Plot particles as dots/points (no mesh overlay)
            ax.scatter(x_particles, z_particles, s=0.1, c='black', alpha=0.3,
                      edgecolors='none', rasterized=True)

            ax.set_xlim(50, 150)  # Set x-axis range
            ax.set_ylim(extent[2], extent[3])
            ax.set_xlabel('X (m)', fontsize=22)
            ax.set_ylabel('Z (m)', fontsize=22)
            ax.set_title(f'Particle positions ({len(particles)} particles)', fontsize=26)
            ax.set_aspect('equal')  # Equal physical scaling: 1m in x = 1m in z
            ax.tick_params(labelsize=18)
            ax.set_facecolor('white')  # White background for particle plot
        else:
            # No particles found - show empty plot with message
            ax.set_facecolor('white')  # White background
            ax.text(0.5, 0.5, 'No particle data available',
                   ha='center', va='center', transform=ax.transAxes, fontsize=20,
                   color='gray')
            ax.set_xlim(50, 150)  # Set x-axis range
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
    available_vars = [name for (_, name) in ds.field_list]

    print(f"Domain extent: {domain_extent[0]:.1f} m x {domain_extent[1]:.1f} m x {domain_extent[2]:.1f} m")
    print(f"Max AMR level: {ds.max_level}")

    # Check for super-droplet fields
    sd_fields = [f for f in available_vars if 'droplet' in f.lower() or 'moisture' in f.lower()]
    if sd_fields:
        print(f"Super-droplet/moisture fields found: {sd_fields}")
    else:
        print("WARNING: No super-droplet or moisture fields found in plotfiles!")
        print(f"Available fields (first 10): {available_vars[:10]}")

    # Process each plotfile
    successful = 0
    failed = []

    for i, pltfile in enumerate(plotfiles):
        plotfile_name = os.path.basename(pltfile)
        print(f"\nProcessing {plotfile_name} ({i+1}/{len(plotfiles)})...")

        try:
            # Load data
            ds = yt.load(pltfile)
            time = float(ds.current_time)

            # Create plot
            output_file = os.path.join(output_dir, f'superdroplets_{plotfile_name}.png')
            plot_superdroplet_fields(ds, time, output_file, domain_extent,
                                    with_particles=with_particles)

            print(f"  Saved {output_file}")
            successful += 1
        except (OverflowError, RuntimeError, ValueError) as e:
            print(f"  ERROR: Failed to process {plotfile_name}: {type(e).__name__}: {e}")
            print(f"  Skipping this timestep and continuing...")
            failed.append(plotfile_name)
            continue

    print(f"\n{'='*70}")
    print(f"Summary: {successful}/{len(plotfiles)} plots created successfully")
    if failed:
        print(f"Failed plotfiles: {', '.join(failed)}")
        print(f"Note: This may be due to a yt bug with certain AMR structures.")
    print(f"Output directory: {output_dir}/")
    print(f"{'='*70}")


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
  With --with-particles:    Two panels side-by-side (density left, particles right)

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
