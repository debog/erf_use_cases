#!/usr/bin/env python3
"""
Plot initial sampling data from ERF plt files
Computes and plots number concentration vs radius from particle data
"""

import os
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
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
SIZE_1 = 8
SIZE_2 = 6
FS = 20
FS_TICK = 18
MS_SIZE = 8

def compute_distribution(run_dir):
    """
    Compute particle distribution from plt file

    Parameters:
    -----------
    run_dir : str
        Path to the run directory containing plt00000

    Returns:
    --------
    radius : ndarray
        Bin centers for radius in meters
    n_mult : ndarray
        Number concentration per bin (multiplicity-weighted)
    """
    # Find plt file
    plt_file = os.path.join(run_dir, "plt00000")

    if not os.path.exists(plt_file):
        print(f"Error: Plot file not found: {plt_file}")
        sys.exit(1)

    # Get particle field names
    pcname = "super_droplets_moisture"
    sd_attribs = pltutils.get_particle_field_names(plt_file)

    print(f"Reading particle data from: {plt_file}")
    print(f"Available particle fields: {sd_attribs}")

    # Read particle data
    _, cgp, _ = pltutils.read_plt_particles(plt_file, pcname, sd_attribs)

    # Get multiplicity
    mult = pltutils.get_particle_var_array(cgp, pcname, "particle_multiplicity")

    # Read mass and compute radius
    m_o = pltutils.get_particle_var_array(cgp, pcname, "particle_particle_mass")
    r_o = (m_o / ((4.0/3.0) * np.pi * DENSITY))**(1.0/3.0)

    print(f"Number of super-droplets: {len(r_o)}")
    print(f"Radius range: {r_o.min():.3e} - {r_o.max():.3e} m")
    print(f"Radius range: {r_o.min()*1e6:.3e} - {r_o.max()*1e6:.3e} μm")

    # Create radius bins (from minimum to maximum particle radius)
    r_range = np.geomspace(r_o.min(), r_o.max(), 30)  # meters

    # Initialize binning arrays
    n_mult = np.zeros(len(r_range))

    # Bin particles by radius
    for idx in range(len(r_range)-1):
        I = (r_o >= r_range[idx]) & (r_o < r_range[idx+1])
        n_mult[idx] = np.sum(mult[I])

    # Normalize by bin width in log space
    n_mult = n_mult / np.gradient(np.log(r_range))

    return r_range, n_mult

def plot_distribution(run_dir, output_file=None, case_name=None):
    """
    Plot the initial particle distribution

    Parameters:
    -----------
    run_dir : str
        Path to the run directory containing plt00000
    output_file : str, optional
        Path to save the plot
    case_name : str, optional
        Name of the case for the title
    """
    # Compute distribution
    r_range, n_mult = compute_distribution(run_dir)

    # Create the plot
    _, ax = plt.subplots(figsize=(SIZE_1, SIZE_2))

    # Plot the data (convert radius to μm, concentration to cm^-3)
    radius_um = 1e6 * r_range[:-1]
    n_conc_cm3 = 1e-6 * n_mult[:-1]

    ax.plot(radius_um, n_conc_cm3, '--o',
            linewidth=2, markersize=MS_SIZE, color='blue')

    # Set up axes
    ax.set_xscale('log')
    ax.set_yscale('log')
    ax.set_xlabel(r'Radius ($\mu$m)', fontsize=FS)
    ax.set_ylabel(r'Number concentration ($cm^{-3}$)', fontsize=FS)
    ax.tick_params(labelsize=FS_TICK)
    ax.grid(True, linestyle=':', alpha=0.7)

    # Set axis limits based on data range
    # Filter out non-positive values for log scale
    radius_positive = radius_um[radius_um > 0]
    n_conc_positive = n_conc_cm3[n_conc_cm3 > 0]

    if len(radius_positive) > 0:
        r_min, r_max = radius_positive.min(), radius_positive.max()
        ax.set_xlim([r_min * 0.5, r_max * 2.0])

    if len(n_conc_positive) > 0:
        n_min, n_max = n_conc_positive.min(), n_conc_positive.max()
        ax.set_ylim([n_min * 0.1, n_max * 10.0])

    # Set title
    if case_name:
        ax.set_title(f'Initial Sampling: {case_name}', fontsize=FS)
    else:
        ax.set_title('Initial Particle Distribution', fontsize=FS)

    # Adjust layout
    plt.tight_layout()

    # Save the plot
    if output_file is None:
        output_file = os.path.join(run_dir, "initial_distribution.png")

    print(f"Saving plot to: {output_file}")
    plt.savefig(output_file, dpi=150, bbox_inches='tight')
    plt.close()

    print("Plot created successfully!")

def main():
    parser = argparse.ArgumentParser(
        description='Plot initial sampling data from ERF Super Droplets simulation',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Plot from a specific run directory
  ./plot_initial_sampling.py ../.run_mass_exp_constant_mult_matrix_initial

  # Save to a specific output file
  ./plot_initial_sampling.py ../.run_mass_exp_constant_mult_matrix_initial -o plot.png

  # Specify case name for title
  ./plot_initial_sampling.py ../.run_mass_exp_constant_mult_matrix_initial -c "Matrix Run"
        """
    )

    parser.add_argument('run_dir',
                       help='Path to run directory containing plt00000')
    parser.add_argument('-o', '--output',
                       help='Output file path')
    parser.add_argument('-c', '--case',
                       help='Case name for plot title')

    args = parser.parse_args()

    # Check if run directory exists
    if not os.path.isdir(args.run_dir):
        print(f"Error: Run directory does not exist: {args.run_dir}")
        sys.exit(1)

    # Create the plot
    plot_distribution(args.run_dir, args.output, args.case)

if __name__ == '__main__':
    main()
