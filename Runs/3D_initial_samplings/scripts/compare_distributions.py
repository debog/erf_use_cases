#!/usr/bin/env python3
"""
Compare particle distributions between baseline and current solutions
Reads baseline from initial_distribution.txt and computes current from plt00000
"""

import os
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import argparse

# Add path to modPltUtils (../../python relative to this script)
script_dir = os.path.dirname(os.path.abspath(__file__))
python_dir = os.path.join(script_dir, '..', '..', 'python')
sys.path.append(python_dir)

try:
    import modPltUtils as pltutils
except ImportError as e:
    print(f"Error: Could not import modPltUtils from {python_dir}")
    print(f"Make sure modPltUtils.py exists in ../../python relative to this script")
    print(f"ImportError: {e}")
    sys.exit(1)

# Physical constants
DENSITY = 2170.0  # kg m^{-3} (NaCl density)

# Figure properties
SIZE_1 = 10
SIZE_2 = 8
FS = 20
FS_TICK = 18
MS_SIZE = 6

def compute_statistics(r_um, n_conc_cm3):
    """Compute statistical properties of the distribution"""
    # Compute statistics (use concentration as weights)
    total_conc = np.sum(n_conc_cm3)

    if total_conc > 0:
        mean_r = np.average(r_um, weights=n_conc_cm3)
        variance = np.average((r_um - mean_r)**2, weights=n_conc_cm3)
        std_r = np.sqrt(variance)
    else:
        mean_r = r_um.mean()
        std_r = 0.0

    stats = {
        'min_radius': r_um.min(),
        'max_radius': r_um.max(),
        'mean_radius': mean_r,
        'std_radius': std_r,
        'median_radius': np.median(r_um),
        'total_concentration': total_conc,
        'num_bins': len(r_um)
    }

    return stats

def read_distribution_from_file(run_dir):
    """
    Read particle distribution from initial_distribution.txt file

    Returns:
    --------
    r_um : ndarray
        Particle radii in micrometers
    n_conc_cm3 : ndarray
        Number concentration in cm^-3
    stats : dict
        Statistical properties
    """
    # Find distribution file
    dist_file = os.path.join(run_dir, "initial_distribution.txt")

    if not os.path.exists(dist_file):
        print(f"Error: Distribution file not found: {dist_file}")
        return None, None, None

    # Read data (skip comment lines starting with #)
    data = np.loadtxt(dist_file)

    if data.ndim == 1:
        # Single data point
        data = data.reshape(1, -1)

    r_um = data[:, 0]  # Radius in μm
    n_conc_cm3 = data[:, 1]  # Number concentration in cm^-3

    # Compute statistics
    stats = compute_statistics(r_um, n_conc_cm3)

    return r_um, n_conc_cm3, stats

def compute_distribution_from_plt(run_dir):
    """
    Compute particle distribution from plt file

    Returns:
    --------
    r_um : ndarray
        Particle radii in micrometers
    n_conc_cm3 : ndarray
        Number concentration in cm^-3
    stats : dict
        Statistical properties
    """
    # Find plt file
    plt_file = os.path.join(run_dir, "plt00000")

    if not os.path.exists(plt_file):
        print(f"Error: Plot file not found: {plt_file}")
        return None, None, None

    # Get particle field names
    pcname = "super_droplets_moisture"
    sd_attribs = pltutils.get_particle_field_names(plt_file)

    # Read particle data
    _, cgp, _ = pltutils.read_plt_particles(plt_file, pcname, sd_attribs)

    # Get multiplicity
    mult = pltutils.get_particle_var_array(cgp, pcname, "particle_multiplicity")

    # Read mass and compute radius
    m_o = pltutils.get_particle_var_array(cgp, pcname, "particle_particle_mass")
    r_o = (m_o / ((4.0/3.0) * np.pi * DENSITY))**(1.0/3.0)

    # Convert to micrometers
    r_um = r_o * 1e6

    # Check for constant radius case
    r_std = np.std(r_um)
    if r_std < 1e-20 or r_um.max() == r_um.min():
        # Single radius
        r_single = r_um.mean()
        n_total = np.sum(mult)
        n_conc_cm3 = np.array([n_total * 1e-6])  # Convert to cm^-3
        r_um_out = np.array([r_single])
    else:
        # Multiple radii - create bins
        r_range = np.geomspace(r_o.min(), r_o.max(), 30)
        n_mult = np.zeros(len(r_range))

        for idx in range(len(r_range)-1):
            I = (r_o >= r_range[idx]) & (r_o < r_range[idx+1])
            n_mult[idx] = np.sum(mult[I])

        # Normalize by bin width in log space
        n_mult = n_mult / np.gradient(np.log(r_range))

        # Convert to output units (μm and cm^-3)
        r_um_out = r_range[:-1] * 1e6
        n_conc_cm3 = n_mult[:-1] * 1e-6

    # Compute statistics
    stats = compute_statistics(r_um_out, n_conc_cm3)

    return r_um_out, n_conc_cm3, stats

