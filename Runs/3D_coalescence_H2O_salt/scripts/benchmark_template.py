#!/usr/bin/env python3
"""
ERF benchmark comparison script for Super Droplets Moisture simulations
Generated automatically by benchmark.sh
"""

import os
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt
from matplotlib.ticker import LogFormatter, ScalarFormatter
import glob
from matplotlib import gridspec
import math

# Enable better math rendering
plt.rcParams.update({
    'text.usetex': False,  # Don't use actual LaTeX (not always available)
    'mathtext.default': 'regular',  # Use regular font for math
    'mathtext.fontset': 'stix'      # Use STIX fonts which have good math support
})

# Configuration
ROOT_DIR = "{root_dir}"
BENCHMARK_DIR = "{benchmark_dir}"
PLATFORM = "{platform}"
OUTPUT_DIR = "{output_dir}"
OUTPUT_FORMAT = "{output_format}"
CASE_NAME = "{case_name}"
KERNEL = "{kernel}"

# Set up plot style and formatting
plt.rcParams.update({
    'font.family': 'serif',
    'font.size': 14,
    'mathtext.fontset': 'stix',
    'axes.grid': True,
    'grid.linestyle': ':',
    'grid.alpha': 0.7
})

# Define line styles for benchmark (solid) and current run (dashed with markers)
BENCHMARK_STYLES = {
    't0': {'color': 'black', 'linestyle': '-', 'linewidth': 2},
    't1': {'color': 'red', 'linestyle': '-', 'linewidth': 2},
    't2': {'color': 'blue', 'linestyle': '-', 'linewidth': 2},
    't3': {'color': 'green', 'linestyle': '-', 'linewidth': 2},
}

CURRENT_STYLES = {
    't0': {'color': 'black', 'linestyle': '--', 'linewidth': 2, 'marker': 'o', 'markersize': 5, 'markevery': 10},
    't1': {'color': 'red', 'linestyle': '--', 'linewidth': 2, 'marker': 's', 'markersize': 5, 'markevery': 10},
    't2': {'color': 'blue', 'linestyle': '--', 'linewidth': 2, 'marker': 'D', 'markersize': 5, 'markevery': 10},
    't3': {'color': 'green', 'linestyle': '--', 'linewidth': 2, 'marker': '^', 'markersize': 5, 'markevery': 10},
}

# Function to read data files
def read_data(filepath):
    try:
        # Check if file exists
        if not os.path.exists(filepath):
            print(f"File does not exist: {filepath}")
            return None

        # Read the data
        data = np.loadtxt(filepath)

        # Check if data is valid
        if data is None or data.size == 0:
            print(f"Empty data in file: {filepath}")
            return None
        return data
    except Exception as e:
        print(f"Error reading file {filepath}: {str(e)}")
        return None

# Calculate error norms between two datasets
def calculate_error_norms(data1, data2):
    """
    Calculate L1, L2, and L-infinity norms between two datasets.

    Args:
        data1: First dataset (n x m)
        data2: Second dataset (n x m)

    Returns:
        dict: Dictionary with L1, L2, and Linf norms
    """
    # Make sure data is aligned (same x values)
    if data1.shape[0] != data2.shape[0]:
        # Find common x-axis points by interpolating
        # This is a simplified approach that assumes data is sorted by x
        x1 = data1[:, 0]
        y1 = data1[:, 1]
        x2 = data2[:, 0]
        y2 = data2[:, 1]

        # Find common range
        x_min = max(x1.min(), x2.min())
        x_max = min(x1.max(), x2.max())

        # Create common x-axis
        common_x = np.linspace(x_min, x_max, 1000)

        # Interpolate both datasets to common x-axis
        interp_y1 = np.interp(common_x, x1, y1)
        interp_y2 = np.interp(common_x, x2, y2)

        # Use interpolated values for error calculation
        diff = interp_y1 - interp_y2
        sum_abs = np.sum(np.abs(interp_y1))  # Normalization factor
    else:
        # Datasets already aligned
        diff = data1[:, 1] - data2[:, 1]
        sum_abs = np.sum(np.abs(data1[:, 1]))  # Normalization factor

    # Avoid division by zero
    if sum_abs == 0:
        sum_abs = 1.0

    # Calculate norms
    l1_norm = np.sum(np.abs(diff)) / sum_abs
    l2_norm = np.sqrt(np.sum(diff**2)) / np.sqrt(np.sum(data1[:, 1]**2) if np.sum(data1[:, 1]**2) > 0 else 1.0)
    linf_norm = np.max(np.abs(diff)) / np.max(np.abs(data1[:, 1])) if np.max(np.abs(data1[:, 1])) > 0 else np.max(np.abs(diff))

    return {
        "L1": l1_norm,
        "L2": l2_norm,
        "Linf": linf_norm
    }

