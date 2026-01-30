#!/bin/bash
#
# Setup and run script for initial sampling runs (max_step = 0)
# Creates run directory, input files, and run scripts for a single case
#
# Usage:
#   ./run_erf.sh [OPTIONS]
#
# Options:
#   -c, --case=NAME       Case name (default: mass_exponential)
#   -p, --platform=NAME   Platform to run on (default: auto-detect from LCHOST)
#   -a, --all             Run all available cases
#   -l, --list            List all available cases
#   -d, --dry-run         Show what would be created without creating
#   -h, --help            Show this help message
#
# Examples:
#   # List all available cases
#   ./run_erf.sh -l
#
#   # Run a specific case
#   ./run_erf.sh -c mass_exponential -p matrix
#
#   # Run all cases on a platform
#   ./run_erf.sh -a -p matrix
#
#   # Dry run to see what would be created
#   ./run_erf.sh -c mass_exponential -p matrix -d
#
# Environment:
#   LCHOST            Platform identifier (auto-detected, or 'desktop' if unset)
#   ERF_BUILD         Path to ERF build directory (required)
#

set -e

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SCRIPT_DIR/platforms.conf"
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

# Parse configuration file for a given platform and key
get_config() {
    local platform="$1" key="$2" default="${3:-}"
    local in_section=false value=""

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Check for section header
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\] ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$platform" ]]; then
                in_section=true
            else
                in_section=false
            fi
            continue
        fi

        # Parse key=value if in correct section
        if $in_section && [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*) ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$key" ]]; then
                value="${BASH_REMATCH[2]}"
                # Trim trailing whitespace and comments
                value="${value%%#*}"
                value="${value%"${value##*[![:space:]]}"}"
                echo "$value"
                return 0
            fi
        fi
    done < "$CONFIG_FILE"

    echo "$default"
}

# Check if platform exists in config
platform_exists() {
    local platform="$1"
    grep -q "^\[$platform\]" "$CONFIG_FILE" 2>/dev/null
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

# =============================================================================
# Parse arguments
# =============================================================================
# Show help if no arguments provided
if [[ $# -eq 0 ]]; then
    usage
fi

CASE="$DEFAULT_CASE"
PLATFORM="${LCHOST:-desktop}"
DRY_RUN=""
RUN_ALL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--case=*)
            [[ "$1" == -c ]] && { shift; CASE="$1"; } || CASE="${1#*=}" ;;
        -p|--platform=*)
            [[ "$1" == -p ]] && { shift; PLATFORM="$1"; } || PLATFORM="${1#*=}" ;;
        -a|--all)       RUN_ALL=1 ;;
        -l|--list)      list_cases ;;
        -d|--dry-run)   DRY_RUN=1 ;;
        -h|--help)      usage ;;
        *)              error "Unknown option: $1" ;;
    esac
    shift
done

