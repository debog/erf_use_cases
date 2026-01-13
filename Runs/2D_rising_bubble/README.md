# 2D Rising Bubble Test Case

ERF simulation of the BF02 moist bubble test case with various microphysics options.

## Quick Start

```bash
./scripts/run_erf.sh --case=BF02_moist_bubble_SDM_unimodal_NaCl
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

| Short | Long | Description |
|-------|------|-------------|
| `-c` | `--case=NAME` | Input case name (default: `BF02_moist_bubble_SDM_unimodal_NaCl`) |
| `-m` | `--mode=MODE` | `interactive` (default) or `batch` |
| `-n` | `--ntasks=N` | Override MPI task count |
| `-N` | `--nnodes=N` | Override node count |
| `-q` | `--queue=NAME` | Override queue/partition |
| `-t` | `--walltime=TIME` | Override walltime |
| `-d` | `--dry-run` | Preview without executing |
| `-l` | `--list-cases` | Show available cases |
| `-p` | `--list-platforms` | Show supported platforms |
| `-v` | `--verbose` | Enable verbose output |
| `-h` | `--help` | Show help message |

## Platform Detection

The script auto-detects the platform from `$LCHOST`:

| LCHOST | Platform | Scheduler |
|--------|----------|-----------|
| (unset) | Desktop/workstation | mpirun |
| `dane` | DANE CPU cluster | SLURM |
| `matrix` | MATRIX GPU cluster | SLURM |
| `tuolumne` | Tuolumne | Flux |

## Examples

```bash
# Interactive run on desktop
./scripts/run_erf.sh -c BF02_moist_bubble_Kessler

# Batch submission on HPC
./scripts/run_erf.sh -c BF02_moist_bubble_SDM_unimodal_NaCl -m batch

# Custom resources
./scripts/run_erf.sh -n 16 -N 2 -q pbatch -m batch

# Preview commands without running
./scripts/run_erf.sh -d
```

## Available Cases

- `BF02_moist_bubble_Kessler` - Bulk microphysics (quick test)
- `BF02_moist_bubble_SDM_unimodal_NaCl` - SuperDroplets with NaCl
- `BF02_moist_bubble_SDM_unimodal_NH42SO4` - SuperDroplets with ammonium sulfate
- `BF02_moist_bubble_SDM_inject_unimodal_NaCl` - SDM with particle injection
- `BF02_moist_bubble_IceSDM_unimodal_NaCl` - Ice-phase SDM

Run `./scripts/run_erf.sh -l` for the complete list.

## Profiling

Use `profile_erf.sh` to run with platform-appropriate profiling tools:

```bash
./scripts/profile_erf.sh -c BF02_moist_bubble_Kessler
```

| Short | Long | Description |
|-------|------|-------------|
| `-P` | `--profiler=NAME` | Profiler to use (see `--list-profilers`) |
| `-o` | `--output=NAME` | Profile output name (default: `profile`) |
| `-r` | `--report` | Generate report after profiling |

### Platform Profilers

| Platform | Default | Alternative | Description |
|----------|---------|-------------|-------------|
| desktop | `perf` | - | Linux perf tools (CPU sampling) |
| dane | `perf` | - | Linux perf tools (CPU sampling) |
| matrix | `nsys` | `ncu` | NVIDIA Nsight Systems / Compute |
| tuolumne | `rocprof` | `omniperf` | AMD ROCm profiler / Omniperf |

### Profiling Examples

```bash
# Profile with default profiler
./scripts/profile_erf.sh -c BF02_moist_bubble_Kessler

# Use alternative profiler (e.g., ncu on matrix)
./scripts/profile_erf.sh -P ncu -c BF02_moist_bubble_Kessler

# Profile and generate report
./scripts/profile_erf.sh -r -c BF02_moist_bubble_Kessler

# Batch profiling job
./scripts/profile_erf.sh -m batch -c BF02_moist_bubble_SDM_unimodal_NaCl
```

## Creating New Input Variants

```bash
./scripts/generate_inputs.sh NEW_CASE_NAME override1.conf [override2.conf ...]
./scripts/generate_inputs.sh --list  # Show available templates
```