# Create caption with error norms
def create_error_caption(norms_dict):
    """
    Create caption with error norms for the plot.

    Args:
        norms_dict: Dictionary with time steps as keys and norm dictionaries as values

    Returns:
        str: Caption with error norms
    """
    caption = "Error Metrics (Normalized):\n"

    for time_step, norms in norms_dict.items():
        caption += f"t={time_step}s: L1={norms['L1']:.5f}, L2={norms['L2']:.5f}, Linf={norms['Linf']:.5f}\n"

    return caption.strip()

# Functions to generate comparison plots
def plot_comparison_c1_golovin():
    """
    Generate comparison plots for C1 cases (Golovin kernel, 3600s simulation time)
    """
    fig, ax = plt.subplots(figsize=(10, 8))

    # Set up plot parameters
    ax.set_xscale('log')
    ax.set_xlabel(r'Radius $R$ ($\mu$m)', fontsize=20)
    ax.set_ylabel(r'Mass density distribution $g(\ln R)$ (gm/m$^3$/unit ln $R$)', fontsize=16)
    ax.set_xlim(10, 5000)
    ax.set_ylim(0, 1.8)
    ax.grid(True, linestyle=':', alpha=0.7)
    ax.set_title(f"Comparison with Benchmark: {CASE_NAME} - Golovin kernel", fontsize=18)

    # For C1 cases, we compare at t=0, 1200, 2400, 3600
    time_steps = ["00000", "24000", "48000", "72000"]
    time_seconds = [0, 1200, 2400, 3600]

    # Store error norms for caption
    error_norms = {}

    # Legend items
    benchmark_legend_items = []
    current_legend_items = []

    # Set default paths based on case name
    run_dir = f"{ROOT_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"
    benchmark_dir = f"{BENCHMARK_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"

    # Plot data for each time step
    for i, (time_step, seconds) in enumerate(zip(time_steps, time_seconds)):
        # Benchmark data
        benchmark_file = f"{benchmark_dir}/super_droplets_moisture_g_lnR_{time_step}.txt"
        benchmark_data = read_data(benchmark_file)

        # Current run data
        current_file = f"{run_dir}/super_droplets_moisture_g_lnR_{time_step}.txt"
        current_data = read_data(current_file)

        if benchmark_data is not None and current_data is not None:
            # Plot benchmark data (solid line)
            benchmark_line, = ax.plot(
                benchmark_data[:, 0] * 1e6,  # Convert to µm
                benchmark_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Benchmark, t = {seconds} s",
                **BENCHMARK_STYLES[f't{i}']
            )
            benchmark_legend_items.append(benchmark_line)

            # Plot current run data (dashed line with markers)
            current_line, = ax.plot(
                current_data[:, 0] * 1e6,  # Convert to µm
                current_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Current, t = {seconds} s",
                **CURRENT_STYLES[f't{i}']
            )
            current_legend_items.append(current_line)

            # Calculate error norms
            norms = calculate_error_norms(benchmark_data, current_data)
            error_norms[seconds] = norms

    # Create caption with error norms
    caption = create_error_caption(error_norms)

    # Add caption at the bottom
    fig.text(0.5, 0.01, caption, ha='center', va='bottom', fontsize=10,
             bbox=dict(facecolor='white', alpha=0.8, boxstyle='round,pad=0.5'))

    # Combine legend items in pairs (benchmark and current for each time step)
    legend_items = []
    for bm, curr in zip(benchmark_legend_items, current_legend_items):
        legend_items.extend([bm, curr])

    ax.legend(handles=legend_items, loc='upper right')
    plt.tight_layout(rect=[0, 0.05, 1, 1])  # Adjust layout to make room for caption

    # Save plot
    output_file = f"{OUTPUT_DIR}/{CASE_NAME}_benchmark_comparison.{PLATFORM}.{OUTPUT_FORMAT}"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved comparison plot to {output_file}")