# =============================================================================
# Handle --all flag
# =============================================================================
if [[ -n "$RUN_ALL" ]]; then
    info "Running all 7 cases on platform: $PLATFORM"
    echo

    FAILED_CASES=()
    for case_name in "${ALL_CASES[@]}"; do
        info "======================================================================"
        info "Running case: $case_name"
        info "======================================================================"

        # Build the command with appropriate flags
        CMD=("$0" "-c" "$case_name" "-p" "$PLATFORM")
        [[ -n "$DRY_RUN" ]] && CMD+=("-d")

        # Run the case
        if "${CMD[@]}"; then
            info "Successfully completed: $case_name"
        else
            warn "Failed to complete: $case_name"
            FAILED_CASES+=("$case_name")
        fi
        echo
    done

    # Report summary
    info "======================================================================"
    info "All cases completed"
    info "======================================================================"
    info "Total cases: ${#ALL_CASES[@]}"
    info "Successful: $((${#ALL_CASES[@]} - ${#FAILED_CASES[@]}))"
    if [[ ${#FAILED_CASES[@]} -gt 0 ]]; then
        warn "Failed (${#FAILED_CASES[@]}): ${FAILED_CASES[*]}"
        exit 1
    else
        info "All cases ran successfully!"
    fi
    exit 0
fi

# =============================================================================
# Validate environment
# =============================================================================
if [[ -z "$ERF_BUILD" ]]; then
    error "ERF_BUILD environment variable is not set.
       Please set it to your ERF build directory, e.g.:
       export ERF_BUILD=/path/to/ERF/Build"
fi

if [[ ! -d "$ERF_BUILD" ]]; then
    error "ERF_BUILD directory does not exist: $ERF_BUILD"
fi

# Find ERF executable
ERF_EXEC_PATH="$ERF_BUILD/Exec/MoistRegTests/Bubble"
if [[ ! -d "$ERF_EXEC_PATH" ]]; then
    error "ERF executable directory not found: $ERF_EXEC_PATH"
fi

EXEC=$(ls "$ERF_EXEC_PATH"/erf_* 2>/dev/null | head -1) || true
if [[ -z "$EXEC" || ! -x "$EXEC" ]]; then
    error "No ERF executable found in $ERF_EXEC_PATH"
fi

# Check config file
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "Platform configuration file not found: $CONFIG_FILE"
fi

# Validate platform
if ! platform_exists "$PLATFORM"; then
    error "Unknown platform: $PLATFORM
       Available platforms in $CONFIG_FILE"
fi

# =============================================================================
# Setup directories and copy templates
# =============================================================================
info "Setting up initial sampling run for case: $CASE"
info "Platform: $PLATFORM"
info "ERF executable: $EXEC"

# Create directory structure
INPUTS_DIR="$ROOT_DIR/inputs"
TEMPLATES_DIR="$INPUTS_DIR/templates"
OVERRIDES_DIR="$TEMPLATES_DIR/overrides"

if [[ -z "$DRY_RUN" ]]; then
    mkdir -p "$OVERRIDES_DIR"

    # Check if base template exists
    if [[ ! -f "$TEMPLATES_DIR/base.inputs" ]]; then
        error "Base template not found: $TEMPLATES_DIR/base.inputs"
    fi
fi

# =============================================================================
# Merge input files
# =============================================================================
merge_inputs() {
    local output_file="$1"
    shift
    local files=("$@")

    # Use associative array to track key-value pairs (preserves last value)
    declare -A params
    declare -a order  # Track order of keys for output

    for file in "${files[@]}"; do
        while IFS= read -r line; do
            # Skip empty lines and pure comments
            if [[ -z "${line// }" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi

            # Parse key = value (with optional inline comment)
            if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9._]+)[[:space:]]*=[[:space:]]*(.*) ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"

                # Track key order (only add if new)
                if [[ -z "${params[$key]+isset}" ]]; then
                    order+=("$key")
                fi
                params["$key"]="$value"
            fi
        done < "$file"
    done

    # Generate output with section comments
    {
        echo "# ------------------  INPUTS TO MAIN PROGRAM  -------------------"
        echo "# Generated by run_erf.sh on $(date)"
        echo "# Case: $CASE"
        echo "# Base: $(basename "${files[0]}")"
        echo "# Overrides: ${files[*]:1}"
        echo "# ------------------------------------------------------------------"
        echo

        local prev_prefix=""
        for key in "${order[@]}"; do
            # Add section headers based on key prefix
            local prefix="${key%%.*}"
            if [[ "$prefix" != "$prev_prefix" ]]; then
                [[ -n "$prev_prefix" ]] && echo
                prev_prefix="$prefix"
            fi
            echo "${key} = ${params[$key]}"
        done
    } > "$output_file"
}

# =============================================================================
# Determine override files for the case
# =============================================================================
BASE_TEMPLATE="$TEMPLATES_DIR/base.inputs"
SAMPLING_OPTIONS_OVERRIDE="$OVERRIDES_DIR/${CASE}.conf"

# Validate that the case override file exists
if [[ ! -f "$SAMPLING_OPTIONS_OVERRIDE" ]]; then
    error "Case override file not found: $SAMPLING_OPTIONS_OVERRIDE
       Use './run_erf.sh -l' to list all available cases"
fi

# =============================================================================
# Create run directory and files
# =============================================================================
# Load platform configuration
SCHEDULER=$(get_config "$PLATFORM" "scheduler")
NTASKS=$(get_config "$PLATFORM" "ntasks" "4")
NNODES=$(get_config "$PLATFORM" "nnodes" "1")
GPU_SUPPORT=$(get_config "$PLATFORM" "gpu_support" "false")
GPUS_PER_TASK=$(get_config "$PLATFORM" "gpus_per_task" "1")
DEBUG_QUEUE=$(get_config "$PLATFORM" "debug_queue" "pdebug")

if [[ -z "$DRY_RUN" ]]; then
    # Create run directory (hidden)
    RUN_DIR="$ROOT_DIR/.run_${CASE}_${PLATFORM}_initial"

    if [[ -d "$RUN_DIR" ]]; then
        warn "Run directory already exists: $RUN_DIR"
        info "Removing existing directory"
        rm -rf "$RUN_DIR"
    fi

    info "Creating run directory: $RUN_DIR"
    mkdir -p "$RUN_DIR"

    # Generate input file
    INPUT_FILE="$RUN_DIR/inputs_${CASE}"
    info "Generating input file: $INPUT_FILE"
    merge_inputs "$INPUT_FILE" "$BASE_TEMPLATE" "$SAMPLING_OPTIONS_OVERRIDE"

    # Create run script
    RUN_SCRIPT="$RUN_DIR/run.sh"
    info "Creating run script: $RUN_SCRIPT"

    cat > "$RUN_SCRIPT" << EOF
#!/bin/bash
#
# Run script for initial sampling case: $CASE
# Platform: $PLATFORM
# Generated by run_erf.sh on $(date)
#

set -e

# Configuration
NTASKS=$NTASKS
NNODES=$NNODES
GPU_SUPPORT=$GPU_SUPPORT
GPUS_PER_TASK=$GPUS_PER_TASK
EXEC=$EXEC
INPUT=inputs_${CASE}

echo "Running ERF for initial sampling (max_step = 0)"
echo "Case: $CASE"
echo "Platform: $PLATFORM"
echo "Tasks: \$NTASKS"
echo "Nodes: \$NNODES"
[[ "\$GPU_SUPPORT" == "true" ]] && echo "GPUs per task: \$GPUS_PER_TASK"
echo

# Determine how to launch MPI job based on scheduler
EOF

    if [[ "$SCHEDULER" == "slurm" ]]; then
        cat >> "$RUN_SCRIPT" << EOF
# SLURM-based system (using debug queue for interactive runs)
DEBUG_QUEUE=$DEBUG_QUEUE
if [[ "\$GPU_SUPPORT" == "true" ]]; then
    # Total GPUs = ntasks * gpus_per_task
    TOTAL_GPUS=\$((\$NTASKS * \$GPUS_PER_TASK))
    srun -n \$NTASKS -N \$NNODES -p \$DEBUG_QUEUE -G \$TOTAL_GPUS \$EXEC \$INPUT 2>&1 | tee output.log
else
    srun -n \$NTASKS -N \$NNODES -p \$DEBUG_QUEUE \$EXEC \$INPUT 2>&1 | tee output.log
fi
EOF
    elif [[ "$SCHEDULER" == "flux" ]]; then
        cat >> "$RUN_SCRIPT" << EOF
# Flux-based system (using debug queue for interactive runs)
DEBUG_QUEUE=$DEBUG_QUEUE
flux run --exclusive --nodes=\$NNODES --ntasks \$NTASKS -q=\$DEBUG_QUEUE \$EXEC \$INPUT 2>&1 | tee output.log
EOF
    else
        cat >> "$RUN_SCRIPT" << EOF
# Direct execution with MPI
if command -v mpirun &>/dev/null; then
    mpirun -n \$NTASKS \$EXEC \$INPUT 2>&1 | tee output.log
else
    echo "WARNING: No MPI launcher found, running serially"
    \$EXEC \$INPUT 2>&1 | tee output.log
fi
EOF
    fi

    cat >> "$RUN_SCRIPT" << 'EOF'

echo
echo "Initial sampling complete. Check output files."
EOF

    chmod +x "$RUN_SCRIPT"

    info "Setup complete!"
    echo
    info "Run directory: $RUN_DIR"
    info "Input file: $INPUT_FILE"
    info "Run script: $RUN_SCRIPT"
    echo

    # Change to run directory and execute
    cd "$RUN_DIR"

    # Execute the run script
    ./run.sh

    echo
    info "Initial sampling complete. Output in: $RUN_DIR"

else
    info "DRY RUN - would create:"
    info "  Run directory: $ROOT_DIR/.run_${CASE}_${PLATFORM}_initial"
    info "  Input file: inputs_${CASE}"
    info "  Run script: run.sh"
    info "  Platform config: scheduler=$SCHEDULER ntasks=$NTASKS gpu=$GPU_SUPPORT queue=$DEBUG_QUEUE"
    info "  Would then run the simulation automatically"
fi
