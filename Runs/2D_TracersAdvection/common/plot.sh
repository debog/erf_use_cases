#!/bin/bash
#
# Unified plotting script for ERF 2D_TracersAdvection runs
#
# Usage:
#   ./common/plot.sh [OPTIONS]
#
# Options:
#   -c, --case=NAME       Input case name(s) - space separated or wildcards
#   -a, --all             Plot all available cases
#   -r, --run=DIR         Run directory to process (alternative to -c)
#   -o, --output=DIR      Output directory for plots (default: <run_dir>/plots)
#   -l, --list-cases      List available input cases
#   -v, --verbose         Enable verbose output
#   -h, --help            Show this help message
#
# Environment:
#   LCHOST            Platform identifier (auto-detected, or 'desktop' if unset)
#
# Examples:
#   # List available cases
#   ./common/plot.sh -l
#
#   # Plot a single case
#   ./common/plot.sh -c ParticleFlat_AMR0
#
#   # Plot multiple cases
#   ./common/plot.sh -c ParticleFlat_AMR0 ParticleWoA_AMR0
#
#   # Plot all cases matching pattern
#   ./common/plot.sh -c Particle*
#
#   # Plot all cases
#   ./common/plot.sh -a
#
#   # Directly specify run directory
#   ./common/plot.sh -r .run_ParticleFlat_AMR0.matrix.nproc00004
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
RUN_ALL=false
RUN_DIR_CANDIDATES=()
OUTPUT_DIR=""
VERBOSE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--case=*)
            if [[ "$1" == -c ]]; then
                shift
                # Collect all non-option arguments as case names
                while [[ $# -gt 0 && "$1" != -* ]]; do
                    # Expand wildcards for case matching
                    expanded=false
                    for f in "$INPUTS_DIR"/inputs_*; do
                        [[ -f "$f" ]] || continue
                        name=$(basename "$f" | sed 's/^inputs_//')
                        if [[ "$name" == $1 ]]; then
                            CASES+=("$name")
                            expanded=true
                        fi
                    done
                    if [[ "$expanded" == false ]]; then
                        # No wildcard match, add as-is
                        CASES+=("$1")
                    fi
                    shift
                done
                # Already shifted, so continue without shift at end
                continue
            else
                case_arg="${1#*=}"
                # Expand wildcards
                expanded=false
                for f in "$INPUTS_DIR"/inputs_*; do
                    [[ -f "$f" ]] || continue
                    name=$(basename "$f" | sed 's/^inputs_//')
                    if [[ "$name" == $case_arg ]]; then
                        CASES+=("$name")
                        expanded=true
                    fi
                done
                if [[ "$expanded" == false ]]; then
                    CASES+=("$case_arg")
                fi
            fi
            ;;
        -a|--all)
            RUN_ALL=true ;;
        -r|--run=*)
            if [[ "$1" == -r ]]; then
                shift
                # Take the next argument(s) - could be multiple if wildcard expanded
                # Collect all non-option arguments
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
        -l|--list-cases)
            list_cases; exit 0 ;;
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
RUN_DIRS=()

if [[ ${#RUN_DIR_CANDIDATES[@]} -gt 0 ]]; then
    # Run directory explicitly provided with -r
    IFS=$'\n' RUN_DIRS=($(sort -r <<<"${RUN_DIR_CANDIDATES[*]}"))
    unset IFS
    if [[ ${#RUN_DIRS[@]} -gt 1 ]]; then
        info "Processing ${#RUN_DIRS[@]} directories"
    fi
elif [[ "$RUN_ALL" == true ]]; then
    # Get all cases and find their run directories
    for f in "$INPUTS_DIR"/inputs_*; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f" | sed 's/^inputs_//')
        CASES+=("$name")
    done
    info "Plotting all ${#CASES[@]} cases"
elif [[ ${#CASES[@]} -gt 0 ]]; then
    # Cases provided with -c
    debug "Cases specified: ${CASES[*]}"
else
    error "No cases or run directories specified. Use -c, -a, or -r option."
fi

# For each case, find the matching run directory
if [[ ${#CASES[@]} -gt 0 ]]; then
    for CASE in "${CASES[@]}"; do
        # Pattern: .run_${CASE}.${PLATFORM}.*
        MATCHING_DIRS=($(ls -d "$ROOT_DIR"/.run_${CASE}.${PLATFORM}.* 2>/dev/null | sort -r))

        if [[ ${#MATCHING_DIRS[@]} -eq 0 ]]; then
            warn "No run directories found for case '$CASE' on platform '$PLATFORM'"
            warn "  Pattern: .run_${CASE}.${PLATFORM}.*"
            continue
        fi

        if [[ ${#MATCHING_DIRS[@]} -gt 1 ]]; then
            debug "Found ${#MATCHING_DIRS[@]} matching run directories for $CASE, using most recent: $(basename "${MATCHING_DIRS[0]}")"
        else
            debug "Found run directory: $(basename "${MATCHING_DIRS[0]}")"
        fi

        RUN_DIRS+=("${MATCHING_DIRS[0]}")
    done
fi

if [[ ${#RUN_DIRS[@]} -eq 0 ]]; then
    error "No run directories found to plot"
fi

# Process each run directory
for RUN_DIR in "${RUN_DIRS[@]}"; do
    # Validate run directory
    if [[ ! -d "$RUN_DIR" ]]; then
        warn "Run directory not found: $RUN_DIR (skipping)"
        continue
    fi

    info "========================================"
    info "Plotting: $(basename "$RUN_DIR")"
    info "========================================"

    # Check for plotfiles
    PLOTFILES=($(ls -d "$RUN_DIR"/plt????? 2>/dev/null))
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

    PLOT_SCRIPT="$SCRIPT_DIR/plot_snapshots.py"
    if [[ ! -f "$PLOT_SCRIPT" ]]; then
        error "Plot script not found: $PLOT_SCRIPT"
    fi

    info "  Input:  $(basename "$RUN_DIR")"
    info "  Output: $CURRENT_OUTPUT_DIR"
    echo

    # Run the plot script
    python3 "$PLOT_SCRIPT" "$RUN_DIR"

    echo
    info "Done! Plots saved to $CURRENT_OUTPUT_DIR"
    echo
done

info "All plotting complete."
