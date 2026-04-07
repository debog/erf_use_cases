#!/bin/bash
#
# Unified plotting script for ERF runs
#
# Usage:
#   ./plot.sh [OPTIONS]
#
# Options:
#   -c, --case=NAME       Input case name(s) (space-separated list, supports wildcards)
#                         Examples: -c BF02_moist_bubble_AMR1
#                                   -c BF02_moist_bubble_AMR0 BF02_moist_bubble_AMR1
#                                   -c BF02_moist_bubble_AMR*
#   -r, --run=DIR         Run directory to process (alternative to -c)
#   -o, --output=DIR      Output directory for plots (default: <run_dir>/plots)
#   -p, --with-particles  Include particle position plots
#   -f, --field=FIELD     Field(s) to plot (space-separated list)
#                         Default: super_droplets_moisture_number_density
#                         Examples: -f qc qv super_droplets_moisture_number_density
#   -l, --list-cases      List available input cases
#   --log                 Use logarithmic scale for field plotting (default: linear)
#   -m, --mass-alpha      Use particle mass for transparency (log scale)
#   -n, --num-procs=N     Number of parallel processes (default: 1, use 0 for all CPUs)
#   -h, --help            Show this help message
#
# Environment:
#   LCHOST            Platform identifier (auto-detected, or 'desktop' if unset)
#
# Examples:
#   # List available cases
#   ./plot.sh -l
#
#   # Plot qc for a single moist bubble case
#   ./plot.sh -c BF02_moist_bubble_AMR1 -f qc
#
#   # Plot for multiple cases
#   ./plot.sh -c BF02_moist_bubble_AMR0 BF02_moist_bubble_AMR1 -f qc
#
#   # Plot for cases matching a pattern
#   ./plot.sh -c BF02_moist_bubble_AMR* -f qc
#
#   # Plot multiple fields for a case
#   ./plot.sh -c BF02_moist_bubble_AMR1 -f qc super_droplets_moisture_number_density
#
#   # Plot with particles and use all CPUs
#   ./plot.sh -c BF02_dry_bubble_AMR1 -p -n 0 -f qc qv
#
#   # Use logarithmic scale
#   ./plot.sh -c BF02_moist_bubble_AMR1 -f qc --log
#
#   # Directly specify run directory
#   ./plot.sh -r .run_BF02_moist_bubble_AMR1.matrix.nproc00004 -f qc
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
INPUTS_DIR="$ROOT_DIR/inputs"

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

error() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
warn()  { echo -e "${YELLOW}WARNING:${NC} $*" >&2; }
info()  { echo -e "${GREEN}==>${NC} $*"; }
debug() { [[ -n "$VERBOSE" ]] && echo -e "${BLUE}DEBUG:${NC} $*" >&2 || true; }

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# List available input cases
list_cases() {
    echo "Available cases in $INPUTS_DIR:"
    for f in "$INPUTS_DIR"/inputs_*; do
        [[ -f "$f" ]] || continue
        local name=$(basename "$f" | sed 's/^inputs_//')
        echo "  $name"
    done
}

# Show help if no arguments provided
if [[ $# -eq 0 ]]; then
    usage
fi

# Parse arguments
CASES=()
RUN_DIR=""
OUTPUT_DIR=""
WITH_PARTICLES=""
FIELD_NAMES=()
LOGSCALE=""
MASS_ALPHA=""
NUM_PROCS=""
VERBOSE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--case=*)
            if [[ "$1" == -c ]]; then
                shift
                # Collect all non-option arguments as case names
                while [[ $# -gt 0 && "$1" != -* ]]; do
                    # Expand wildcards by checking if pattern matches any input files
                    if [[ "$1" == *"*"* ]] || [[ "$1" == *"?"* ]]; then
                        # This is a glob pattern - expand it
                        shopt -s nullglob
                        matched_files=("$INPUTS_DIR"/inputs_$1)
                        shopt -u nullglob
                        for matched in "${matched_files[@]}"; do
                            [[ -f "$matched" ]] && CASES+=("$(basename "$matched" | sed 's/^inputs_//')")
                        done
                    else
                        CASES+=("$1")
                    fi
                    shift
                done
                # Already shifted, so continue without shift at end
                continue
            else
                CASES+=("${1#*=}")
            fi
            ;;
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
            if [[ "$1" == -f ]]; then
                shift
                # Collect all non-option arguments as field names
                while [[ $# -gt 0 && "$1" != -* ]]; do
                    FIELD_NAMES+=("$1")
                    shift
                done
                # Already shifted, so continue without shift at end
                continue
            else
                FIELD_NAMES+=("${1#*=}")
            fi
            ;;
        -l|--list-cases)
            list_cases; exit 0 ;;
        --log)
            LOGSCALE="-l" ;;
        -m|--mass-alpha)
            MASS_ALPHA="--particle-mass-alpha" ;;
        -n|--num-procs=*)
            [[ "$1" == -n ]] && { shift; NUM_PROCS="$1"; } || NUM_PROCS="${1#*=}" ;;
        -v|--verbose)
            VERBOSE=1 ;;
        -h|--help)
            usage ;;
        *)
            error "Unknown option: $1" ;;
    esac
    shift
done

# Auto-detect platform from LCHOST, default to 'desktop'
if [[ -z "$LCHOST" ]]; then
    PLATFORM="desktop"
    debug "LCHOST not set, assuming desktop environment"
