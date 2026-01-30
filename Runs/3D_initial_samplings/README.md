# 3D Initial Samplings

This directory contains scripts for running ERF simulations with `max_step = 0` to generate initial sampling data without time evolution.

## Overview

The `run_erf.sh` script creates a complete run directory with:
- Input files merged from base template and override files
- A `max_step = 0` override to stop after initialization
- A run script to execute the simulation

## Prerequisites

Set the `ERF_BUILD` environment variable to your ERF build directory:

```bash
export ERF_BUILD=/path/to/ERF/Build
```

## Quick Start

Run the script - it will automatically create the input files and run the simulation:
```bash
cd scripts
./run_erf.sh
```

This creates a hidden run directory `.run_mass_exp_constant_mult_<platform>_initial/` and executes the simulation.

## Usage Options

```bash
./run_erf.sh [OPTIONS]

Options:
  -c, --case=NAME       Case name (default: mass_exp_constant_mult)
  -p, --platform=NAME   Platform to run on (default: auto-detect from LCHOST)
  -l, --list            List all available cases
  -d, --dry-run         Show what would be created without creating
  -h, --help            Show this help message
```

### Examples

List available case:
```bash
./run_erf.sh --list
```

Dry run to see what would be created (without running):
```bash
./run_erf.sh --dry-run
```

Run with different platform:
```bash
./run_erf.sh --platform=lassen
```

## Case Details

### mass_exp_constant_mult

- **Mass distribution**: Exponential (override to exponential in sampling_matrix.conf)
- **Multiplicity**: Constant
- **Particles per cell**: 2048
- **Run time**: 0s (initialization only, max_step = 0)
- **MPI tasks**: 4 ranks
- **GPU support**: Automatically configured per platform (Matrix/Tuolumne use 4 GPUs with --gpus-per-task=1)
- **Queue**: Runs in debug queue (pdebug) for fast interactive execution

This case generates initial particle distributions with exponential mass distribution and constant multiplicity. The simulation stops immediately after initialization to sample the initial state.

## Re-running a Simulation

To re-run a completed simulation, use the generated `run.sh` script:
```bash
cd .run_mass_exp_constant_mult_<platform>_initial
./run.sh
```

## Plotting Results

After running the simulation, plot the initial mass density distribution:

```bash
# From the scripts directory
cd scripts

# Plot from the latest run directory (auto-detected)
./plot.sh

# Plot from a specific run directory
./plot.sh ../.run_mass_exp_constant_mult_matrix_initial

# Specify case name and output file
./plot.sh -c "Matrix Run" -o my_plot.png ../.run_mass_exp_constant_mult_matrix_initial
```

The plotting script:
- Reads `super_droplets_moisture_g_lnR_00000.txt` from the run directory
- Plots column 1 (radius in μm) vs column 3 (mass density distribution g(ln R))
- Saves to `initial_distribution.png` by default
- Uses log scale for the x-axis (radius)

## Directory Structure

```
3D_initial_samplings/
├── README.md                           # This file
├── scripts/
│   ├── run_erf.sh                     # Setup and run script
│   ├── plot.sh                        # Plotting wrapper script
│   ├── plot_initial_sampling.py       # Python plotting script
│   └── platforms.conf                 # Platform-specific configuration
├── inputs/
│   └── templates/
│       ├── base.inputs                # Complete configuration
│       └── overrides/
│           └── sampling_matrix.conf   # 3 aerosol distribution parameters
└── .run_<case>_<platform>_initial/    # Hidden run directories (created on execution)
    ├── inputs_<case>                  # Generated input file
    ├── run.sh                         # Re-run script
    ├── super_droplets_moisture_g_lnR_00000.txt  # Output data
    ├── initial_distribution.png       # Generated plot
    └── plt*/                          # Output plotfiles
```

## Adding New Sampling Cases

The input file generation is extremely simple:
1. **base.inputs** - Contains ALL settings (max_step=0, stop_time=0.0, particles_per_cell=2048, etc.)
2. **sampling_matrix.conf** - Only the last 3 lines that vary between cases (aerosol distribution parameters)

To add new cases, simply create new override files like `sampling_tuolumne.conf` or `sampling_dane.conf` with different aerosol distribution parameters:

```bash
# Example: Create a new sampling case
cd inputs/templates/overrides
cp sampling_matrix.conf sampling_tuolumne.conf
# Edit the 3 aerosol distribution parameters in sampling_tuolumne.conf
```

## Notes

- The script automatically runs the simulation after creating the input files
- Use `--dry-run` to preview without running
- Each run creates a fresh hidden directory (`.run_...`) to avoid conflicts
- A `run.sh` script is created in the run directory for re-running if needed
- **Runs in debug queue** (pdebug) for interactive execution
- Platform-specific settings (ntasks, GPU support) are read from `scripts/platforms.conf`
  - **Matrix** (GPU): 4 MPI tasks, 4 GPUs total (`srun -G 4`), pdebug queue
  - **Dane** (CPU): 4 MPI tasks, no GPU, pdebug queue
  - **Tuolumne** (GPU): 4 MPI tasks, 1 GPU per task = 4 GPUs total, pdebug queue
  - **Desktop**: 4 MPI tasks
  - Other platforms: see platforms.conf
- The input file is generated by merging just two files:
  1. **base.inputs** - Complete configuration with all settings
  2. **sampling_matrix.conf** - Only 3 aerosol distribution parameters that vary
- Use `./run_erf.sh -l` to see the available case
- Output files are placed in the hidden run directory
