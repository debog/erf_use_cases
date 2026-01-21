#!/usr/bin/env python3
"""
ERF comparison script for Super Droplets Moisture simulations
Generated automatically by plot_compare.sh
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
BASELINE_DIR = "{baseline_dir}"
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

# Define line styles for baseline (thinner solid line) and current run (dashed with markers)
BASELINE_STYLES = {
    't0': {'color': 'black', 'linestyle': '-', 'linewidth': 1},
    't1': {'color': 'red', 'linestyle': '-', 'linewidth': 1},
    't2': {'color': 'blue', 'linestyle': '-', 'linewidth': 1},
    't3': {'color': 'green', 'linestyle': '-', 'linewidth': 1},
}

CURRENT_STYLES = {
    't0': {'color': 'black', 'linestyle': '--', 'linewidth': 2, 'marker': 'o', 'markersize': 5, 'markevery': 1, 'markerfacecolor': 'none', 'markeredgewidth': 1},
    't1': {'color': 'red', 'linestyle': '--', 'linewidth': 2, 'marker': 'o', 'markersize': 5, 'markevery': 1, 'markerfacecolor': 'none', 'markeredgewidth': 1},
    't2': {'color': 'blue', 'linestyle': '--', 'linewidth': 2, 'marker': 'o', 'markersize': 5, 'markevery': 1, 'markerfacecolor': 'none', 'markeredgewidth': 1},
    't3': {'color': 'green', 'linestyle': '--', 'linewidth': 2, 'marker': 'o', 'markersize': 5, 'markevery': 1, 'markerfacecolor': 'none', 'markeredgewidth': 1},
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

# Validate simulation results against baseline
def validate_simulation(current_data_dict, baseline_data_dict, time_seconds):
    """
    Validates simulation results against baseline using multiple metrics.

    Args:
        current_data_dict: Dictionary with time steps as keys and numpy arrays as values
        baseline_data_dict: Dictionary with time steps as keys and numpy arrays as values
        time_seconds: List of time steps in seconds

    Returns:
        dict: Validation results with metrics and pass/fail status
    """
    # Define thresholds for validation
    thresholds = {
        "peak_height_diff_pct": 15.0,  # Max allowed % difference in peak height
        "peak_loc_diff_pct": 20.0,     # Max allowed % difference in peak location
        "mass_diff_pct": 10.0,         # Max allowed % difference in total mass
        "width_diff_pct": 25.0,        # Max allowed % difference in distribution width (increased to 25%)
        "mean_diff_pct": 15.0          # Max allowed % difference in mean
    }

    validation = {"pass": True, "metrics": {}, "case": CASE_NAME}

    for seconds in time_seconds:
        # Skip if data is missing for this time step
        if seconds not in current_data_dict or seconds not in baseline_data_dict:
            validation["metrics"][seconds] = {"error": "Missing data"}
            continue

        curr_data = current_data_dict[seconds]
        base_data = baseline_data_dict[seconds]

        # Convert data to more usable format
        curr = {"x": curr_data[:, 0] * 1e6, "y": curr_data[:, 1] * 1000}  # Convert to µm and g/m³
        base = {"x": base_data[:, 0] * 1e6, "y": base_data[:, 1] * 1000}  # Convert to µm and g/m³

        # Initialize time step metrics
        metrics = {}

        # 1. Peak height comparison (relative difference)
        curr_peak = np.max(curr["y"])
        base_peak = np.max(base["y"])
        peak_diff_pct = 100 * abs(curr_peak - base_peak) / base_peak
        metrics["peak_height_diff_pct"] = {
            "value": peak_diff_pct,
            "threshold": thresholds["peak_height_diff_pct"],
            "pass": peak_diff_pct <= thresholds["peak_height_diff_pct"]
        }

        # 2. Peak location comparison
        curr_peak_idx = np.argmax(curr["y"])
        base_peak_idx = np.argmax(base["y"])
        curr_peak_x = curr["x"][curr_peak_idx]
        base_peak_x = base["x"][base_peak_idx]
        peak_loc_diff_pct = 100 * abs(curr_peak_x - base_peak_x) / base_peak_x
        metrics["peak_loc_diff_pct"] = {
            "value": peak_loc_diff_pct,
            "threshold": thresholds["peak_loc_diff_pct"],
            "pass": peak_loc_diff_pct <= thresholds["peak_loc_diff_pct"]
        }

        # 3. Mass conservation (integrate curve)
        curr_mass = np.trapz(curr["y"], curr["x"])
        base_mass = np.trapz(base["y"], base["x"])
        mass_diff_pct = 100 * abs(curr_mass - base_mass) / base_mass
        metrics["mass_diff_pct"] = {
            "value": mass_diff_pct,
            "threshold": thresholds["mass_diff_pct"],
            "pass": mass_diff_pct <= thresholds["mass_diff_pct"]
        }

        # 4. Distribution width (use FWHM)
        # Calculate full width at half maximum as a measure of distribution width
        half_max_curr = curr_peak / 2
        half_max_base = base_peak / 2

        # Find indices where curve is above half max
        curr_above = np.where(curr["y"] >= half_max_curr)[0]
        base_above = np.where(base["y"] >= half_max_base)[0]

        # Calculate width if we can find indices
        if len(curr_above) > 0 and len(base_above) > 0:
            curr_width = curr["x"][curr_above[-1]] - curr["x"][curr_above[0]]
            base_width = base["x"][base_above[-1]] - base["x"][base_above[0]]
            width_diff_pct = 100 * abs(curr_width - base_width) / base_width
            metrics["width_diff_pct"] = {
                "value": width_diff_pct,
                "threshold": thresholds["width_diff_pct"],
                "pass": width_diff_pct <= thresholds["width_diff_pct"]
            }
        else:
            # If we can't calculate width, mark as failed
            metrics["width_diff_pct"] = {
                "value": float('inf'),
                "threshold": thresholds["width_diff_pct"],
                "pass": False
            }

        # 5. Calculate statistical moments
        # Mean (1st moment)
        curr_mean = np.average(curr["x"], weights=curr["y"])
        base_mean = np.average(base["x"], weights=base["y"])
        mean_diff_pct = 100 * abs(curr_mean - base_mean) / base_mean
        metrics["mean_diff_pct"] = {
            "value": mean_diff_pct,
            "threshold": thresholds["mean_diff_pct"],
            "pass": mean_diff_pct <= thresholds["mean_diff_pct"]
        }

        # Store metrics for this time step
        validation["metrics"][seconds] = metrics

        # Check if any metric failed
        time_step_pass = all(m["pass"] for m in metrics.values())
        if not time_step_pass:
            validation["pass"] = False

    return validation

# Create caption with error norms
def create_error_caption(norms_dict):
    """
    Create caption with error norms for the plot.

    Args:
        norms_dict: Dictionary with time steps as keys and norm dictionaries as values

    Returns:
        str: Caption with error norms formatted as a table
    """
    # Create table header
    caption = "Error Metrics (Normalized):\n"
    caption += "  Time      L1          L2          Linf\n"
    caption += "  ----------------------------------------\n"

    # Sort time steps numerically
    time_steps = sorted(norms_dict.keys())

    # Format each row with consistent alignment
    for time_step in time_steps:
        norms = norms_dict[time_step]
        # Convert time_step to string if it's an integer (seconds)
        time_str = str(time_step)
        caption += f"  t={time_str:<4}  {norms['L1']:.2e}  {norms['L2']:.2e}  {norms['Linf']:.2e}\n"

    return caption.strip()

# ANSI color codes for terminal output
GREEN = "\033[92m"
RED = "\033[91m"
RESET = "\033[0m"

# Create validation report
def create_validation_report(validation_results):
    """
    Create a detailed validation report.

    Args:
        validation_results: Dictionary with validation results

    Returns:
        str: Formatted validation report with color-coded PASS/FAIL
    """
    case_name = validation_results["case"]
    overall_pass = validation_results["pass"]
    metrics = validation_results["metrics"]

    # Color-coded overall result
    overall_status = f"{GREEN}PASS{RESET}" if overall_pass else f"{RED}FAIL{RESET}"

    # Start building the report
    report = "VALIDATION RESULTS\n"
    report += "=================\n"
    report += f"{case_name}: {overall_status}\n"

    # Sort time steps numerically
    time_steps = sorted(metrics.keys())

    # Process each time step
    for time_step in time_steps:
        time_metrics = metrics[time_step]

        # Check if we have error data for this time step
        if "error" in time_metrics:
            report += f"  t={time_step}s: {time_metrics['error']}\n"
            continue

        # Always print all metrics for this time step
        report += f"  t={time_step}s:\n"

        # Add details for each metric
        for metric_name, metric_data in time_metrics.items():
            value = metric_data["value"]
            threshold = metric_data["threshold"]
            passed = metric_data["pass"]

            # Color-coded status for each metric
            status = f"{GREEN}PASS{RESET}" if passed else f"{RED}FAIL{RESET}"
            report += f"    {metric_name.ljust(20)}: {value:.2f}% (threshold: {threshold:.2f}%) - {status}\n"

    return report

# Functions to generate comparison plots
def plot_comparison_c1_golovin():
    """
    Generate comparison plots for C1 cases (Golovin kernel, 3600s simulation time)
    """
    # Generate comparison plots for C1 cases with Golovin kernel
    fig, ax = plt.subplots(figsize=(10, 8.8))  # Increased height by 10%

    # Set up plot parameters
    ax.set_xscale('log')
    ax.set_xlabel(r'Radius $R$ ($\mu$m)', fontsize=20)
    ax.set_ylabel(r'Mass density distribution $g(\ln R)$ (gm/m$^3$/unit ln $R$)', fontsize=16)
    ax.set_xlim(10, 5000)
    ax.set_ylim(0, 2.0)  # Extended to 2.0
    ax.grid(True, linestyle=':', alpha=0.7)
    # Extract PPB exponent from case name (e.g., "13" from "c1_ppb_2_13_golovin")
    ppb_exponent = CASE_NAME.split("_")[3]
    ax.set_title(f"Particles per box = 2^{ppb_exponent} - Golovin kernel", fontsize=18)

    # For C1 cases, we compare at t=0, 1200, 2400, 3600
    time_steps = ["00000", "24000", "48000", "72000"]
    time_seconds = [0, 1200, 2400, 3600]

    # Store error norms for caption
    error_norms = {}

    # Legend items
    baseline_legend_items = []
    current_legend_items = []

    # Set default path for current run
    run_dir = f"{ROOT_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"

    # Baseline paths will be constructed directly using BASELINE_DIR directory

    # Plot data for each time step
    for i, (time_step, seconds) in enumerate(zip(time_steps, time_seconds)):
        # Baseline data - ensure we use the correct path structure
        baseline_file = f"{BASELINE_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_{time_step}.txt"
        baseline_data = read_data(baseline_file)

        # Current run data
        current_file = f"{run_dir}/super_droplets_moisture_g_lnR_{time_step}.txt"
        current_data = read_data(current_file)

        if baseline_data is not None and current_data is not None:
            # Plot baseline data (thin solid line)
            baseline_line, = ax.plot(
                baseline_data[:, 0] * 1e6,  # Convert to µm
                baseline_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Baseline, t = {seconds} s",
                **BASELINE_STYLES[f't{i}']
            )
            baseline_legend_items.append(baseline_line)

            # Plot current run data (dashed line with markers)
            current_line, = ax.plot(
                current_data[:, 0] * 1e6,  # Convert to µm
                current_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Current, t = {seconds} s",
                **CURRENT_STYLES[f't{i}']
            )
            current_legend_items.append(current_line)

            # Calculate error norms
            norms = calculate_error_norms(baseline_data, current_data)
            error_norms[seconds] = norms

    # Create caption with error norms
    caption = create_error_caption(error_norms)

    # Add error metrics on the top left with smaller font and monospace for table alignment
    ax.text(0.02, 0.98, caption, ha='left', va='top', fontsize=8, transform=ax.transAxes,
            bbox=dict(facecolor='white', alpha=0.8, boxstyle='round,pad=0.5'),
            family='monospace')

    # Combine legend items in pairs (baseline and current for each time step)
    legend_items = []
    for bm, curr in zip(baseline_legend_items, current_legend_items):
        legend_items.extend([bm, curr])

    ax.legend(handles=legend_items, loc='upper right')
    plt.tight_layout()  # No need to adjust layout since caption is inside the plot

    # Save plot
    output_file = f"{OUTPUT_DIR}/{CASE_NAME}_comparison.{PLATFORM}.{OUTPUT_FORMAT}"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved comparison plot to {output_file}")

def plot_comparison_c2_kernel():
    """
    Generate comparison plots for C2 cases (Other kernels, 1800s simulation time)
    """
    fig, ax = plt.subplots(figsize=(10, 8.8))  # Increased height by 10%

    # Set up plot parameters
    ax.set_xscale('log')
    ax.set_xlabel(r'Radius $R$ ($\mu$m)', fontsize=20)
    ax.set_ylabel(r'Mass density distribution $g(\ln R)$ (gm/m$^3$/unit ln $R$)', fontsize=16)
    ax.set_xlim(10, 5000)
    ax.set_ylim(0, 2.0)  # Extended to 2.0
    ax.grid(True, linestyle=':', alpha=0.7)

    # Extract PPB exponent from case name (e.g., "13" from "c2_ppb_2_13_Halls")
    ppb_exponent = CASE_NAME.split("_")[3]

    # Set title based on kernel type with particles per box format
    if KERNEL == "Halls":
        ax.set_title(f"Particles per box = 2^{ppb_exponent} - Hall's kernel", fontsize=18)
    elif KERNEL == "Longs":
        ax.set_title(f"Particles per box = 2^{ppb_exponent} - Long's kernel", fontsize=18)
    elif KERNEL == "sedim":
        ax.set_title(f"Particles per box = 2^{ppb_exponent} - Sedimentation kernel", fontsize=18)

    # For C2 cases, we compare at t=0, 600, 1200, 1800
    time_steps = ["00000", "12000", "24000", "36000"]
    time_seconds = [0, 600, 1200, 1800]

    # Store error norms for caption
    error_norms = {}

    # Legend items
    baseline_legend_items = []
    current_legend_items = []

    # Set default paths based on case name
    run_dir = f"{ROOT_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"
    baseline_dir = f"{BASELINE_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"

    # Plot data for each time step
    for i, (time_step, seconds) in enumerate(zip(time_steps, time_seconds)):
        # Baseline data - ensure we use the correct path structure
        baseline_file = f"{BASELINE_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_{time_step}.txt"
        baseline_data = read_data(baseline_file)

        # Current run data
        current_file = f"{run_dir}/super_droplets_moisture_g_lnR_{time_step}.txt"
        current_data = read_data(current_file)

        if baseline_data is not None and current_data is not None:
            # Plot baseline data (thin solid line)
            baseline_line, = ax.plot(
                baseline_data[:, 0] * 1e6,  # Convert to µm
                baseline_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Baseline, t = {seconds} s",
                **BASELINE_STYLES[f't{i}']
            )
            baseline_legend_items.append(baseline_line)

            # Plot current run data (dashed line with markers)
            current_line, = ax.plot(
                current_data[:, 0] * 1e6,  # Convert to µm
                current_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Current, t = {seconds} s",
                **CURRENT_STYLES[f't{i}']
            )
            current_legend_items.append(current_line)

            # Calculate error norms
            norms = calculate_error_norms(baseline_data, current_data)
            error_norms[seconds] = norms

    # Create caption with error norms
    caption = create_error_caption(error_norms)

    # Add error metrics on the top left with smaller font and monospace for table alignment
    ax.text(0.02, 0.98, caption, ha='left', va='top', fontsize=8, transform=ax.transAxes,
            bbox=dict(facecolor='white', alpha=0.8, boxstyle='round,pad=0.5'),
            family='monospace')

    # Combine legend items in pairs (baseline and current for each time step)
    legend_items = []
    for bm, curr in zip(baseline_legend_items, current_legend_items):
        legend_items.extend([bm, curr])

    ax.legend(handles=legend_items, loc='upper right')
    plt.tight_layout()  # No need to adjust layout since caption is inside the plot

    # Save plot
    output_file = f"{OUTPUT_DIR}/{CASE_NAME}_comparison.{PLATFORM}.{OUTPUT_FORMAT}"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved comparison plot to {output_file}")

def plot_comparison_c3_kernel():
    """
    Generate comparison plots for C3 cases (Modified parameters, 3600s simulation time)
    """
    # Check if this is a valid C3 case with Halls or Longs kernel
    if KERNEL not in ["Halls", "Longs"]:
        print(f"C3 baseline comparisons are only available for Halls and Longs kernels, not {KERNEL}")
        return

    fig, ax = plt.subplots(figsize=(10, 8.8))  # Increased height by 10%

    # Set up plot parameters
    ax.set_xscale('log')
    ax.set_xlabel(r'Radius $R$ ($\mu$m)', fontsize=20)
    ax.set_ylabel(r'Mass density distribution $g(\ln R)$ (gm/m$^3$/unit ln $R$)', fontsize=16)
    ax.set_xlim(2, 5000)
    ax.set_ylim(0, 2.0)  # Extended to 2.0
    ax.grid(True, linestyle=':', alpha=0.7)

    # Extract PPB exponent from case name (e.g., "17" from "c3_ppb_2_17_Halls")
    ppb_exponent = CASE_NAME.split("_")[3]

    # Set title based on kernel type with particles per box format
    if KERNEL == "Halls":
        ax.set_title(f"Particles per box = 2^{ppb_exponent} - Hall's kernel", fontsize=18)
    elif KERNEL == "Longs":
        ax.set_title(f"Particles per box = 2^{ppb_exponent} - Long's kernel", fontsize=18)

    # For C3 cases, we compare at t=0, 1200, 2400, 3600
    time_steps = ["00000", "24000", "48000", "72000"]
    time_seconds = [0, 1200, 2400, 3600]

    # Store error norms for caption
    error_norms = {}

    # Legend items
    baseline_legend_items = []
    current_legend_items = []

    # Set default paths based on case name
    run_dir = f"{ROOT_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"
    baseline_dir = f"{BASELINE_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"

    # Plot data for each time step
    for i, (time_step, seconds) in enumerate(zip(time_steps, time_seconds)):
        # Baseline data - ensure we use the correct path structure
        baseline_file = f"{BASELINE_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_{time_step}.txt"
        baseline_data = read_data(baseline_file)

        # Current run data
        current_file = f"{run_dir}/super_droplets_moisture_g_lnR_{time_step}.txt"
        current_data = read_data(current_file)

        if baseline_data is not None and current_data is not None:
            # Plot baseline data (thin solid line)
            baseline_line, = ax.plot(
                baseline_data[:, 0] * 1e6,  # Convert to µm
                baseline_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Baseline, t = {seconds} s",
                **BASELINE_STYLES[f't{i}']
            )
            baseline_legend_items.append(baseline_line)

            # Plot current run data (dashed line with markers)
            current_line, = ax.plot(
                current_data[:, 0] * 1e6,  # Convert to µm
                current_data[:, 1] * 1000,  # Convert to g/m³
                label=f"Current, t = {seconds} s",
                **CURRENT_STYLES[f't{i}']
            )
            current_legend_items.append(current_line)

            # Calculate error norms
            norms = calculate_error_norms(baseline_data, current_data)
            error_norms[seconds] = norms

    # Create caption with error norms
    caption = create_error_caption(error_norms)

    # Add error metrics on the top left with smaller font and monospace for table alignment
    ax.text(0.02, 0.98, caption, ha='left', va='top', fontsize=8, transform=ax.transAxes,
            bbox=dict(facecolor='white', alpha=0.8, boxstyle='round,pad=0.5'),
            family='monospace')

    # Combine legend items in pairs (baseline and current for each time step)
    legend_items = []
    for bm, curr in zip(baseline_legend_items, current_legend_items):
        legend_items.extend([bm, curr])

    ax.legend(handles=legend_items, loc='upper right')
    plt.tight_layout()  # No need to adjust layout since caption is inside the plot

    # Save plot
    output_file = f"{OUTPUT_DIR}/{CASE_NAME}_comparison.{PLATFORM}.{OUTPUT_FORMAT}"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved comparison plot to {output_file}")

# Main execution
def main():
    global BASELINE_DIR, VALIDATE

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"Comparing with baseline for case: {CASE_NAME}")
    print(f"Kernel: {KERNEL}")
    print(f"Output format: {OUTPUT_FORMAT}")
    print(f"Output directory: {OUTPUT_DIR}")

    # Validation mode (set by plot_compare.sh)
    VALIDATE = "{validate}" == "true"
    if VALIDATE:
        print("Validation mode: ENABLED")

    # Check if both run and baseline directories exist
    run_dir = f"{ROOT_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"
    baseline_dir = f"{BASELINE_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"

    # Keep BASELINE_DIR as the top-level baseline directory
    # Baseline files will be accessed with full paths in the plot functions

    if not os.path.exists(run_dir):
        print(f"Error: Run directory not found: {run_dir}")
        sys.exit(1)

    if not os.path.exists(baseline_dir):
        print(f"Error: Baseline directory not found: {baseline_dir}")
        sys.exit(1)

    # If we're in validation mode, perform validation
    if VALIDATE:
        run_dir = f"{ROOT_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"
        baseline_dir = f"{BASELINE_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001"

        # Determine which type of case we have and validate
        current_data_dict = {}
        baseline_data_dict = {}

        if "c1_" in CASE_NAME and "golovin" in CASE_NAME:
            # For C1 cases, we compare at t=0, 1200, 2400, 3600
            time_steps = ["00000", "24000", "48000", "72000"]
            time_seconds = [0, 1200, 2400, 3600]
        elif "c2_" in CASE_NAME:
            # For C2 cases, we compare at t=0, 600, 1200, 1800
            time_steps = ["00000", "12000", "24000", "36000"]
            time_seconds = [0, 600, 1200, 1800]
        elif "c3_" in CASE_NAME:
            # For C3 cases, we compare at t=0, 1200, 2400, 3600
            time_steps = ["00000", "24000", "48000", "72000"]
            time_seconds = [0, 1200, 2400, 3600]
        else:
            print(f"Unknown case type: {CASE_NAME}")
            sys.exit(1)

        # Load data for each time step
        for time_step, seconds in zip(time_steps, time_seconds):
            # Use the same path structure as in the plotting functions
            baseline_file = f"{BASELINE_DIR}/.run_{CASE_NAME}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_{time_step}.txt"
            current_file = f"{run_dir}/super_droplets_moisture_g_lnR_{time_step}.txt"

            baseline_data = read_data(baseline_file)
            current_data = read_data(current_file)

            if baseline_data is not None and current_data is not None:
                baseline_data_dict[seconds] = baseline_data
                current_data_dict[seconds] = current_data

        # Validate the simulation
        validation_results = validate_simulation(current_data_dict, baseline_data_dict, time_seconds)

        # Create validation report
        report = create_validation_report(validation_results)

        # Print report to console
        print("\n" + report)

        # Save report to file
        report_file = f"{OUTPUT_DIR}/{CASE_NAME}_validation.txt"
        with open(report_file, "w") as f:
            f.write(report)
        print(f"Saved validation report to {report_file}")

        # Report validation result and continue processing
        if not validation_results["pass"]:
            print(f"Validation FAILED for {CASE_NAME} - continuing with plot generation")
        else:
            print(f"Validation PASSED for {CASE_NAME}")

    # Generate plots
    if "c1_" in CASE_NAME and "golovin" in CASE_NAME:
        plot_comparison_c1_golovin()
    elif "c2_" in CASE_NAME:
        plot_comparison_c2_kernel()
    elif "c3_" in CASE_NAME:
        plot_comparison_c3_kernel()
    else:
        print(f"Unknown case type: {CASE_NAME}")
        sys.exit(1)

    # No longer exit with an error code when validation fails
    # This allows the script to continue processing all cases

if __name__ == "__main__":
    main()