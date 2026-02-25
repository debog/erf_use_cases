#!/usr/bin/env python3
"""
Script to plot fields from ERF AMR simulations (dry and moist bubble cases).

This script creates 2D (x-z) plots showing:
  1. Field with AMR mesh overlay (super-droplet number density, qc, etc.)
  2. (Optional) Particle positions in the domain

Usage:
    python plot_superdroplets.py <run_directory> [options]

Examples:
    # Dry bubble with 8 parallel processes
    python plot_superdroplets.py .run_BF02_dry_bubble_AMR1.matrix.nproc00004 -p -n 8

    # Moist bubble with qc and mass-weighted particles, use all CPUs
    python plot_superdroplets.py .run_BF02_moist_bubble_SDM.matrix.nproc00004 -f qc -p --particle-mass-alpha -n 0
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
from multiprocessing import Pool, cpu_count
from functools import partial

# Disable yt info prints
yt.set_log_level("error")


def format_time(seconds):
    """Format time in seconds."""
    return f'{seconds:.1f} s'


def shorten_field_name(field_name):
    """
    Shorten long field names for use in filenames.

    Args:
        field_name: full field name

    Returns:
        shortened field name suitable for filenames
    """
    # Mapping of common long field names to short versions
    field_name_map = {
        'super_droplets_moisture_number_density': 'sd_num_dens',
        'super_droplets_number_density': 'sd_num_dens',
        'qc': 'qc',
        'qv': 'qv',
        'qt': 'qt',
        'theta': 'theta',
        'temperature': 'temp',
        'density': 'dens',
    }

    # Return mapped name if it exists
    if field_name in field_name_map:
        return field_name_map[field_name]

    # For other fields, create abbreviated version
    # Remove common prefixes
    short = field_name.replace('super_droplets_', 'sd_')
    short = short.replace('moisture_', 'moist_')
    short = short.replace('number_density', 'num_dens')
    short = short.replace('mixing_ratio', 'mix_ratio')

    # If still too long (>20 chars), truncate intelligently
    if len(short) > 20:
        # Keep first 20 characters
        short = short[:20]

    return short


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

    Manually composites by extracting data from each grid patch.

    Args:
        ds: yt dataset
        field_name: name of the field to extract

    Returns:
        Tuple of (x_coords, z_coords, field_2d) where field_2d is at y-midplane
    """
    from scipy.ndimage import zoom

    max_level = ds.max_level
    base_dims = ds.domain_dimensions
    field_tuple = ('boxlib', field_name)

    # Calculate finest resolution dimensions
    dims_finest = base_dims * (2 ** max_level) if max_level > 0 else base_dims

    # Get coordinates at finest level
    x_fine = np.linspace(float(ds.domain_left_edge[0].to('m').value),
                        float(ds.domain_right_edge[0].to('m').value),
                        dims_finest[0])
    z_fine = np.linspace(float(ds.domain_left_edge[2].to('m').value),
                        float(ds.domain_right_edge[2].to('m').value),
                        dims_finest[2])

    # Initialize output array
    field_2d_composite = np.zeros((dims_finest[2], dims_finest[0]))

    # Track which level owns each cell (starts at -1 = unassigned)
    level_owner = -np.ones((dims_finest[2], dims_finest[0]), dtype=int)

    # Domain info for coordinate conversion
    domain_left_x = float(ds.domain_left_edge[0].to('m').value)
    domain_left_z = float(ds.domain_left_edge[2].to('m').value)
    domain_width_x = float(ds.domain_width[0].to('m').value)
    domain_width_z = float(ds.domain_width[2].to('m').value)

    # First pass: mark which cells belong to which level (finest wins)
    for level in range(max_level, -1, -1):  # Process from finest to coarsest for marking
        grids_at_level = [g for g in ds.index.grids if g.Level == level]

        for grid in grids_at_level:
            left_x, left_y, left_z = grid.LeftEdge.to('m').value
            right_x, right_y, right_z = grid.RightEdge.to('m').value

            # Convert to indices at finest resolution
            i_start = int(np.round((left_x - domain_left_x) / domain_width_x * dims_finest[0]))
            i_end = int(np.round((right_x - domain_left_x) / domain_width_x * dims_finest[0]))
            k_start = int(np.round((left_z - domain_left_z) / domain_width_z * dims_finest[2]))
            k_end = int(np.round((right_z - domain_left_z) / domain_width_z * dims_finest[2]))

            # Mark cells owned by this level (only if not already claimed by finer level)
            mask = level_owner[k_start:k_end, i_start:i_end] < level
            level_owner[k_start:k_end, i_start:i_end][mask] = level

    # Second pass: place data only in cells owned by each level
    for level in range(max_level + 1):
        grids_at_level = [g for g in ds.index.grids if g.Level == level]

        if len(grids_at_level) == 0:
            continue

        for grid_idx, grid in enumerate(grids_at_level):
            # Extract data directly from this grid
            grid_data = np.array(grid[field_tuple])  # Shape: (nx, ny, nz)
            y_mid_idx = grid_data.shape[1] // 2
            grid_slice = grid_data[:, y_mid_idx, :].T  # Shape: (nz, nx)

            # Get grid boundaries in physical space
            left_x, left_y, left_z = grid.LeftEdge.to('m').value
            right_x, right_y, right_z = grid.RightEdge.to('m').value

            # Convert to indices at finest resolution
            i_start = int(np.round((left_x - domain_left_x) / domain_width_x * dims_finest[0]))
            i_end = int(np.round((right_x - domain_left_x) / domain_width_x * dims_finest[0]))
            k_start = int(np.round((left_z - domain_left_z) / domain_width_z * dims_finest[2]))
            k_end = int(np.round((right_z - domain_left_z) / domain_width_z * dims_finest[2]))

            # Upsample this grid's data to finest resolution if needed
            if level < max_level:
                zoom_factor = 2 ** (max_level - level)
                grid_slice_upsampled = zoom(grid_slice, zoom_factor, order=0)
            else:
                grid_slice_upsampled = grid_slice

            # Place data only where this level owns the cells
            owner_mask = level_owner[k_start:k_end, i_start:i_end] == level

            # Use np.where or copyto to ensure proper assignment
            region = field_2d_composite[k_start:k_end, i_start:i_end].copy()
            region[owner_mask] = grid_slice_upsampled[owner_mask]
            field_2d_composite[k_start:k_end, i_start:i_end] = region

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


