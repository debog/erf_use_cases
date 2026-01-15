#!/usr/bin/env python3
"""
ERF plotting script for Super Droplets Moisture simulations
Generated automatically by plot.sh
"""

import os
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt
from matplotlib.ticker import LogFormatter
import glob

# Enable better math rendering
plt.rcParams.update({
    'text.usetex': False,  # Don't use actual LaTeX (not always available)
    'mathtext.default': 'regular',  # Use regular font for math
    'mathtext.fontset': 'stix'      # Use STIX fonts which have good math support
})

# Configuration
ROOT_DIR = "{root_dir}"
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

# Define line styles and colors for different cases
STYLES = {
    'ppb_2_13': {
        't0': {'color': 'black', 'linestyle': '--', 'linewidth': 2, 'marker': 's', 'markersize': 5},
        't1': {'color': 'red', 'linestyle': '--', 'linewidth': 2, 'marker': 'o', 'markersize': 5},
        't2': {'color': 'blue', 'linestyle': '--', 'linewidth': 2, 'marker': 'd', 'markersize': 5},
        't3': {'color': 'green', 'linestyle': '--', 'linewidth': 2, 'marker': 's', 'markersize': 5},
    },
    'ppb_2_17': {
        't0': {'color': 'black', 'linestyle': ':', 'linewidth': 1, 'marker': 'o', 'markersize': 3},
        't1': {'color': 'red', 'linestyle': ':', 'linewidth': 1, 'marker': 'o', 'markersize': 3},
        't2': {'color': 'blue', 'linestyle': ':', 'linewidth': 1, 'marker': 'o', 'markersize': 3},
        't3': {'color': 'green', 'linestyle': ':', 'linewidth': 1, 'marker': 'o', 'markersize': 3},
    },
    'ppb_2_21': {
        't0': {'color': 'black', 'linestyle': ':', 'linewidth': 1, 'marker': 'o', 'markersize': 3},
        't1': {'color': 'red', 'linestyle': ':', 'linewidth': 1, 'marker': 'o', 'markersize': 3},
        't2': {'color': 'blue', 'linestyle': ':', 'linewidth': 1, 'marker': 'o', 'markersize': 3},
        't3': {'color': 'green', 'linestyle': ':', 'linewidth': 1, 'marker': 'o', 'markersize': 3},
    }
}

# Function to read data files
def read_data(filepath):
    try:
        data = np.loadtxt(filepath)
        return data
    except:
        print(f"Error reading file: {filepath}")
        return None

# Functions to generate plots
def plot_c1_golovin():
    # C1 cases (Golovin kernel, 3600s simulation time)
    fig, ax = plt.subplots(figsize=(10, 8))

    # Set up plot parameters
    ax.set_xscale('log')
    ax.set_xlabel(r'Radius $R$ ($\mu$m)', fontsize=20)
    ax.set_ylabel(r'Mass density distribution $g(\ln R)$ (gm/m$^3$/unit ln $R$)', fontsize=16)
    ax.set_xlim(10, 5000)
    ax.set_ylim(0, 1.8)
    ax.grid(True, linestyle=':', alpha=0.7)
    ax.set_title(r'Golovin kernel', fontsize=18)

    # Plot data
    data_files = []
    legend_labels = []

    # Filter based on case name if provided
    if CASE_NAME == "c1_ppb_2_13_golovin":
        # Only plot 2^13 case
        data_files.extend([
            f"{ROOT_DIR}/.run_c1_ppb_2_13_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_13_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_13_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_48000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_13_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_72000.txt",
        ])
        legend_labels.extend([
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 2400 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 3600 \, \mathrm{s}$, $N_s = 2^{13}$",
        ])
        styles = [
            STYLES['ppb_2_13']['t0'],
            STYLES['ppb_2_13']['t1'],
            STYLES['ppb_2_13']['t2'],
            STYLES['ppb_2_13']['t3']
        ]
    elif CASE_NAME == "c1_ppb_2_17_golovin":
        # Only plot 2^17 case
        data_files.extend([
            f"{ROOT_DIR}/.run_c1_ppb_2_17_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_17_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_17_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_48000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_17_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_72000.txt",
        ])
        legend_labels.extend([
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 2400 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 3600 \, \mathrm{s}$, $N_s = 2^{17}$",
        ])
        styles = [
            STYLES['ppb_2_17']['t0'],
            STYLES['ppb_2_17']['t1'],
            STYLES['ppb_2_17']['t2'],
            STYLES['ppb_2_17']['t3']
        ]
    else:
        # Plot both 2^13 and 2^17 cases
        data_files.extend([
            f"{ROOT_DIR}/.run_c1_ppb_2_13_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_13_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_13_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_48000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_13_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_72000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_17_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_17_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_17_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_48000.txt",
            f"{ROOT_DIR}/.run_c1_ppb_2_17_golovin.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_72000.txt",
        ])
        legend_labels.extend([
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 2400 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 3600 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 2400 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 3600 \, \mathrm{s}$, $N_s = 2^{17}$",
        ])
        styles = [
            STYLES['ppb_2_13']['t0'],
            STYLES['ppb_2_13']['t1'],
            STYLES['ppb_2_13']['t2'],
            STYLES['ppb_2_13']['t3'],
            STYLES['ppb_2_17']['t0'],
            STYLES['ppb_2_17']['t1'],
            STYLES['ppb_2_17']['t2'],
            STYLES['ppb_2_17']['t3']
        ]

    # Plot each data file
    for i, file_path in enumerate(data_files):
        data = read_data(file_path)
        if data is not None:
            ax.plot(data[:,0] * 1e6, data[:,1] * 1000, label=legend_labels[i], **styles[i])

    ax.legend(loc='upper right')
    plt.tight_layout()

    # Save plot
    output_file = f"{OUTPUT_DIR}/Golovin.{PLATFORM}.{OUTPUT_FORMAT}"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved plot to {output_file}")

