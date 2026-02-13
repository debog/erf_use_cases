#!/usr/bin/env python3
"""
Script to plot microphysics quantities from ERF simulations at each timestep.

Usage: python plot_microphysics.py <run_directory> [output_dir]
    Ex: python plot_microphysics.py .run_sdm_bimodal_amsu.matrix.nproc00004
"""

import yt
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import sys
import os
from glob import glob

# Disable yt info prints
yt.set_log_level("error")

# Microphysics variables - q quantities
Q_VARS = ['qv', 'qc', 'qi', 'qrain', 'qsnow', 'qgraup', 'qt']

# Variables to overlay (all q except qv)
OVERLAY_VARS = ['qc', 'qi', 'qrain', 'qsnow', 'qgraup']

# Color scheme for each variable (bright, saturated for dark background)
COLORS = {
    'qc': np.array([0.6, 0.6, 0.6]),      # Light grey - cloud water
    'qi': np.array([1.0, 1.0, 1.0]),      # White - ice
    'qrain': np.array([0.3, 0.5, 1.0]),   # Bright blue - rain
    'qsnow': np.array([1.0, 0.4, 0.8]),   # Pink/magenta - snow
    'qgraup': np.array([1.0, 0.6, 0.0])   # Bright orange - graupel
}

# Gamma exponent for power-law alpha scaling (< 1 enhances weak features)
GAMMA = 0.4

# Opacity scaling factors (dim dominant species to let others show)
CLOUD_OPACITY = 0.3
GRAUPEL_OPACITY = 0.5

# Display labels for variables
LABELS = {
    'qc': 'cloud',
    'qi': 'ice',
    'qrain': 'rain',
    'qsnow': 'snow',
    'qgraup': 'graupel'
}

def format_time(seconds):
    """Format time as seconds or minutes depending on magnitude."""
    if seconds < 120:
        return f'{seconds:.1f} s'
    return f'{seconds / 60:.1f} min'

def normalize_field(field_data, min_threshold=1e-8, gamma=1.0):
    """
    Normalize field data to [0, 1] for alpha channel with power-law scaling.
    Values below min_threshold are set to 0.

    Args:
        field_data: numpy array of field values
        min_threshold: minimum value to consider (below this is 0)
        gamma: power-law exponent (< 1 enhances weak features, > 1 suppresses)

    Returns:
        Normalized array with values in [0, 1]
    """
    data = np.copy(field_data)
    data[data < min_threshold] = 0

    max_val = np.nanmax(data)
    if max_val > 0:
        data = data / max_val

    # Apply gamma correction
    if gamma != 1.0:
        mask = data > 0
        data[mask] = data[mask] ** gamma

    return data

def plot_composite_microphysics(cg, var_list, time, output_file, domain_extent):
    """
    Create a composite plot with multiple microphysics variables overlaid
    on a dark background. Each variable has its own color, with gamma-corrected
    transparency indicating magnitude. Cloud is dimmed to let other species show.

    Args:
        cg: yt covering grid object
        var_list: list of variable names to overlay
        time: simulation time
        output_file: path to save the plot
        domain_extent: tuple of (x_extent, y_extent, z_extent) in meters
    """
    # Get coordinates (convert from cm to m)
    x = np.array(cg['x'][:, 0, 0]) / 1e2  # cm to m
    y = np.array(cg['y'][0, :, 0]) / 1e2
    z = np.array(cg['z'][0, 0, :]) / 1e2

    # Set up figure with proper aspect ratio
    x_extent_m = domain_extent[0]
    z_extent_m = domain_extent[2]
    aspect_ratio = x_extent_m / z_extent_m

    fig_height = 12
    fig_width = fig_height * aspect_ratio * 1.2

    # Dark style
    with plt.style.context('dark_background'):
        fig, ax = plt.subplots(figsize=(fig_width, fig_height))
        fig.set_facecolor('black')
        ax.set_facecolor('black')

        # Create RGB image (composited onto black background directly)
        nx, nz = len(x), len(z)
        rgb_image = np.zeros((nz, nx, 3))

        # Track which variables are actually present
        present_vars = []

        # Render cloud first as a dim base layer, then other species on top
        for var in var_list:
            present_vars.append(var)

            # Get 3D field and average over y-direction
            field_3d = np.array(cg[('boxlib', var)])  # Shape: (nx, ny, nz)
            field_2d = np.mean(field_3d, axis=1).T  # (nz, nx)

            # Normalize with gamma correction
            alpha = normalize_field(field_2d, min_threshold=1e-8, gamma=GAMMA)

            # Dim dominant species so they don't overwhelm others
            if var == 'qc':
                alpha *= CLOUD_OPACITY
            elif var == 'qgraup':
                alpha *= GRAUPEL_OPACITY

            # Get RGB color for this variable
            rgb = COLORS[var]

            # Additive blending onto black background
            for i in range(3):
                rgb_image[:, :, i] += rgb[i] * alpha

        # Clip to valid range
        rgb_image = np.clip(rgb_image, 0, 1)

        # Plot the composite image
        extent = [x[0], x[-1], z[0], z[-1]]
        ax.imshow(rgb_image, extent=extent, aspect='auto', origin='lower',
                  interpolation='nearest')

        ax.set_xlabel('X (m)', fontsize=14)
        ax.set_ylabel('Z (m)', fontsize=14)
        ax.set_title(f'Mixing ratios at t = {format_time(time)}', fontsize=16)

        # Extend y-axis to leave room for the legend above the data
        z_range = z[-1] - z[0]
        ax.set_ylim(z[0], z[-1] + 0.15 * z_range)

        # Set aspect ratio to match physical domain
        ax.set_aspect(aspect_ratio)

        # Create legend with dark styling
        from matplotlib.patches import Patch
        legend_elements = [Patch(facecolor=COLORS[var], label=LABELS[var])
                          for var in present_vars]
        leg = ax.legend(handles=legend_elements, loc='upper right', fontsize=11,
                 title='Brightness $\\propto$ magnitude',
                 title_fontsize=9, facecolor='#1a1a1a', edgecolor='#444444',
                 framealpha=0.9)
        leg.get_title().set_color('white')
        for text in leg.get_texts():
            text.set_color('white')

        plt.tight_layout()
        plt.savefig(output_file, dpi=300, bbox_inches='tight',
                    facecolor='black')
        plt.close(fig)

