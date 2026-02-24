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
#   -m, --mass-alpha      Use particle mass for transparency (log scale)
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
MASS_ALPHA=""
PLOT_TYPE="superdroplets"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--run=*)
            [[ "$1" == -r ]] && { shift; RUN_DIR="$1"; } || RUN_DIR="${1#*=}" ;;
        -o|--output=*)
            [[ "$1" == -o ]] && { shift; OUTPUT_DIR="$1"; } || OUTPUT_DIR="${1#*=}" ;;
        -p|--with-particles)
            WITH_PARTICLES="-p" ;;
        -f|--field=*)
            [[ "$1" == -f ]] && { shift; FIELD_NAME="$1"; } || FIELD_NAME="${1#*=}" ;;
        -m|--mass-alpha)
            MASS_ALPHA="--particle-mass-alpha" ;;
        -t|--type=*)
            [[ "$1" == -t ]] && { shift; PLOT_TYPE="$1"; } || PLOT_TYPE="${1#*=}" ;;
        -h|--help)
            usage ;;
        *)
            error "Unknown option: $1" ;;
    esac
    shift
done

# Auto-detect run directory if not specified
if [[ -z "$RUN_DIR" ]]; then
    # Look for .run_* directories
    RUN_DIRS=($(ls -d "$ROOT_DIR"/.run_* 2>/dev/null | sort -r))
    if [[ ${#RUN_DIRS[@]} -eq 0 ]]; then
        error "No run directories found. Use -r to specify one."
    fi
    RUN_DIR="${RUN_DIRS[0]}"
    info "Auto-detected run directory: $(basename "$RUN_DIR")"
fi

# Validate run directory
if [[ ! -d "$RUN_DIR" ]]; then
    error "Run directory not found: $RUN_DIR"
fi

# Check for plotfiles
PLOTFILES=($(ls -d "$RUN_DIR"/plt* 2>/dev/null))
if [[ ${#PLOTFILES[@]} -eq 0 ]]; then
    error "No plotfiles found in $RUN_DIR"
fi

info "Found ${#PLOTFILES[@]} plotfiles"

# Set default output directory
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$RUN_DIR/plots"
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
        info "  Output: $OUTPUT_DIR"
        [[ -n "$FIELD_NAME" ]] && info "  Field: $FIELD_NAME"
        [[ -n "$WITH_PARTICLES" ]] && info "  Particles: enabled"
        [[ -n "$MASS_ALPHA" ]] && info "  Particle alpha: mass-weighted"
        echo

        # Build command with optional arguments
        CMD="python3 \"$PLOT_SCRIPT\" \"$RUN_DIR\" -o \"$OUTPUT_DIR\""
        [[ -n "$WITH_PARTICLES" ]] && CMD="$CMD $WITH_PARTICLES"
        [[ -n "$FIELD_NAME" ]] && CMD="$CMD -f \"$FIELD_NAME\""
        [[ -n "$MASS_ALPHA" ]] && CMD="$CMD $MASS_ALPHA"

        eval $CMD
        ;;
    *)
        error "Unknown plot type: $PLOT_TYPE"
        ;;
esac

info "Done! Plots saved to $OUTPUT_DIR"
