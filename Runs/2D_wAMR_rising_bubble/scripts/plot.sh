#!/bin/bash
#
# Convenience wrapper for plotting scripts
#
# Usage:
#   ./plot.sh [OPTIONS]
#
# Options:
#   -r, --run=DIR         Run directory to process (default: auto-detect from .run_*)
#   -o, --output=DIR      Output directory for plots (default: <run_dir>/plots)
#   -p, --with-particles  Include particle position plots
#   -f, --field=FIELD     Field to plot (default: super_droplets_moisture_number_density)
#                         For moist bubble use: qc
#   -l, --logscale        Use logarithmic scale for field plotting (default: linear)
#   -m, --mass-alpha      Use particle mass for transparency (log scale)
#   -n, --num-procs=N     Number of parallel processes (default: 1, use 0 for all CPUs)
#   -t, --type=TYPE       Plot type: superdroplets (default)
#   -h, --help            Show this help message
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' NC=''
fi

error() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
info()  { echo -e "${GREEN}==>${NC} $*"; }

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# Show help if no arguments provided
if [[ $# -eq 0 ]]; then
    usage
fi

# Parse arguments
RUN_DIR=""
OUTPUT_DIR=""
WITH_PARTICLES=""
FIELD_NAME=""
LOGSCALE=""
MASS_ALPHA=""
NUM_PROCS=""
PLOT_TYPE="superdroplets"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--run=*)
            if [[ "$1" == -r ]]; then
                shift
                # Take the next argument(s) - could be multiple if wildcard expanded
                # Collect all non-option arguments
                RUN_DIR_CANDIDATES=()
                while [[ $# -gt 0 && "$1" != -* ]]; do
                    RUN_DIR_CANDIDATES+=("$1")
                    shift
                done
                # Already shifted, so continue without shift at end
                continue
            else
                RUN_DIR_CANDIDATES=("${1#*=}")
            fi
            ;;
        -o|--output=*)
            [[ "$1" == -o ]] && { shift; OUTPUT_DIR="$1"; } || OUTPUT_DIR="${1#*=}" ;;
        -p|--with-particles)
            WITH_PARTICLES="-p" ;;
        -f|--field=*)
            [[ "$1" == -f ]] && { shift; FIELD_NAME="$1"; } || FIELD_NAME="${1#*=}" ;;
        -l|--logscale)
            LOGSCALE="-l" ;;
        -m|--mass-alpha)
            MASS_ALPHA="--particle-mass-alpha" ;;
        -n|--num-procs=*)
            [[ "$1" == -n ]] && { shift; NUM_PROCS="$1"; } || NUM_PROCS="${1#*=}" ;;
        -t|--type=*)
            [[ "$1" == -t ]] && { shift; PLOT_TYPE="$1"; } || PLOT_TYPE="${1#*=}" ;;
        -h|--help)
            usage ;;
        *)
            error "Unknown option: $1" ;;
    esac
    shift
done

# Select run directories to process
if [[ ${#RUN_DIR_CANDIDATES[@]} -gt 0 ]]; then
    # Sort all matching directories
    IFS=$'\n' RUN_DIRS=($(sort -r <<<"${RUN_DIR_CANDIDATES[*]}"))
    unset IFS
    if [[ ${#RUN_DIRS[@]} -gt 1 ]]; then
        info "Processing ${#RUN_DIRS[@]} directories: ${RUN_DIRS[*]}"
    fi
else
    # Auto-detect run directory if not specified
    RUN_DIRS=($(ls -d "$ROOT_DIR"/.run_* 2>/dev/null | sort -r))
    if [[ ${#RUN_DIRS[@]} -eq 0 ]]; then
        error "No run directories found. Use -r to specify one."
    fi
    RUN_DIRS=("${RUN_DIRS[0]}")
    info "Auto-detected run directory: $(basename "${RUN_DIRS[0]}")"
fi

# Process each run directory
for RUN_DIR in "${RUN_DIRS[@]}"; do
    # Validate run directory
    if [[ ! -d "$RUN_DIR" ]]; then
        echo "${RED}WARNING:${NC} Run directory not found: $RUN_DIR (skipping)"
        continue
    fi

    # Check for plotfiles
    PLOTFILES=($(ls -d "$RUN_DIR"/plt* 2>/dev/null))
    if [[ ${#PLOTFILES[@]} -eq 0 ]]; then
        echo "${RED}WARNING:${NC} No plotfiles found in $RUN_DIR (skipping)"
        continue
    fi

    info "Found ${#PLOTFILES[@]} plotfiles in $(basename "$RUN_DIR")"

    # Set output directory (use specified or default)
    if [[ -n "$OUTPUT_DIR" ]]; then
        CURRENT_OUTPUT_DIR="$OUTPUT_DIR"
    else
        CURRENT_OUTPUT_DIR="$RUN_DIR/plots"
    fi

    # Run the appropriate plotting script
    case "$PLOT_TYPE" in
        superdroplets)
            PLOT_SCRIPT="$SCRIPT_DIR/plot_superdroplets.py"
            if [[ ! -f "$PLOT_SCRIPT" ]]; then
                error "Plot script not found: $PLOT_SCRIPT"
            fi

            info "Plotting fields"
            info "  Input:  $RUN_DIR"
            info "  Output: $CURRENT_OUTPUT_DIR"
            [[ -n "$FIELD_NAME" ]] && info "  Field: $FIELD_NAME"
            [[ -n "$LOGSCALE" ]] && info "  Scale: logarithmic" || info "  Scale: linear"
            [[ -n "$WITH_PARTICLES" ]] && info "  Particles: enabled"
            [[ -n "$MASS_ALPHA" ]] && info "  Particle alpha: mass-weighted"
            [[ -n "$NUM_PROCS" ]] && info "  Parallel processes: $NUM_PROCS"
            echo

            # Build command with optional arguments
            CMD="python3 \"$PLOT_SCRIPT\" \"$RUN_DIR\" -o \"$CURRENT_OUTPUT_DIR\""
            [[ -n "$WITH_PARTICLES" ]] && CMD="$CMD $WITH_PARTICLES"
            [[ -n "$FIELD_NAME" ]] && CMD="$CMD -f \"$FIELD_NAME\""
            [[ -n "$LOGSCALE" ]] && CMD="$CMD $LOGSCALE"
            [[ -n "$MASS_ALPHA" ]] && CMD="$CMD $MASS_ALPHA"
            [[ -n "$NUM_PROCS" ]] && CMD="$CMD -n $NUM_PROCS"

            eval $CMD
            ;;
        *)
            error "Unknown plot type: $PLOT_TYPE"
            ;;
    esac

    info "Done! Plots saved to $CURRENT_OUTPUT_DIR"
    echo
done