def compare_and_plot(baseline_dir, current_dir, output_file, case_name=None):
    """
    Compare baseline and current distributions and create comparison plot
    Reads baseline from initial_distribution.txt and computes current from plt00000

    Returns:
    --------
    comparison : dict
        Dictionary of comparison metrics
    """
    print(f"Reading baseline from: {baseline_dir}/initial_distribution.txt")
    r_um_base, n_conc_base, stats_base = read_distribution_from_file(baseline_dir)

    if r_um_base is None:
        return None

    print(f"Computing current distribution from: {current_dir}/plt00000")
    r_um_curr, n_conc_curr, stats_curr = compute_distribution_from_plt(current_dir)

    if r_um_curr is None:
        return None

    # Compute comparison metrics
    comparison = {
        'baseline_stats': stats_base,
        'current_stats': stats_curr,
        'relative_errors': {}
    }

    for key in ['min_radius', 'max_radius', 'mean_radius', 'std_radius', 'median_radius']:
        baseline_val = stats_base[key]
        current_val = stats_curr[key]
        if baseline_val != 0:
            rel_error = abs(current_val - baseline_val) / abs(baseline_val)
        else:
            rel_error = 0 if current_val == 0 else float('inf')
        comparison['relative_errors'][key] = rel_error

    # Check if comparison passed (mean and std within tolerance)
    MAX_TOLERANCE = 0.02  # 0.02 maximum allowed error
    passed = True
    failed_keys = []

    for key in ['mean_radius', 'std_radius']:
        if comparison['relative_errors'][key] > MAX_TOLERANCE:
            passed = False
            failed_keys.append(key)

    comparison['passed'] = passed
    comparison['failed_keys'] = failed_keys
    comparison['tolerance'] = MAX_TOLERANCE

    # Create comparison plot
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(SIZE_1, SIZE_2),
                                     gridspec_kw={'height_ratios': [3, 1]})

    # Main plot (data already in μm and cm^-3)
    # For constant mass cases (single radius), use the same x-coordinate for both
    if len(r_um_base) == 1 and len(r_um_curr) == 1:
        # Both are single points - use average x-position to plot them together
        r_avg = (r_um_base[0] + r_um_curr[0]) / 2.0
        ax1.scatter([r_avg], n_conc_base,
                   s=100, edgecolors='black', facecolors='none', linewidths=1.5,
                   marker='o', label='Baseline', zorder=5)
        ax1.scatter([r_avg], n_conc_curr,
                   s=100, edgecolors='blue', facecolors='none', linewidths=1.5,
                   marker='s', label='Current', zorder=4)
    else:
        # At least one has multiple points - plot separately
        if len(r_um_base) == 1:
            # Single radius baseline
            ax1.scatter(r_um_base, n_conc_base,
                       s=100, edgecolors='black', facecolors='none', linewidths=1.5,
                       marker='o', label='Baseline', zorder=5)
        else:
            ax1.plot(r_um_base, n_conc_base,
                    'o-', linewidth=1, markersize=MS_SIZE, color='black',
                    markerfacecolor='none', markeredgewidth=1.5,
                    label='Baseline')

        if len(r_um_curr) == 1:
            # Single radius current
            ax1.scatter(r_um_curr, n_conc_curr,
                       s=100, edgecolors='blue', facecolors='none', linewidths=1.5,
                       marker='s', label='Current', zorder=4)
        else:
            ax1.plot(r_um_curr, n_conc_curr,
                    's--', linewidth=1, markersize=MS_SIZE, color='blue',
                    markerfacecolor='none', markeredgewidth=1.5,
                    label='Current')

    ax1.set_xscale('log')
    ax1.set_yscale('log')
    ax1.set_xlabel(r'Radius ($\mu$m)', fontsize=FS)
    ax1.set_ylabel(r'Number concentration ($cm^{-3}$)', fontsize=FS)
    ax1.tick_params(labelsize=FS_TICK)
    ax1.grid(True, linestyle=':', alpha=0.7)
    ax1.legend(fontsize=16, loc='best')

    # Add pass/fail status to title
    status_str = "PASSED" if comparison['passed'] else "FAILED"
    if case_name:
        title = f'Distribution Comparison: {case_name} [{status_str}]'
    else:
        title = f'Distribution Comparison [{status_str}]'

    # Color title based on pass/fail
    title_color = 'green' if comparison['passed'] else 'red'
    ax1.set_title(title, fontsize=FS, color=title_color)

    # Statistics comparison subplot
    ax2.axis('off')
    stats_text = "Statistical Comparison:\n"
    stats_text += f"Mean radius:   {stats_base['mean_radius']:.3e} μm (base) | "
    stats_text += f"{stats_curr['mean_radius']:.3e} μm (curr) | "
    stats_text += f"Error: {comparison['relative_errors']['mean_radius']:.2e}\n"
    stats_text += f"Std radius:    {stats_base['std_radius']:.3e} μm (base) | "
    stats_text += f"{stats_curr['std_radius']:.3e} μm (curr) | "
    stats_text += f"Error: {comparison['relative_errors']['std_radius']:.2e}\n"
    stats_text += f"Min radius:    {stats_base['min_radius']:.3e} μm (base) | "
    stats_text += f"{stats_curr['min_radius']:.3e} μm (curr) | "
    stats_text += f"Error: {comparison['relative_errors']['min_radius']:.2e}\n"
    stats_text += f"Max radius:    {stats_base['max_radius']:.3e} μm (base) | "
    stats_text += f"{stats_curr['max_radius']:.3e} μm (curr) | "
    stats_text += f"Error: {comparison['relative_errors']['max_radius']:.2e}\n"
    stats_text += f"\nTolerance: max error ≤ {comparison['tolerance']:.2e} for mean/std radius"

    ax2.text(0.05, 0.5, stats_text, fontsize=12, family='monospace',
             verticalalignment='center', transform=ax2.transAxes)

    plt.tight_layout()

    # Save plot
    print(f"Saving comparison plot to: {output_file}")
    plt.savefig(output_file, dpi=150, bbox_inches='tight')
    plt.close()

    return comparison

