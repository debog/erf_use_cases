#!/usr/bin/env python3
"""
Script to plot vertical profiles of horizontally averaged microphysics
variables from ERF simulations at each timestep.

Usage: python plot_vertical_profiles.py <run_directory> [output_dir]
    Ex: python plot_vertical_profiles.py .run_sdm_bimodal_amsu.matrix.nproc00004
"""

import yt
import numpy as np
import matplotlib.pyplot as plt
import sys
import os
from glob import glob

# Disable yt info prints
yt.set_log_level("error")

# Microphysics variables to profile
PROFILE_VARS = ['qc', 'qi', 'qrain', 'qsnow', 'qgraup']

# Colors matching the composite plot scheme
COLORS = {
    'qc': '#999999',      # Grey - cloud water
    'qi': '#9933FF',      # Purple - ice
    'qrain': '#4D80FF',   # Blue - rain
    'qsnow': '#FF66CC',   # Pink - snow
    'qgraup': '#FF9900',  # Orange - graupel
}

# Display labels
LABELS = {
    'qc': 'cloud ($q_c$)',
    'qi': 'ice ($q_i$)',
    'qrain': 'rain ($q_{rain}$)',
    'qsnow': 'snow ($q_{snow}$)',
    'qgraup': 'graupel ($q_{graup}$)',
}

# Line widths: thinner for cloud (background), thicker for primary species
LINEWIDTHS = {
    'qc': 1.5,
    'qi': 2.5,
    'qrain': 2.5,
    'qsnow': 2.5,
    'qgraup': 2.5,
}


def format_time(seconds):
    """Format time as seconds or minutes depending on magnitude."""
    if seconds < 120:
        return f'{seconds:.1f} s'
    return f'{seconds / 60:.1f} min'


def plot_vertical_profiles(cg, var_list, time, output_file, domain_extent,
                           xmax=None):
    """
    Plot vertical profiles of horizontally averaged microphysics variables.

    Args:
        cg: yt covering grid object
        var_list: list of variable names to plot
        time: simulation time
        output_file: path to save the plot
        domain_extent: tuple of (x_extent, y_extent, z_extent) in meters
        xmax: fixed upper x-axis limit for consistent scaling across timesteps
    """
    # Get z coordinates (convert from cm to m)
    z = np.array(cg['z'][0, 0, :]) / 1e2  # cm to m

    fig, ax = plt.subplots(figsize=(8, 10))

    for var in var_list:
        # Get 3D field and average over x and y
        field_3d = np.array(cg[('boxlib', var)])  # Shape: (nx, ny, nz)
        profile = np.mean(field_3d, axis=(0, 1))  # Average over x, y -> (nz,)

        # Clean up noise near threshold by setting small values to NaN
        profile = profile.astype(float)
        profile[profile < 1e-7] = np.nan

        # Only plot if there's meaningful data
        if np.any(np.isfinite(profile)):
            ax.plot(profile, z, linewidth=LINEWIDTHS[var], color=COLORS[var],
                    label=LABELS[var])

    ax.set_xscale('log')
    ax.set_xlim(1e-7, xmax)
    ax.set_xlabel('Mixing ratio (kg/kg)', fontsize=14)
    ax.set_ylabel('Z (m)', fontsize=14)
    ax.set_title(f'Vertical profiles at t = {format_time(time)}', fontsize=16)
    ax.legend(fontsize=11, loc='best')
    ax.grid(True, alpha=0.3, which='both')
    ax.set_ylim(z[0], z[-1])

    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close(fig)


def plot_all_profiles(run_dir, output_dir):
    """
    Plot vertical profiles from all timesteps in a run directory.

    Args:
        run_dir: path to the run directory containing plt* subdirectories
        output_dir: directory to save plots (will be created if doesn't exist)
    """
    plotfiles = sorted(glob(os.path.join(run_dir, 'plt*')))

    if not plotfiles:
        print(f"No plotfiles found in {run_dir}")
        return

    print(f"Found {len(plotfiles)} plotfiles")

    os.makedirs(output_dir, exist_ok=True)

    # Get available variables from first plotfile
    print("Loading first plotfile to check available variables...")
    ds = yt.load(plotfiles[0])
    available_vars = [name for (_, name) in ds.field_list]
    domain_extent = tuple(ds.domain_width.to('m').value)

    profile_vars_available = [var for var in PROFILE_VARS if var in available_vars]

    if not profile_vars_available:
        print("Warning: No microphysics variables found in plotfiles")
        print(f"Available variables: {available_vars}")
        return

    print(f"Will plot profiles for: {profile_vars_available}")

    # First pass: find global max across all timesteps for consistent x-axis
    print("Finding global max across all timesteps...")
    global_max = 0
    for pltfile in plotfiles:
        ds = yt.load(pltfile)
        cg = ds.covering_grid(0, ds.domain_left_edge, ds.domain_dimensions,
                             fields=profile_vars_available)
        for var in profile_vars_available:
            field_3d = np.array(cg[('boxlib', var)])
            profile = np.mean(field_3d, axis=(0, 1))
            global_max = max(global_max, np.max(profile))

    # Round up to next power of 10 for a clean axis limit
    xmax = 10 ** np.ceil(np.log10(global_max))
    print(f"Global max mixing ratio: {global_max:.2e}, x-axis limit: {xmax:.0e}")

    # Second pass: generate plots
    for i, pltfile in enumerate(plotfiles):
        print(f"Processing {os.path.basename(pltfile)} ({i+1}/{len(plotfiles)})...")

        ds = yt.load(pltfile)
        time = float(ds.current_time)

        cg = ds.covering_grid(0, ds.domain_left_edge, ds.domain_dimensions,
                             fields=profile_vars_available)

        for var in profile_vars_available:
            cg[('boxlib', var)]

        output_file = os.path.join(output_dir,
                                   f'profiles_{os.path.basename(pltfile)}.png')
        plot_vertical_profiles(cg, profile_vars_available, time,
                              output_file, domain_extent, xmax=xmax)

        print(f"  Saved {output_file}")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("=" * 70)
        print("ERF Vertical Profiles Plotting Script")
        print("=" * 70)
        print("\nUsage: python plot_vertical_profiles.py <run_directory> [output_dir]")
        print("\nArguments:")
        print("  run_directory  : Path to ERF run directory containing plt* subdirectories")
        print("  output_dir     : (Optional) Output directory for plots")
        print("                   Default: <run_directory>/plots")
        print("\nOutput:")
        print("  - profiles_plt*.png : Vertical profiles of horizontally averaged")
        print("                        mixing ratios (qc, qi, qrain, qsnow, qgraup)")
        print("=" * 70)
        sys.exit(1)

    run_dir = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(run_dir, 'plots')

    if not os.path.isdir(run_dir):
        print(f"Error: {run_dir} is not a valid directory")
        sys.exit(1)

    print(f"Processing run directory: {run_dir}")
    print(f"Output directory: {output_dir}")

    plot_all_profiles(run_dir, output_dir)

    print("\nDone!")
