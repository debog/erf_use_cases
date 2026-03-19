# 3D Coalescence H2O with Salt Test Case

ERF simulation of 3D cloud droplet coalescence with water and salt.

## Quick Start

```bash
# Run a case
./scripts/run_erf.sh -c c1_ppb_2_13_golovin

# Profile a case (10 timesteps by default)
./scripts/profile_erf.sh -c c1_ppb_2_13_golovin
```

## Requirements

Set `ERF_BUILD` to your ERF build directory:
```bash
export ERF_BUILD=/path/to/ERF/Build
```

## Usage

```bash
./scripts/run_erf.sh [OPTIONS]
```

| Short | Long               | Description                                       |
|-------|--------------------|---------------------------------------------------|
| `-c`  | `--case=NAME`      | Input case name (default: `c1_ppb_2_13_golovin`)  |
| `-m`  | `--mode=MODE`      | `interactive` (default) or `batch`                |
| `-n`  | `--ntasks=N`       | Override MPI task count                           |
| `-N`  | `--nnodes=N`       | Override node count                               |
| `-q`  | `--queue=NAME`     | Override queue/partition                          |
| `-t`  | `--walltime=TIME`  | Override walltime                                 |
| `-s`  | `--max-steps=N`    | Override number of timesteps                      |
| `-a`  | `--all`            | Run all cases sequentially                        |
| `-d`  | `--dry-run`        | Preview without executing                         |
| `-l`  | `--list-cases`     | Show available cases                              |
| `-p`  | `--list-platforms` | Show supported platforms                          |
| `-v`  | `--verbose`        | Enable verbose output                             |
| `-h`  | `--help`           | Show help message                                 |

## Platform Detection

The script auto-detects the platform from `$LCHOST`:

| LCHOST    | Platform             | Scheduler |
|-----------|----------------------|-----------|
| (unset)   | Desktop/workstation  | mpirun    |
| `dane`    | DANE CPU cluster     | SLURM     |
| `matrix`  | MATRIX GPU cluster   | SLURM     |

## Examples

```bash
# Interactive run on desktop
./scripts/run_erf.sh -c c1_ppb_2_13_golovin

# Batch submission on HPC
./scripts/run_erf.sh -c c1_ppb_2_13_golovin -m batch

# Custom resources
./scripts/run_erf.sh -n 1 -N 1 -q pbatch -m batch

# Run all cases sequentially
./scripts/run_erf.sh -a

# Preview commands without running
./scripts/run_erf.sh -d
```

## Available Cases

The following cases are available for simulation:

### Standard Parameter Cases (C1)
These use 128 particles per cell and have a simulation time of 3600s:

- `c1_ppb_2_13_golovin` - Golovin coalescence kernel
- `c1_ppb_2_13_Halls` - Hall's coalescence kernel
- `c1_ppb_2_13_Longs` - Long's coalescence kernel
- `c1_ppb_2_13_sedim` - Sedimentation coalescence kernel

### High Resolution Parameter Cases (C1)
These use 2048 particles per cell and have a simulation time of 1800s:

- `c1_ppb_2_17_golovin` - Golovin coalescence kernel
- `c1_ppb_2_17_Halls` - Hall's coalescence kernel
- `c1_ppb_2_17_Longs` - Long's coalescence kernel
- `c1_ppb_2_17_sedim` - Sedimentation coalescence kernel

### C2 Parameter Cases
These use modified parameters with 2048 particles per cell and a simulation time of 3600s:

- `c2_ppb_2_17_Halls` - Hall's coalescence kernel with C2 parameters
- `c2_ppb_2_17_Longs` - Long's coalescence kernel with C2 parameters
- `c2_ppb_2_21_Halls` - Hall's coalescence kernel with C2 parameters, higher multiplicity
- `c2_ppb_2_21_Longs` - Long's coalescence kernel with C2 parameters, higher multiplicity

Run `./scripts/run_erf.sh -l` for the complete list of available cases.

## Profiling

Use `profile_erf.sh` to run with platform-appropriate profiling tools.
By default, profiling runs use `max_step=10` for quick profiling.

```bash
./scripts/profile_erf.sh -c c1_ppb_2_13_golovin
```

| Short | Long               | Description                                    |
|-------|--------------------|------------------------------------------------|
| `-s`  | `--max-steps=N`    | Number of timesteps (default: 10)              |
| `-P`  | `--profiler=NAME`  | Profiler to use (see `--list-profilers`)       |
| `-o`  | `--output=NAME`    | Profile output name (default: `profile`)       |
| `-r`  | `--report`         | Generate report after profiling                |
| `-a`  | `--all`            | Profile all cases sequentially                 |

## Creating New Input Variants

```bash
./scripts/generate_inputs.sh NEW_CASE_NAME override1.conf [override2.conf ...]
./scripts/generate_inputs.sh --list  # Show available templates
```