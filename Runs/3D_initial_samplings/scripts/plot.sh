#!/bin/bash
#
# Plot initial sampling data from ERF Super Droplets simulation
#
# Usage:
#   ./plot.sh [OPTIONS]
#
# Options:
#   -c, --case=NAME       Case name (default: mass_exponential)
#   -p, --platform=NAME   Platform to plot from (default: auto-detect from LCHOST)
#   -a, --all             Plot all available cases
#   -o, --output=FILE     Output file path (default: plots/<case>_<platform>.png)
#   -t, --title=TEXT      Custom plot title (default: use case name)
#   -l, --list            List all available cases
#   -h, --help            Show this help message
#
# Examples:
#   # List all available cases
#   ./plot.sh -l
#
#   # Plot specific case and platform
#   ./plot.sh -c mass_exponential -p matrix
#
#   # Plot all cases for a platform
#   ./plot.sh -a -p matrix
#
#   # Specify custom output file and title
#   ./plot.sh -c mass_exponential -o my_plot.png -t "Matrix Run"
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_CASE="mass_exponential"

# All available cases
ALL_CASES=(
    "mass_constant"
    "mass_exponential"
    "radius_log_normal"
    "mass_constant_sampled"
    "mass_exponential_sampled"
    "radius_log_normal_sampled"
    "radius_lognormal_autorange_sampled"
)

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' NC=''
fi

error() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}WARNING:${NC} $*" >&2; }

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# List all available cases
list_cases() {
    echo "Available cases for initial sampling (max_step = 0):"
    echo
    echo "Constant multiplicity (3 cases):"
    echo "  mass_constant                     # Constant aerosol mass"
    echo "  mass_exponential                  # Exponential mass distribution (default)"
    echo "  radius_log_normal                 # Log-normal radius with bounds"
    echo
    echo "Sampled multiplicity (4 cases):"
    echo "  mass_constant_sampled             # Constant aerosol mass, sampled multiplicity"
    echo "  mass_exponential_sampled          # Exponential mass, sampled multiplicity"
    echo "  radius_log_normal_sampled         # Log-normal radius with bounds, sampled mult"
    echo "  radius_lognormal_autorange_sampled # Log-normal radius auto-range, sampled mult"
    echo
    echo "Note: radius_lognormal_autorange only works with sampled multiplicity"
    echo
    exit 0
}

# Parse arguments
# Show help if no arguments provided
if [[ $# -eq 0 ]]; then
    usage
fi

CASE="$DEFAULT_CASE"
PLATFORM="${LCHOST:-}"
OUTPUT_FILE=""
PLOT_TITLE=""
RUN_ALL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--case=*)
            [[ "$1" == -c ]] && { shift; CASE="$1"; } || CASE="${1#*=}" ;;
        -p|--platform=*)
            [[ "$1" == -p ]] && { shift; PLATFORM="$1"; } || PLATFORM="${1#*=}" ;;
        -a|--all)       RUN_ALL=1 ;;
        -o|--output=*)
            [[ "$1" == -o ]] && { shift; OUTPUT_FILE="$1"; } || OUTPUT_FILE="${1#*=}" ;;
        -t|--title=*)
            [[ "$1" == -t ]] && { shift; PLOT_TITLE="$1"; } || PLOT_TITLE="${1#*=}" ;;
        -l|--list)      list_cases ;;
        -h|--help)      usage ;;
        -*)             error "Unknown option: $1" ;;
        *)              error "Unknown argument: $1" ;;
    esac
    shift
done