def plot_c2_kernel(kernel_name):
    # C2 cases (Other kernels, 1800s simulation time)
    fig, ax = plt.subplots(figsize=(10, 8))

    # Set up plot parameters
    ax.set_xscale('log')
    ax.set_xlabel(r'Radius $R$ ($\mu$m)', fontsize=20)
    ax.set_ylabel(r'Mass density distribution $g(\ln R)$ (gm/m$^3$/unit ln $R$)', fontsize=16)
    ax.set_xlim(10, 5000)
    ax.set_ylim(0, 1.8)
    ax.grid(True, linestyle=':', alpha=0.7)

    # Set title based on kernel type
    if kernel_name == "Halls":
        ax.set_title(r"Hall's kernel", fontsize=18)
    elif kernel_name == "Longs":
        ax.set_title(r"Long's kernel", fontsize=18)
    elif kernel_name == "sedim":
        ax.set_title(r"Sedimentation kernel", fontsize=18)

    # Plot data
    data_files = []
    legend_labels = []

    # Filter based on case name if provided
    if CASE_NAME == f"c2_ppb_2_13_{kernel_name}":
        # Only plot 2^13 case
        data_files.extend([
            f"{ROOT_DIR}/.run_c2_ppb_2_13_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_13_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_12000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_13_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_13_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_36000.txt",
        ])
        legend_labels.extend([
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 600 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 1800 \, \mathrm{s}$, $N_s = 2^{13}$",
        ])
        styles = [
            STYLES['ppb_2_13']['t0'],
            STYLES['ppb_2_13']['t1'],
            STYLES['ppb_2_13']['t2'],
            STYLES['ppb_2_13']['t3']
        ]
    elif CASE_NAME == f"c2_ppb_2_17_{kernel_name}":
        # Only plot 2^17 case
        data_files.extend([
            f"{ROOT_DIR}/.run_c2_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_12000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_36000.txt",
        ])
        legend_labels.extend([
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 600 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 1800 \, \mathrm{s}$, $N_s = 2^{17}$",
        ])
        styles = [
            STYLES['ppb_2_17']['t0'],
            STYLES['ppb_2_17']['t1'],
            STYLES['ppb_2_17']['t2'],
            STYLES['ppb_2_17']['t3']
        ]
    else:
        # Plot both 2^13 and 2^17 cases
        data_files.extend([
            f"{ROOT_DIR}/.run_c2_ppb_2_13_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_13_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_12000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_13_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_13_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_36000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_12000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c2_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_36000.txt",
        ])
        legend_labels.extend([
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 600 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 1800 \, \mathrm{s}$, $N_s = 2^{13}$",
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 600 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 1800 \, \mathrm{s}$, $N_s = 2^{17}$",
        ])
        styles = [
            STYLES['ppb_2_13']['t0'],
            STYLES['ppb_2_13']['t1'],
            STYLES['ppb_2_13']['t2'],
            STYLES['ppb_2_13']['t3'],
            STYLES['ppb_2_17']['t0'],
            STYLES['ppb_2_17']['t1'],
            STYLES['ppb_2_17']['t2'],
            STYLES['ppb_2_17']['t3']
        ]

    # Plot each data file
    for i, file_path in enumerate(data_files):
        data = read_data(file_path)
        if data is not None:
            ax.plot(data[:,0] * 1e6, data[:,1] * 1000, label=legend_labels[i], **styles[i])

    ax.legend(loc='upper right')
    plt.tight_layout()

    # Save plot
    output_file = f"{OUTPUT_DIR}/{kernel_name}.{PLATFORM}.{OUTPUT_FORMAT}"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved plot to {output_file}")