def plot_qv_separately(cg, time, output_file, domain_extent):
    """
    Plot water vapor (qv) separately since it has different scale.

    Args:
        cg: yt covering grid object
        time: simulation time
        output_file: path to save the plot
        domain_extent: tuple of (x_extent, y_extent, z_extent) in meters
    """
    # Get coordinates (convert from cm to m)
    x = np.array(cg['x'][:, 0, 0]) / 1e2
    z = np.array(cg['z'][0, 0, :]) / 1e2

    # Get field and average over y-direction
    field_3d = np.array(cg[('boxlib', 'qv')])
    field_2d = np.mean(field_3d, axis=1).T  # (nz, nx)

    # Set up figure with proper aspect ratio
    x_extent_m = domain_extent[0]
    z_extent_m = domain_extent[2]
    aspect_ratio = x_extent_m / z_extent_m

    fig_height = 12
    fig_width = fig_height * aspect_ratio * 1.2

    fig, ax = plt.subplots(figsize=(fig_width, fig_height))

    # Create RGBA image with red/orange color and transparency based on magnitude
    nz, nx = field_2d.shape
    rgba_image = np.zeros((nz, nx, 4))

    # Normalize field for transparency
    alpha = normalize_field(field_2d, min_threshold=1e-8)

    # Use orange-red color [1.0, 0.4, 0.0] (orange-red)
    rgba_image[:, :, 0] = 1.0 * alpha  # Red channel
    rgba_image[:, :, 1] = 0.4 * alpha  # Green channel
    rgba_image[:, :, 2] = 0.0 * alpha  # Blue channel
    rgba_image[:, :, 3] = alpha        # Alpha channel

    extent = [x[0], x[-1], z[0], z[-1]]
    im = ax.imshow(rgba_image, extent=extent, aspect='auto', origin='lower',
                   interpolation='bilinear')

    ax.set_xlabel('X (m)', fontsize=14)
    ax.set_ylabel('Z (m)', fontsize=14)
    ax.set_title(f'Vapour mixing ratio at t = {format_time(time)}', fontsize=16)

    # Extend y-axis to leave room above the data
    z_range = z[-1] - z[0]
    ax.set_ylim(z[0], z[-1] + 0.5 * z_range)

    ax.set_aspect(aspect_ratio)

    # Create a colorbar for reference (showing actual values)
    # Use a dummy mappable for the colorbar
    from matplotlib.cm import ScalarMappable
    from matplotlib.colors import Normalize
    vmin = np.nanmin(field_2d[field_2d > 1e-8])
    vmax = np.nanmax(field_2d)
    norm = Normalize(vmin=vmin, vmax=vmax)
    sm = ScalarMappable(cmap='Oranges', norm=norm)
    sm.set_array([])

    cbar = plt.colorbar(sm, ax=ax, pad=0.02, fraction=0.046)
    cbar.set_label('qv (kg/kg)', fontsize=12)

    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close(fig)