# Handle --all flag
if [[ -n "$RUN_ALL" ]]; then
    # Determine platform
    if [[ -z "$PLATFORM" ]]; then
        PLATFORM="${LCHOST:-}"
        if [[ -z "$PLATFORM" ]]; then
            error "Platform must be specified with -p when using --all"
        fi
    fi

    info "Plotting all 7 cases for platform: $PLATFORM"
    echo

    FAILED_CASES=()
    for case_name in "${ALL_CASES[@]}"; do
        info "----------------------------------------------------------------------"
        info "Plotting case: $case_name"
        info "----------------------------------------------------------------------"

        # Build the command with appropriate flags
        CMD=("$0" "-c" "$case_name" "-p" "$PLATFORM")
        [[ -n "$OUTPUT_FILE" ]] && CMD+=("-o" "$OUTPUT_FILE")
        [[ -n "$PLOT_TITLE" ]] && CMD+=("-t" "$PLOT_TITLE")

        # Run the plot
        if "${CMD[@]}"; then
            info "Successfully plotted: $case_name"
        else
            warn "Failed to plot: $case_name"
            FAILED_CASES+=("$case_name")
        fi
        echo
    done

    # Report summary
    info "======================================================================"
    info "All plots completed"
    info "======================================================================"
    info "Total cases: ${#ALL_CASES[@]}"
    info "Successful: $((${#ALL_CASES[@]} - ${#FAILED_CASES[@]}))"
    if [[ ${#FAILED_CASES[@]} -gt 0 ]]; then
        warn "Failed (${#FAILED_CASES[@]}): ${FAILED_CASES[*]}"
        exit 1
    else
        info "All plots generated successfully!"
        info "Output directory: $ROOT_DIR/plots"
    fi
    exit 0
fi

# Find the run directory based on case and platform
if [[ -n "$PLATFORM" ]]; then
    # Specific platform requested
    RUN_DIR="$ROOT_DIR/.run_${CASE}_${PLATFORM}_initial"
else
    # Try to find any matching case directory
    info "No platform specified, searching for run directory matching case: $CASE"

    # Find all directories matching the case pattern
    RUN_DIR=$(find "$ROOT_DIR" -maxdepth 1 -type d -name ".run_${CASE}_*_initial" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

    if [[ -z "$RUN_DIR" ]]; then
        error "No run directory found for case: $CASE
       Available directories:"
        list_runs
    fi

    info "Found run directory: $(basename $RUN_DIR)"
fi

# Check if run directory exists
if [[ ! -d "$RUN_DIR" ]]; then
    error "Run directory does not exist: $RUN_DIR"
fi

# Check if data file exists
DATA_FILE="$RUN_DIR/super_droplets_moisture_g_lnR_00000.txt"
if [[ ! -f "$DATA_FILE" ]]; then
    error "Data file not found: $DATA_FILE
       Make sure the simulation has been run and produced output."
fi

# Create plots directory if it doesn't exist
PLOTS_DIR="$ROOT_DIR/plots"
mkdir -p "$PLOTS_DIR"

# Set default output file if not provided
if [[ -z "$OUTPUT_FILE" ]]; then
    # Extract platform from run directory name using the known case name
    RUN_BASENAME=$(basename "$RUN_DIR")
    # Pattern: .run_${CASE}_${PLATFORM}_initial
    # Remove the known prefix and suffix to get the platform
    DETECTED_PLATFORM=$(echo "$RUN_BASENAME" | sed -E "s/^\.run_${CASE}_(.+)_initial$/\1/")
    OUTPUT_FILE="$PLOTS_DIR/${CASE}_${DETECTED_PLATFORM}.png"
fi

# Build command
CMD="$SCRIPT_DIR/plot_initial_sampling.py"
CMD_ARGS=("$RUN_DIR")

# Use custom title if provided, otherwise use case name
if [[ -n "$PLOT_TITLE" ]]; then
    CMD_ARGS+=("-c" "$PLOT_TITLE")
else
    CMD_ARGS+=("-c" "$CASE")
fi

CMD_ARGS+=("-o" "$OUTPUT_FILE")

# Run the plotting script
info "Plotting: $CASE"
info "Run directory: $RUN_DIR"
info "Output file: $OUTPUT_FILE"
echo
python3 "$CMD" "${CMD_ARGS[@]}"