def plot_comparison_c2_kernel():
    """
    Generate comparison plots for C2 cases (Other kernels, 1800s simulation time)
    """
    fig, ax = plt.subplots(figsize=(10, 8))

    # Set up plot parameters
    ax.set_xscale('log')
    ax.set_xlabel(r'Radius $R$ ($\mu$m)', fontsize=20)
    ax.set_ylabel(r'Mass density distribution $g(\ln R)$ (gm/m$^3$/unit ln $R$)', fontsize=16)
    ax.set_xlim(10, 5000)
    ax.set_ylim(0, 1.8)
    ax.grid(True, linestyle=':', alpha=0.7)

    # Set title based on kernel type
    if KERNEL == "Halls":
        ax.set_title(f"Comparison with Benchmark: {CASE_NAME} - Hall's kernel", fontsize=18)
    elif KERNEL == "Longs":
        ax.set_title(f"Comparison with Benchmark: {CASE_NAME} - Long's kernel", fontsize=18)
    elif KERNEL == "sedim":
        ax.set_title(f"Comparison with Benchmark: {CASE_NAME} - Sedimentation kernel", fontsize=18)

    # For C2 cases, we compare at t=0, 600, 1200, 1800
    time_steps = ["00000", "12000", "24000", "36000"]
    time_seconds = [0, 600, 1200, 1800]

    # Store error norms for caption
    error_norms = {}

    # Legend items
    benchmark_legend_items = []
    current_legend_items = []

    # Set default paths based on case name
    run_dir = f"{ROOT_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"
    benchmark_dir = f"{BENCHMARK_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"

    # Plot data for each time step
    for i, (time_step, seconds) in enumerate(zip(time_steps, time_seconds)):
        # Benchmark data
        benchmark_file = f"{benchmark_dir}/super_droplets_moisture_g_lnR_{time_step}.txt"
        benchmark_data = read_data(benchmark_file)

        # Current run data
        current_file = f"{run_dir}/super_droplets_moisture_g_lnR_{time_step}.txt"
        current_data = read_data(current_file)

        if benchmark_data is not None and current_data is not None:
            # Plot benchmark data (solid line)
            benchmark_line, = ax.plot(
                benchmark_data[:, 0] * 1e6,  # Convert to µm
                benchmark_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Benchmark, t = {seconds} s",
                **BENCHMARK_STYLES[f't{i}']
            )
            benchmark_legend_items.append(benchmark_line)

            # Plot current run data (dashed line with markers)
            current_line, = ax.plot(
                current_data[:, 0] * 1e6,  # Convert to µm
                current_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Current, t = {seconds} s",
                **CURRENT_STYLES[f't{i}']
            )
            current_legend_items.append(current_line)

            # Calculate error norms
            norms = calculate_error_norms(benchmark_data, current_data)
            error_norms[seconds] = norms

    # Create caption with error norms
    caption = create_error_caption(error_norms)

    # Add caption at the bottom
    fig.text(0.5, 0.01, caption, ha='center', va='bottom', fontsize=10,
             bbox=dict(facecolor='white', alpha=0.8, boxstyle='round,pad=0.5'))

    # Combine legend items in pairs (benchmark and current for each time step)
    legend_items = []
    for bm, curr in zip(benchmark_legend_items, current_legend_items):
        legend_items.extend([bm, curr])

    ax.legend(handles=legend_items, loc='upper right')
    plt.tight_layout(rect=[0, 0.05, 1, 1])  # Adjust layout to make room for caption

    # Save plot
    output_file = f"{OUTPUT_DIR}/{CASE_NAME}_benchmark_comparison.{PLATFORM}.{OUTPUT_FORMAT}"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved comparison plot to {output_file}")