def plot_c3_kernel(kernel_name):
    # C3 cases (Modified parameters, 3600s simulation time)
    if kernel_name not in ["Halls", "Longs"]:
        print(f"C3 plots are only available for Halls and Longs kernels, not {kernel_name}")
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
    if kernel_name == "Halls":
        ax.set_title("Hall's kernel", fontsize=18)
    elif kernel_name == "Longs":
        ax.set_title("Long's kernel", fontsize=18)

    # Plot data
    data_files = []
    legend_labels = []

    # Filter based on case name if provided
    if CASE_NAME == f"c3_ppb_2_17_{kernel_name}":
        # Only plot 2^17 case
        data_files.extend([
            f"{ROOT_DIR}/.run_c3_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_48000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_72000.txt",
        ])
        legend_labels.extend([
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 2400 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 3600 \, \mathrm{s}$, $N_s = 2^{17}$",
        ])
        styles = [
            STYLES['ppb_2_17']['t0'],
            STYLES['ppb_2_17']['t1'],
            STYLES['ppb_2_17']['t2'],
            STYLES['ppb_2_17']['t3']
        ]
    elif CASE_NAME == f"c3_ppb_2_21_{kernel_name}":
        # Only plot 2^21 case
        data_files.extend([
            f"{ROOT_DIR}/.run_c3_ppb_2_21_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_21_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_21_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_48000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_21_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_72000.txt",
        ])
        legend_labels.extend([
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{21}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{21}$",
            r"$t = 2400 \, \mathrm{s}$, $N_s = 2^{21}$",
            r"$t = 3600 \, \mathrm{s}$, $N_s = 2^{21}$",
        ])
        styles = [
            STYLES['ppb_2_21']['t0'],
            STYLES['ppb_2_21']['t1'],
            STYLES['ppb_2_21']['t2'],
            STYLES['ppb_2_21']['t3']
        ]
    else:
        # Plot both 2^17 and 2^21 cases
        data_files.extend([
            f"{ROOT_DIR}/.run_c3_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_48000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_17_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_72000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_21_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_00000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_21_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_24000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_21_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_48000.txt",
            f"{ROOT_DIR}/.run_c3_ppb_2_21_{kernel_name}.{PLATFORM}.nproc00001/super_droplets_moisture_g_lnR_72000.txt",
        ])
        legend_labels.extend([
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 2400 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 3600 \, \mathrm{s}$, $N_s = 2^{17}$",
            r"$t = 0 \, \mathrm{s}$, $N_s = 2^{21}$",
            r"$t = 1200 \, \mathrm{s}$, $N_s = 2^{21}$",
            r"$t = 2400 \, \mathrm{s}$, $N_s = 2^{21}$",
            r"$t = 3600 \, \mathrm{s}$, $N_s = 2^{21}$",
        ])
        styles = [
            STYLES['ppb_2_17']['t0'],
            STYLES['ppb_2_17']['t1'],
            STYLES['ppb_2_17']['t2'],
            STYLES['ppb_2_17']['t3'],
            STYLES['ppb_2_21']['t0'],
            STYLES['ppb_2_21']['t1'],
            STYLES['ppb_2_21']['t2'],
            STYLES['ppb_2_21']['t3']
        ]

    # Plot each data file
    for i, file_path in enumerate(data_files):
        data = read_data(file_path)
        if data is not None:
            ax.plot(data[:,0] * 1e6, data[:,1] * 1000, label=legend_labels[i], **styles[i])

    ax.legend(loc='upper right')
    plt.tight_layout()

    # Save plot
    output_file = f"{OUTPUT_DIR}/{kernel_name}.c3.{PLATFORM}.{OUTPUT_FORMAT}"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved plot to {output_file}")

# Main execution
def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"Plotting for kernel: {KERNEL}")
    print(f"Case name: {CASE_NAME}")
    print(f"Output format: {OUTPUT_FORMAT}")
    print(f"Output directory: {OUTPUT_DIR}")

    if KERNEL == "golovin":
        plot_c1_golovin()
    elif KERNEL in ["Halls", "Longs", "sedim"]:
        plot_c2_kernel(KERNEL)

        # Only plot C3 cases for Halls and Longs kernels
        if KERNEL in ["Halls", "Longs"]:
            plot_c3_kernel(KERNEL)
    else:
        print(f"Unknown kernel type: {KERNEL}")
        sys.exit(1)

if __name__ == "__main__":
    main()