else
    PLATFORM="$LCHOST"
fi

# Determine run directories to process
if [[ ${#CASES[@]} -gt 0 ]]; then
    # Case name(s) provided - find matching run directories for this platform
    RUN_DIRS=()
    for CASE in "${CASES[@]}"; do
        debug "Looking for run directories matching case: $CASE, platform: $PLATFORM"

        # Pattern: .run_${CASE}.${PLATFORM}.*
        CASE_DIRS=($(ls -d "$ROOT_DIR"/.run_${CASE}.${PLATFORM}.* 2>/dev/null | sort -r))

        if [[ ${#CASE_DIRS[@]} -eq 0 ]]; then
            warn "No run directories found for case '$CASE' on platform '$PLATFORM'"
            continue
        fi

        if [[ ${#CASE_DIRS[@]} -gt 1 ]]; then
            info "Found ${#CASE_DIRS[@]} matching run directories for $CASE, using most recent: $(basename "${CASE_DIRS[0]}")"
        else
            info "Found run directory for $CASE: $(basename "${CASE_DIRS[0]}")"
        fi

        # Add the most recent run directory for this case
        RUN_DIRS+=("${CASE_DIRS[0]}")
    done

    if [[ ${#RUN_DIRS[@]} -eq 0 ]]; then
        error "No run directories found for any specified case on platform '$PLATFORM'
       Available directories: $(ls -d "$ROOT_DIR"/.run_* 2>/dev/null | xargs -n1 basename | head -5)"
    fi
elif [[ ${#RUN_DIR_CANDIDATES[@]} -gt 0 ]]; then
    # Run directory explicitly provided with -r
    IFS=$'\n' RUN_DIRS=($(sort -r <<<"${RUN_DIR_CANDIDATES[*]}"))
    unset IFS
    if [[ ${#RUN_DIRS[@]} -gt 1 ]]; then
        info "Processing ${#RUN_DIRS[@]} directories: ${RUN_DIRS[*]}"
    fi
else
    # Auto-detect run directory if neither -c nor -r specified
    RUN_DIRS=($(ls -d "$ROOT_DIR"/.run_* 2>/dev/null | sort -r))
    if [[ ${#RUN_DIRS[@]} -eq 0 ]]; then
        error "No run directories found. Use -c to specify case name or -r to specify directory."
    fi
    RUN_DIRS=("${RUN_DIRS[0]}")
    info "Auto-detected run directory: $(basename "${RUN_DIRS[0]}")"
fi

# Set default field if none specified
if [[ ${#FIELD_NAMES[@]} -eq 0 ]]; then
    FIELD_NAMES=("super_droplets_moisture_number_density")
fi

# Process each run directory
for RUN_DIR in "${RUN_DIRS[@]}"; do
    # Validate run directory
    if [[ ! -d "$RUN_DIR" ]]; then
        warn "Run directory not found: $RUN_DIR (skipping)"
        continue
    fi

    # Check for plotfiles
    PLOTFILES=($(ls -d "$RUN_DIR"/plt* 2>/dev/null | grep -v '\.visit$'))
    if [[ ${#PLOTFILES[@]} -eq 0 ]]; then
        warn "No plotfiles found in $RUN_DIR (skipping)"
        continue
    fi

    info "Found ${#PLOTFILES[@]} plotfiles in $(basename "$RUN_DIR")"

    # Set output directory (use specified or default)
    if [[ -n "$OUTPUT_DIR" ]]; then
        CURRENT_OUTPUT_DIR="$OUTPUT_DIR"
    else
        CURRENT_OUTPUT_DIR="$RUN_DIR/plots"
    fi

    # Process each field
    for FIELD_NAME in "${FIELD_NAMES[@]}"; do
        PLOT_SCRIPT="$SCRIPT_DIR/plot_superdroplets.py"
        if [[ ! -f "$PLOT_SCRIPT" ]]; then
            error "Plot script not found: $PLOT_SCRIPT"
        fi

        info "Plotting field: $FIELD_NAME"
        info "  Input:  $(basename "$RUN_DIR")"
        info "  Output: $CURRENT_OUTPUT_DIR"
        [[ -n "$LOGSCALE" ]] && info "  Scale: logarithmic" || info "  Scale: linear"
        [[ -n "$WITH_PARTICLES" ]] && info "  Particles: enabled"
        [[ -n "$MASS_ALPHA" ]] && info "  Particle alpha: mass-weighted"
        [[ -n "$NUM_PROCS" ]] && info "  Parallel processes: ${NUM_PROCS:-1}"
        echo

        # Build command with optional arguments
        CMD="python3 \"$PLOT_SCRIPT\" \"$RUN_DIR\" -o \"$CURRENT_OUTPUT_DIR\""
        CMD="$CMD -f \"$FIELD_NAME\""
        [[ -n "$WITH_PARTICLES" ]] && CMD="$CMD $WITH_PARTICLES"
        [[ -n "$LOGSCALE" ]] && CMD="$CMD $LOGSCALE"
        [[ -n "$MASS_ALPHA" ]] && CMD="$CMD $MASS_ALPHA"
        [[ -n "$NUM_PROCS" ]] && CMD="$CMD -n $NUM_PROCS"

        eval $CMD

        echo
    done

    info "Done! Plots saved to $CURRENT_OUTPUT_DIR"
    echo
done