def read_particle_positions(ds, read_mass=False):
    """
    Read super-droplet particle positions from plotfile dataset.

    Args:
        ds: yt dataset
        read_mass: whether to also read particle mass data

    Returns:
        If read_mass=False: Numpy array of particle positions (N, 3) in meters, or None if no particles
        If read_mass=True: Tuple of (positions, masses) or (None, None) if no particles
    """
    pcname = "super_droplets_moisture"

    try:
        # Check if particle data exists
        particle_fields = [name for (_, name) in ds.field_list if name.startswith("particle_")]

        if not particle_fields:
            print(f"  No particle data found in plotfile")
            return (None, None) if read_mass else None

        # Use all_data() to get particles from all AMR levels
        ad = ds.all_data()

        # Get particle position field names
        pos_x_field = (pcname, "particle_position_x")
        pos_y_field = (pcname, "particle_position_y")
        pos_z_field = (pcname, "particle_position_z")

        # Extract positions - this gets particles from all AMR levels
        x_particles = np.array(ad[pos_x_field])  # In code units (cm)
        y_particles = np.array(ad[pos_y_field])
        z_particles = np.array(ad[pos_z_field])

        # Convert from cm to m
        x_particles = x_particles / 100.0
        y_particles = y_particles / 100.0
        z_particles = z_particles / 100.0

        # Stack into (N, 3) array
        positions = np.column_stack([x_particles, y_particles, z_particles])

        print(f"  Read {len(positions)} particles from plotfile")

        if read_mass:
            # Try to read particle mass - check multiple possible field names
            possible_mass_fields = [
                (pcname, "particle_particle_mass"),
                (pcname, "particle_mass"),
                (pcname, "particle_species_mass_H2O"),
                (pcname, "particle_species_mass_ice"),
            ]

            masses = None
            for mass_field in possible_mass_fields:
                try:
                    masses = np.array(ad[mass_field])
                    print(f"  Read particle masses from {mass_field[1]}: min={np.min(masses):.2e}, max={np.max(masses):.2e}")
                    return positions, masses
                except:
                    continue

            # If none worked, list available particle fields
            if masses is None:
                particle_field_names = [name for (ptype, name) in ds.field_list if ptype == pcname]
                print(f"  WARNING: Could not find particle mass field")
                print(f"  Available {pcname} fields: {particle_field_names}")
                return positions, None
        else:
            return positions

    except Exception as e:
        print(f"  WARNING: Could not read particles from plotfile: {e}")
        import traceback
        traceback.print_exc()
        return (None, None) if read_mass else None


