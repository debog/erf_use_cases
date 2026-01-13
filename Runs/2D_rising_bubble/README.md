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

| Option | Description |
|--------|-------------|
| `--case=NAME` | Input case name (default: `BF02_moist_bubble_SDM_unimodal_NaCl`) |
| `--mode=MODE` | `interactive` (default) or `batch` |
| `--ntasks=N` | Override MPI task count |
| `--nnodes=N` | Override node count |
| `--queue=NAME` | Override queue/partition |
| `--dry-run` | Preview without executing |
| `--list-cases` | Show available cases |
| `--list-platforms` | Show supported platforms |

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
./scripts/run_erf.sh --case=BF02_moist_bubble_Kessler

# Batch submission on HPC
./scripts/run_erf.sh --case=BF02_moist_bubble_SDM_unimodal_NaCl --mode=batch

# Custom resources
./scripts/run_erf.sh --ntasks=16 --nnodes=2 --queue=pbatch --mode=batch

# Preview commands without running
./scripts/run_erf.sh --dry-run
```

## Available Cases

- `BF02_moist_bubble_Kessler` - Bulk microphysics (quick test)
- `BF02_moist_bubble_SDM_unimodal_NaCl` - SuperDroplets with NaCl
- `BF02_moist_bubble_SDM_unimodal_NH42SO4` - SuperDroplets with ammonium sulfate
- `BF02_moist_bubble_SDM_inject_unimodal_NaCl` - SDM with particle injection
- `BF02_moist_bubble_IceSDM_unimodal_NaCl` - Ice-phase SDM

Run `./scripts/run_erf.sh --list-cases` for the complete list.

## Creating New Input Variants

```bash
./scripts/generate_inputs.sh NEW_CASE_NAME override1.conf [override2.conf ...]
./scripts/generate_inputs.sh --list  # Show available templates
```