def plot_comparison_c3_kernel():
    """
    Generate comparison plots for C3 cases (Modified parameters, 3600s simulation time)
    """
    # Check if this is a valid C3 case with Halls or Longs kernel
    if KERNEL not in ["Halls", "Longs"]:
        print(f"C3 benchmark comparisons are only available for Halls and Longs kernels, not {KERNEL}")
        return

    fig, ax = plt.subplots(figsize=(10, 8))

    # Set up plot parameters
    ax.set_xscale('log')
    ax.set_xlabel(r'Radius $R$ ($\mu$m)', fontsize=20)
    ax.set_ylabel(r'Mass density distribution $g(\ln R)$ (gm/m$^3$/unit ln $R$)', fontsize=16)
    ax.set_xlim(2, 5000)
    ax.set_ylim(0, 1.8)
    ax.grid(True, linestyle=':', alpha=0.7)

    # Set title based on kernel type
    if KERNEL == "Halls":
        ax.set_title(f"Comparison with Benchmark: {CASE_NAME} - Hall's kernel", fontsize=18)
    elif KERNEL == "Longs":
        ax.set_title(f"Comparison with Benchmark: {CASE_NAME} - Long's kernel", fontsize=18)

    # For C3 cases, we compare at t=0, 1200, 2400, 3600
    time_steps = ["00000", "24000", "48000", "72000"]
    time_seconds = [0, 1200, 2400, 3600]

    # Store error norms for caption
    error_norms = {}

    # Legend items
    benchmark_legend_items = []
    current_legend_items = []

    # Set default paths based on case name
    run_dir = f"{ROOT_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"
    benchmark_dir = f"{BENCHMARK_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"

    # Plot data for each time step
    for i, (time_step, seconds) in enumerate(zip(time_steps, time_seconds)):
        # Benchmark data
        benchmark_file = f"{benchmark_dir}/super_droplets_moisture_g_lnR_{time_step}.txt"
        benchmark_data = read_data(benchmark_file)

        # Current run data
        current_file = f"{run_dir}/super_droplets_moisture_g_lnR_{time_step}.txt"
        current_data = read_data(current_file)

        if benchmark_data is not None and current_data is not None:
            # Plot benchmark data (solid line)
            benchmark_line, = ax.plot(
                benchmark_data[:, 0] * 1e6,  # Convert to µm
                benchmark_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Benchmark, t = {seconds} s",
                **BENCHMARK_STYLES[f't{i}']
            )
            benchmark_legend_items.append(benchmark_line)

            # Plot current run data (dashed line with markers)
            current_line, = ax.plot(
                current_data[:, 0] * 1e6,  # Convert to µm
                current_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Current, t = {seconds} s",
                **CURRENT_STYLES[f't{i}']
            )
            current_legend_items.append(current_line)

            # Calculate error norms
            norms = calculate_error_norms(benchmark_data, current_data)
            error_norms[seconds] = norms

    # Create caption with error norms
    caption = create_error_caption(error_norms)

    # Add caption at the bottom
    fig.text(0.5, 0.01, caption, ha='center', va='bottom', fontsize=10,
             bbox=dict(facecolor='white', alpha=0.8, boxstyle='round,pad=0.5'))

    # Combine legend items in pairs (benchmark and current for each time step)
    legend_items = []
    for bm, curr in zip(benchmark_legend_items, current_legend_items):
        legend_items.extend([bm, curr])

    ax.legend(handles=legend_items, loc='upper right')
    plt.tight_layout(rect=[0, 0.05, 1, 1])  # Adjust layout to make room for caption

    # Save plot
    output_file = f"{OUTPUT_DIR}/{CASE_NAME}_benchmark_comparison.{PLATFORM}.{OUTPUT_FORMAT}"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved comparison plot to {output_file}")

# Main execution
def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"Benchmark comparison for case: {CASE_NAME}")
    print(f"Kernel: {KERNEL}")
    print(f"Output format: {OUTPUT_FORMAT}")
    print(f"Output directory: {OUTPUT_DIR}")

    # Check if both run and benchmark directories exist
    run_dir = f"{ROOT_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"
    benchmark_dir = f"{BENCHMARK_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"

    if not os.path.exists(run_dir):
        print(f"Error: Run directory not found: {run_dir}")
        sys.exit(1)

    if not os.path.exists(benchmark_dir):
        print(f"Error: Benchmark directory not found: {benchmark_dir}")
        sys.exit(1)

    # Determine which type of case we have and call the appropriate function
    if "c1_" in CASE_NAME and "golovin" in CASE_NAME:
        plot_comparison_c1_golovin()
    elif "c2_" in CASE_NAME:
        plot_comparison_c2_kernel()
    elif "c3_" in CASE_NAME:
        plot_comparison_c3_kernel()
    else:
        print(f"Unknown case type: {CASE_NAME}")
        sys.exit(1)

if __name__ == "__main__":
    main()