def plot_superdroplet_fields(ds, time, output_file, domain_extent,
                             with_particles=False, field_name='super_droplets_moisture_number_density',
                             particle_mass_alpha=False, use_logscale=False):
    """
    Create a 2-panel plot showing:
      1. Field with AMR mesh
      2. (Optional) Particle positions

    Args:
        ds: yt dataset
        time: simulation time
        output_file: path to save the plot
        domain_extent: tuple of (x_extent, y_extent, z_extent) in meters
        with_particles: whether to include particle plot
        field_name: name of field to plot (default: super_droplets_moisture_number_density)
        particle_mass_alpha: whether to use particle mass for transparency (log scale)
        use_logscale: whether to use logarithmic scale for field plotting (default: False)
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
        # Set figure background to avoid conflict with white text on particle panel
        fig.patch.set_facecolor('white')
    else:
        fig_height = 12
        fig_width = fig_height * plot_aspect
        fig, axes = plt.subplots(1, 1, figsize=(fig_width, fig_height))
        axes = [axes]  # Make it iterable
        fig.patch.set_facecolor('white')

    # Check if field exists
    available_fields = [name for (_, name) in ds.field_list]

    if field_name not in available_fields:
        print(f"  WARNING: {field_name} not found in dataset")
        print(f"  Available fields: {available_fields[:20]}")
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
    field_min_raw = np.nanmin(field_2d) if np.any(np.isfinite(field_2d)) else np.nan
    field_max_raw = np.nanmax(field_2d) if np.any(np.isfinite(field_2d)) else np.nan
    field_nonzero = np.sum(field_2d > 0)
    has_negative_or_zero = np.any(field_2d <= 0)
    if use_logscale and has_negative_or_zero:
        n_invalid = np.sum(field_2d <= 0)
        print(f"  Field stats: min={field_min_raw:.2e}, max={field_max_raw:.2e}, nonzero cells={field_nonzero} ({n_invalid} zero/negative cells shown as background)")
    else:
        print(f"  Field stats: min={field_min_raw:.2e}, max={field_max_raw:.2e}, nonzero cells={field_nonzero}")

    # Get AMR mesh lines
    mesh_lines = get_amr_mesh_lines(ds)

    # ========================================================================
    # Panel 1: Number density with mesh overlay
    # ========================================================================
    ax = axes[0]

    # Plot number density as a color field
    extent = [x[0], x[-1], z[0], z[-1]]

    # Get min/max for colormap
    field_min = np.min(field_2d)
    field_max = np.max(field_2d)

    # Use log scale if requested
    if use_logscale and field_max > 0:
        from matplotlib.colors import LogNorm
        import matplotlib

        # Create a masked array: mask out zero and negative values
        field_masked = np.ma.masked_where(field_2d <= 0, field_2d)

        # Get min/max of positive values only
        if np.any(field_2d > 0):
            nonzero_min = np.min(field_2d[field_2d > 0])
            vmin = nonzero_min / 10.0  # Set vmin slightly lower than actual minimum
            vmax = field_max

            # Create colormap with a distinct color for masked (invalid) values
            cmap = matplotlib.colormaps['coolwarm'].copy()
            cmap.set_bad(color='lightgray', alpha=0.3)  # Light gray background for invalid values

            im = ax.imshow(field_masked, extent=extent, aspect='auto', origin='lower',
                          cmap=cmap, interpolation='bilinear', norm=LogNorm(vmin=vmin, vmax=vmax))
        else:
            # Fallback if no positive values
            im = ax.imshow(field_2d, extent=extent, aspect='auto', origin='lower',
                          cmap='coolwarm', interpolation='bilinear', vmin=field_min, vmax=field_max)
    else:
        # Linear scale (default)
        im = ax.imshow(field_2d, extent=extent, aspect='auto', origin='lower',
                      cmap='coolwarm', interpolation='bilinear', vmin=field_min, vmax=field_max)

    # Add colorbar with better styling
    cbar = plt.colorbar(im, ax=ax, pad=0.02, fraction=0.046)
    # Set colorbar label based on field name
    if 'number_density' in field_name:
        cbar_label = 'Number density (#/m³)'
    elif field_name == 'qc':
        cbar_label = 'qc (kg/kg)'
    else:
        cbar_label = field_name
    cbar.set_label(cbar_label, fontsize=20)
    cbar.ax.tick_params(labelsize=16)

    # Overlay computational mesh with thin dark grey lines (almost black)
    lc = LineCollection(mesh_lines, colors='#222222', linewidths=0.3, alpha=0.8)
    ax.add_collection(lc)

    ax.set_xlabel('X (m)', fontsize=22)
    ax.set_ylabel('Z (m)', fontsize=22)
    # Set title based on field name
    if 'number_density' in field_name:
        title = f'Super-droplet number density, t = {format_time(time)}'
    elif field_name == 'qc':
        title = f'Cloud water mixing ratio (qc), t = {format_time(time)}'
    else:
        title = f'{field_name}, t = {format_time(time)}'
    ax.set_title(title, fontsize=26)
    ax.set_xlim(50, 150)  # Set x-axis range
    ax.set_aspect('equal')  # Equal physical scaling: 1m in x = 1m in z
    ax.tick_params(labelsize=18)

    # ========================================================================
    # Panel 2 (right): Particle positions (optional)
    # ========================================================================
    if with_particles:
        ax = axes[1]  # Second column

        # Try to read particle positions (and masses if needed) from the dataset
        if particle_mass_alpha:
            particles, masses = read_particle_positions(ds, read_mass=True)
        else:
            particles = read_particle_positions(ds, read_mass=False)
            masses = None

        if particles is not None and len(particles) > 0:
            # Extract x and z coordinates
            x_particles = particles[:, 0]
            y_particles = particles[:, 1]
            z_particles = particles[:, 2]

            if particle_mass_alpha and masses is not None:
                # Use log-scaled mass for alpha values
                log_masses = np.log10(masses + 1e-30)  # Add small value to avoid log(0)
                # Normalize to [0.1, 0.9] range for alpha
                alpha_min, alpha_max = 0.1, 0.9
                log_min = np.min(log_masses)
                log_max = np.max(log_masses)
                if log_max > log_min:
                    alphas = alpha_min + (alpha_max - alpha_min) * (log_masses - log_min) / (log_max - log_min)
                else:
                    alphas = 0.5 * np.ones_like(log_masses)

                # Plot particles with mass-based transparency
                for i in range(len(x_particles)):
                    ax.scatter(x_particles[i], z_particles[i], s=0.1, c='white',
                              alpha=alphas[i], edgecolors='none', rasterized=True)
                print(f"  Particle mass range: {np.min(masses):.2e} to {np.max(masses):.2e}")
                print(f"  Alpha range: {np.min(alphas):.2f} to {np.max(alphas):.2f}")
            else:
                # Plot particles as uniform bright white dots on black background
                ax.scatter(x_particles, z_particles, s=0.1, c='white', alpha=0.3,
                          edgecolors='none', rasterized=True)

            ax.set_xlim(50, 150)  # Set x-axis range
            ax.set_ylim(extent[2], extent[3])
            ax.set_xlabel('X (m)', fontsize=22)
            ax.set_ylabel('Z (m)', fontsize=22)
            title_suffix = ' (mass-weighted)' if (particle_mass_alpha and masses is not None) else ''
            ax.set_title(f'Particle positions ({len(particles)} particles){title_suffix}', fontsize=26)
            ax.set_aspect('equal')  # Equal physical scaling: 1m in x = 1m in z
            ax.tick_params(labelsize=18)
            ax.set_facecolor('black')  # Black background for particle plot
        else:
            # No particles found - show empty plot with message
            ax.set_facecolor('black')  # Black background
            ax.text(0.5, 0.5, 'No particle data available',
                   ha='center', va='center', transform=ax.transAxes, fontsize=20,
                   color='lightgray')
            ax.set_xlim(50, 150)  # Set x-axis range
            ax.set_ylim(extent[2], extent[3])
            ax.set_xlabel('X (m)', fontsize=22)
            ax.set_ylabel('Z (m)', fontsize=22)
            ax.set_title('Particle positions', fontsize=26)
            ax.set_aspect('equal')  # Equal physical scaling: 1m in x = 1m in z
            ax.tick_params(labelsize=18)

    plt.tight_layout(pad=2.0)
    # Use facecolor='white' for figure background to avoid conflicts
    plt.savefig(output_file, dpi=300, bbox_inches='tight', facecolor='white')
    plt.close(fig)


def process_single_plotfile(args):
    """
    Worker function to process a single plotfile.

    Args:
        args: tuple of (pltfile, output_dir, domain_extent, with_particles,
                       field_name, particle_mass_alpha, use_logscale, i, total)

    Returns:
        tuple of (success, plotfile_name, error_message, skipped)
    """
    pltfile, output_dir, domain_extent, with_particles, field_name, particle_mass_alpha, use_logscale, i, total = args
    plotfile_name = os.path.basename(pltfile)
    short_field = shorten_field_name(field_name)

    try:
        # Check if output already exists and is newer than input
        output_file = os.path.join(output_dir, f'{short_field}_{plotfile_name}.png')

        if os.path.exists(output_file):
            output_mtime = os.path.getmtime(output_file)
            pltfile_mtime = os.path.getmtime(pltfile)

            if output_mtime > pltfile_mtime:
                print(f"\nSkipping {plotfile_name} ({i+1}/{total}) - plot is up to date")
                return (True, plotfile_name, None, True)

        print(f"\nProcessing {plotfile_name} ({i+1}/{total})...")

        # Load data
        ds = yt.load(pltfile)
        time = float(ds.current_time)

        # Create plot
        plot_superdroplet_fields(ds, time, output_file, domain_extent,
                                with_particles=with_particles,
                                field_name=field_name,
                                particle_mass_alpha=particle_mass_alpha,
                                use_logscale=use_logscale)

        print(f"  Saved {output_file}")
        return (True, plotfile_name, None, False)

    except (OverflowError, RuntimeError, ValueError) as e:
        error_msg = f"{type(e).__name__}: {e}"
        print(f"  ERROR: Failed to process {plotfile_name}: {error_msg}")
        print(f"  Skipping this timestep and continuing...")
        return (False, plotfile_name, error_msg, False)


def plot_all_timesteps(run_dir, output_dir, with_particles=False,
                       field_name='super_droplets_moisture_number_density',
                       particle_mass_alpha=False, use_logscale=False, num_procs=1):
    """
    Plot fields from all timesteps in a run directory.

    Args:
        run_dir: path to the run directory containing plt* subdirectories
        output_dir: directory to save plots (will be created if doesn't exist)
        with_particles: whether to include particle position plots
        field_name: name of field to plot
        particle_mass_alpha: whether to use particle mass for transparency
        use_logscale: whether to use logarithmic scale for field plotting
        num_procs: number of parallel processes to use (1 = serial)
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

    # Check if requested field exists
    if field_name not in available_vars:
        print(f"ERROR: Field '{field_name}' not found in plotfiles!")
        print(f"Available fields: {available_vars}")
        return

    # Check for super-droplet fields
    sd_fields = [f for f in available_vars if 'droplet' in f.lower() or 'moisture' in f.lower() or 'qc' in f.lower() or 'qv' in f.lower()]
    if sd_fields:
        print(f"Relevant fields found: {sd_fields}")
    else:
        print("WARNING: No droplet/moisture/qc fields found in plotfiles!")
        print(f"Available fields (first 20): {available_vars[:20]}")

    # Prepare arguments for parallel processing
    total = len(plotfiles)
    args_list = [
        (pltfile, output_dir, domain_extent, with_particles, field_name,
         particle_mass_alpha, use_logscale, i, total)
        for i, pltfile in enumerate(plotfiles)
    ]

    # Process plotfiles
    if num_procs > 1:
        print(f"\nUsing {num_procs} parallel processes...")
        with Pool(processes=num_procs) as pool:
            results = pool.map(process_single_plotfile, args_list)
    else:
        print(f"\nProcessing sequentially (use -n/--num-procs for parallelization)...")
        results = [process_single_plotfile(args) for args in args_list]

    # Collect results
    successful = sum(1 for success, _, _, _ in results if success)
    skipped = sum(1 for success, _, _, skip in results if success and skip)
    failed = [(name, err) for success, name, err, _ in results if not success]

    print(f"\n{'='*70}")
    print(f"Summary: {successful}/{len(plotfiles)} plots successful")
    if skipped > 0:
        print(f"  - {skipped} skipped (already up to date)")
        print(f"  - {successful - skipped} newly created")
    if failed:
        print(f"Failed plotfiles ({len(failed)}):")
        for name, err in failed[:5]:  # Show first 5
            print(f"  - {name}: {err}")
        if len(failed) > 5:
            print(f"  ... and {len(failed)-5} more")
    print(f"Output directory: {output_dir}/")
    print(f"{'='*70}")


def main():
    parser = argparse.ArgumentParser(
        description="""
Plot fields from ERF AMR simulations (dry or moist bubble cases).

This script creates 2D (x-z) plots at the y-midplane showing:
  1. Field with AMR mesh overlay (super-droplet number density, qc, etc.)
  2. (Optional) Particle positions in the domain (-p/--with-particles)

For moist bubble cases, use -f qc to plot cloud water mixing ratio.
For particle visualization, use --particle-mass-alpha for mass-weighted transparency.

The plots maintain the physical aspect ratio of the simulation domain and are
suitable for quasi-2D simulations (e.g., ny=4 cells in y-direction).
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry bubble with super-droplet number density
  %(prog)s .run_BF02_dry_bubble_AMR1.matrix.nproc00004

  # With particles, using 8 parallel processes
  %(prog)s .run_BF02_dry_bubble_AMR1.matrix.nproc00004 -p -n 8

  # Moist bubble with qc field
  %(prog)s .run_BF02_moist_bubble_SDM.matrix.nproc00004 -f qc

  # With logarithmic scale for number density
  %(prog)s .run_BF02_dry_bubble_AMR1.matrix.nproc00004 -l

  # Moist bubble with particles showing mass-weighted transparency, use all CPUs
  %(prog)s .run_BF02_moist_bubble_SDM.matrix.nproc00004 -f qc -p --particle-mass-alpha -n 0

  # Custom output directory
  %(prog)s .run_BF02_dry_bubble_AMR1.matrix.nproc00004 -o custom_plots

Output:
  Creates one PNG file per timestep in the output directory:
  - <field>_plt*.png : 2D plots showing field with AMR mesh
                       and optionally particle positions
  Examples: sd_num_dens_plt00100.png, qc_plt00100.png

Plot Layout:
  Without -p/--with-particles: Single panel showing field with mesh
  With -p/--with-particles:    Two panels side-by-side (field left, particles right)

Requirements:
  Python packages: yt, numpy, matplotlib
  Install: pip install yt numpy matplotlib

Technical Details:
  - Extracts 2D slice at y-midplane (index ny//2)
  - Uses 'coolwarm' colormap (blue=low, white=mid, red=high)
  - Linear scale by default; use -l/--logscale for logarithmic scale
  - Bilinear interpolation for smooth rendering
  - Computational mesh shown as thin dark lines (#222222, linewidth=0.3, alpha=0.8)
  - All cell edges rendered at all AMR levels
  - Particles read from plotfile datasets
  - Physical aspect ratio preserved with ax.set_aspect('equal')
  - Supports parallel processing across plotfiles using multiprocessing

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
    parser.add_argument('-p', '--with-particles', action='store_true',
                       help='Include particle position plots in second panel')
    parser.add_argument('-f', '--field', dest='field_name',
                       default='super_droplets_moisture_number_density',
                       help='Field to plot (default: super_droplets_moisture_number_density, for moist cases use: qc)')
    parser.add_argument('--particle-mass-alpha', action='store_true',
                       help='Use particle mass for transparency (log scale) in particle plot')
    parser.add_argument('-l', '--logscale', action='store_true',
                       help='Use logarithmic scale for field plotting (default: linear scale)')
    parser.add_argument('-n', '--num-procs', dest='num_procs', type=int, default=1,
                       help='Number of parallel processes to use (default: 1, use 0 for all available CPUs)')

    args = parser.parse_args()

    run_dir = args.run_directory
    output_dir = args.output_dir if args.output_dir else os.path.join(run_dir, 'plots')

    if not os.path.isdir(run_dir):
        print(f"Error: {run_dir} is not a valid directory")
        sys.exit(1)

    # Handle num_procs = 0 (use all available CPUs)
    num_procs = args.num_procs
    if num_procs == 0:
        num_procs = cpu_count()
        print(f"Using all available CPUs: {num_procs}")
    elif num_procs < 0:
        print(f"Error: num_procs must be >= 0 (got {num_procs})")
        sys.exit(1)

    print("=" * 70)
    print("ERF Super-Droplet Plotting Script")
    print("=" * 70)
    print(f"Processing run directory: {run_dir}")
    print(f"Output directory: {output_dir}")
    print(f"Field to plot: {args.field_name}")
    print(f"Field scale: {'logarithmic' if args.logscale else 'linear'}")
    print(f"Include particles: {args.with_particles}")
    if args.with_particles and args.particle_mass_alpha:
        print(f"Particle transparency: mass-weighted (log scale)")
    elif args.with_particles:
        print(f"Particle transparency: uniform")
    if num_procs > 1:
        print(f"Parallel processes: {num_procs}")
    print("=" * 70)

    plot_all_timesteps(run_dir, output_dir, with_particles=args.with_particles,
                      field_name=args.field_name, particle_mass_alpha=args.particle_mass_alpha,
                      use_logscale=args.logscale, num_procs=num_procs)

    print("\nDone!")


if __name__ == '__main__':
    main()