def main():
    parser = argparse.ArgumentParser(
        description='Compare baseline and current particle distributions',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument('baseline_dir',
                       help='Path to baseline run directory')
    parser.add_argument('current_dir',
                       help='Path to current run directory')
    parser.add_argument('-o', '--output',
                       help='Output plot file path',
                       required=True)
    parser.add_argument('-c', '--case',
                       help='Case name for plot title')

    args = parser.parse_args()

    # Check if directories exist
    if not os.path.isdir(args.baseline_dir):
        print(f"Error: Baseline directory does not exist: {args.baseline_dir}")
        sys.exit(1)

    if not os.path.isdir(args.current_dir):
        print(f"Error: Current directory does not exist: {args.current_dir}")
        sys.exit(1)

    # Compare and plot
    comparison = compare_and_plot(args.baseline_dir, args.current_dir,
                                  args.output, args.case)

    if comparison is None:
        print("Error: Comparison failed")
        sys.exit(1)

    print("\nComparison completed!")
    print(f"\nRelative errors:")
    for key in ['mean_radius', 'std_radius']:
        value = comparison['relative_errors'][key]
        print(f"  {key}: {value:.2e}")

    print(f"\nTolerance check (max allowed: {comparison['tolerance']:.2e}):")
    if comparison['passed']:
        print("  PASSED: All critical errors within tolerance")
        sys.exit(0)
    else:
        print("  FAILED: The following errors exceed tolerance:")
        for key in comparison['failed_keys']:
            print(f"    {key}: {comparison['relative_errors'][key]:.2e} > {comparison['tolerance']:.2e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