def get_domain_extent(ds):
    """
    Extract physical domain extent from yt dataset.

    Returns:
        Tuple of (x_extent, y_extent, z_extent) in meters
    """
    domain_width = ds.domain_width.to('m').value
    return tuple(domain_width)

def plot_all_microphysics(run_dir, output_dir):
    """
    Plot all microphysics variables from all timesteps in a run directory.

    Args:
        run_dir: path to the run directory containing plt* subdirectories
        output_dir: directory to save plots (will be created if doesn't exist)
    """
    # Find all plotfiles
    plotfiles = sorted(glob(os.path.join(run_dir, 'plt*')))

    if not plotfiles:
        print(f"No plotfiles found in {run_dir}")
        return

    print(f"Found {len(plotfiles)} plotfiles")

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Get available variables from first plotfile
    print("Loading first plotfile to check available variables...")
    ds = yt.load(plotfiles[0])
    available_vars = [name for (_, name) in ds.field_list]
    domain_extent = get_domain_extent(ds)

    print(f"Domain extent: {domain_extent[0]:.1f} m x {domain_extent[1]:.1f} m x {domain_extent[2]:.1f} m")

    # Filter to only available q variables
    q_vars_available = [var for var in Q_VARS if var in available_vars]
    overlay_vars_available = [var for var in OVERLAY_VARS if var in available_vars]

    if not q_vars_available:
        print("Warning: No q variables found in plotfiles")
        print(f"Available variables: {available_vars}")
        return

    print(f"Will plot the following q variables: {q_vars_available}")
    print(f"Composite overlay will include: {overlay_vars_available}")

    # Process each plotfile
    for i, pltfile in enumerate(plotfiles):
        print(f"\nProcessing {os.path.basename(pltfile)} ({i+1}/{len(plotfiles)})...")

        # Load data
        ds = yt.load(pltfile)
        time = float(ds.current_time)

        # Create covering grid with all q variables
        cg = ds.covering_grid(0, ds.domain_left_edge, ds.domain_dimensions,
                             fields=q_vars_available)

        # Force preload all data
        for var in q_vars_available:
            cg[('boxlib', var)]

        # Create composite plot if there are overlay variables
        if overlay_vars_available:
            output_file = os.path.join(output_dir,
                                      f'composite_{os.path.basename(pltfile)}.png')
            plot_composite_microphysics(cg, overlay_vars_available, time,
                                       output_file, domain_extent)

        # Create qv plot separately
        if 'qv' in q_vars_available:
            output_file_qv = os.path.join(output_dir,
                                         f'qv_{os.path.basename(pltfile)}.png')
            plot_qv_separately(cg, time, output_file_qv, domain_extent)

        print(f"  Saved plots to {output_dir}/")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("=" * 70)
        print("ERF Microphysics Plotting Script")
        print("=" * 70)
        print("\nUsage: python plot_microphysics.py <run_directory> [output_dir]")
        print("\nArguments:")
        print("  run_directory  : Path to ERF run directory containing plt* subdirectories")
        print("  output_dir     : (Optional) Output directory for plots")
        print("                   Default: <run_directory>/plots")
        print("\nExamples:")
        print("  python plot_microphysics.py .run_sdm_bimodal_amsu.matrix.nproc00004")
        print("  python plot_microphysics.py .run_sdm_bimodal_amsu.matrix.nproc00004 ./my_plots")
        print("\nOutput:")
        print("  - composite_plt*.png : Overlaid mixing ratios (cloud, ice, rain,")
        print("                         snow, graupel) with color-coded transparency")
        print("  - qv_plt*.png        : Vapour mixing ratio plotted separately")
        print("\nColor scheme:")
        print("  cloud (qc)       : Dark grey")
        print("  ice (qi)         : White")
        print("  rain (qrain)     : Blue")
        print("  snow (qsnow)     : Pink/magenta")
        print("  graupel (qgraup) : Orange")
        print("\nNote: Brightness indicates field magnitude in composite plots.")
        print("=" * 70)
        sys.exit(1)

    run_dir = sys.argv[1]
    # Default: create 'plots' subdirectory inside the run directory
    output_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(run_dir, 'plots')

    if not os.path.isdir(run_dir):
        print(f"Error: {run_dir} is not a valid directory")
        sys.exit(1)

    print(f"Processing run directory: {run_dir}")
    print(f"Output directory: {output_dir}")

    # Create composite plots for each timestep
    plot_all_microphysics(run_dir, output_dir)

    print("\nDone!")
