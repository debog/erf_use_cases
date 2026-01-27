#!/bin/bash
#
# Unified ERF launcher script
# Supports multiple HPC platforms and local desktop execution
#
# Usage:
#   ./run_erf.sh [OPTIONS]
#
# Options:
#   -c, --case=NAME       Input case name (default: sdm_bimodal_amsu)
#   -m, --mode=MODE       Execution mode: interactive (default) or batch
#   -n, --ntasks=N        Override number of MPI tasks
#   -N, --nnodes=N        Override number of nodes
#   -q, --queue=NAME      Override queue/partition name
#   -t, --walltime=TIME   Override walltime (e.g., 1:00:00 or 1h)
#   -s, --max-step=N      Override number of timesteps (uses input file default if unset)
#   -T, --stop-time=T     Override simulation stop time (uses input file default if unset)
#   -d, --dry-run         Show what would be executed without running
#   -l, --list-cases      List available input cases
#   -p, --list-platforms  List supported platforms
#   -v, --verbose         Enable verbose output
#   -h, --help            Show this help message
#
# Environment:
#   LCHOST            Platform identifier (auto-detected, or 'desktop' if unset)
#   ERF_BUILD         Path to ERF build directory (required)
#   CASE              Alternative way to specify case name
#

set -e

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SCRIPT_DIR/platforms.conf"
INPUTS_DIR="$ROOT_DIR/inputs"
DEFAULT_CASE="sdm_bimodal_amsu"

# =============================================================================
# Color output (disabled if not a terminal)
# =============================================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# =============================================================================
# Helper functions
# =============================================================================
error() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
warn()  { echo -e "${YELLOW}WARNING:${NC} $*" >&2; }
info()  { echo -e "${GREEN}==>${NC} $*"; }
debug() { [[ -n "$VERBOSE" ]] && echo -e "${BLUE}DEBUG:${NC} $*" >&2 || true; }

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# Parse configuration file for a given platform
# Usage: get_config PLATFORM KEY [DEFAULT]
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

# List available platforms
list_platforms() {
    echo "Available platforms:"
    grep '^\[' "$CONFIG_FILE" | tr -d '[]' | while read -r p; do
        local scheduler=$(get_config "$p" "scheduler")
        local gpu=$(get_config "$p" "gpu_support" "false")
        printf "  %-12s scheduler=%-6s gpu=%s\n" "$p" "$scheduler" "$gpu"
    done
}

# List available input cases
list_cases() {
    echo "Available cases from override files in $INPUTS_DIR/templates/overrides:"
    for f in "$INPUTS_DIR"/templates/overrides/*.conf; do
        [[ -f "$f" ]] || continue
        local name=$(basename "$f" .conf)
        # Remove common prefixes like "temperature_source_" if present
        name=$(echo "$name" | sed -e 's/^temperature_source_//' -e 's/^overrides_//')
        echo "  $name"
    done
}

# Validate environment and inputs
validate() {
    # Check ERF_BUILD
    if [[ -z "$ERF_BUILD" ]]; then
        error "ERF_BUILD environment variable is not set.
       Please set it to your ERF build directory, e.g.:
       export ERF_BUILD=/path/to/ERF/Build"
    fi

    if [[ ! -d "$ERF_BUILD" ]]; then
        error "ERF_BUILD directory does not exist: $ERF_BUILD"
    fi

    # Find ERF executable
    ERF_EXEC_PATH="$ERF_BUILD/Exec/DevTests/TemperatureSourceSpatial_cold"
    if [[ ! -d "$ERF_EXEC_PATH" ]]; then
        error "ERF executable directory not found: $ERF_EXEC_PATH"
    fi

    EXEC="$ERF_EXEC_PATH/erf_abl_with_spatial_temperature_source_cold"
    if [[ ! -x "$EXEC" ]]; then
        error "ERF executable not found or not executable: $EXEC"
    fi

    # Check if override file exists for the case
    if ! ls "$INPUTS_DIR/templates/overrides"/*${CASE}*.conf &> /dev/null; then
        error "No override file found for case: $CASE
       Use --list-cases to see available cases."
    fi

    # Check config file
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Platform configuration file not found: $CONFIG_FILE"
    fi

    # Validate platform
    if ! platform_exists "$PLATFORM"; then
        error "Unknown platform: $PLATFORM
       Use --list-platforms to see available platforms."
    fi

    # Check if this is the big case on Matrix (not supported)
    if [[ "$CASE" == "sdm_bimodal_amsu_big" && "$PLATFORM" == "matrix" ]]; then
        error "The sdm_bimodal_amsu_big case cannot run on Matrix due to resource constraints.
       Please use Dane or Tuolumne for this case."
    fi
}

# =============================================================================
# Job generation functions
# =============================================================================

generate_slurm_batch() {
    local jobfile="$1"
    cat > "$jobfile" << EOF
#!/bin/bash

#SBATCH -J erf_${CASE}
#SBATCH -N ${NNODES}
#SBATCH -n ${NTASKS}
#SBATCH -t ${WALLTIME}
#SBATCH --exclusive
#SBATCH --export=ALL
EOF

    [[ -n "$ACCOUNT" ]] && echo "#SBATCH -A ${ACCOUNT}" >> "$jobfile"
    [[ -n "$QUEUE" ]] && echo "#SBATCH -p ${QUEUE}" >> "$jobfile"

    if [[ "$GPU_SUPPORT" == "true" ]]; then
        echo "#SBATCH --gpus-per-task=${GPUS_PER_TASK}" >> "$jobfile"
    fi

    cat >> "$jobfile" << EOF

export OMP_NUM_THREADS=1

srun -n ${NTASKS} --exclusive $EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee out.${PLATFORM}.log
EOF
}

generate_flux_batch() {
    local jobfile="$1"
    cat > "$jobfile" << EOF
#!/bin/bash

#flux: --job-name=erf_${CASE}
#flux: --output={{name}}-{{id}}.out
#flux: --nodes=${NNODES}
#flux: --time=${WALLTIME}
#flux: --exclusive
EOF

    [[ -n "$ACCOUNT" ]] && echo "#flux: --bank=${ACCOUNT}" >> "$jobfile"
    [[ -n "$QUEUE" ]] && echo "#flux: --queue=${QUEUE}" >> "$jobfile"

    # Add environment variables for GPU support
    local env_vars=$(get_config "$PLATFORM" "env_vars")
    if [[ -n "$env_vars" ]]; then
        for var in $env_vars; do
            echo "export $var" >> "$jobfile"
        done
    fi

    cat >> "$jobfile" << EOF

export OMP_NUM_THREADS=1

flux run --exclusive --nodes=${NNODES} --ntasks ${NTASKS} $EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee out.${PLATFORM}.log
EOF
}

# =============================================================================
# Execution functions
# =============================================================================

run_interactive() {
    local scheduler=$(get_config "$PLATFORM" "scheduler")
    local runcmd=""

    case "$scheduler" in
        slurm)
            local debug_queue=$(get_config "$PLATFORM" "debug_queue" "pdebug")
            runcmd="srun -n $NTASKS -N $NNODES -p $debug_queue --exclusive"
            if [[ "$GPU_SUPPORT" == "true" ]]; then
                runcmd="$runcmd --gpus-per-task=${GPUS_PER_TASK}"
            fi
            ;;
        flux)
            local debug_queue=$(get_config "$PLATFORM" "debug_queue" "pdebug")
            runcmd="flux run --exclusive --nodes=$NNODES --ntasks $NTASKS -q=$debug_queue"
            # Set environment for GPU
            local env_vars=$(get_config "$PLATFORM" "env_vars")
            for var in $env_vars; do
                export "${var?}"
            done
            ;;
        direct)
            local mpi_launcher=$(get_config "$PLATFORM" "mpi_launcher" "mpirun")
            if command -v "$mpi_launcher" &>/dev/null; then
                runcmd="$mpi_launcher -n $NTASKS"
            else
                warn "MPI launcher '$mpi_launcher' not found, running without MPI"
                runcmd=""
            fi
            ;;
        *)
            error "Unknown scheduler: $scheduler"
            ;;
    esac

    info "Running ERF interactively"
    info "  Platform:   $PLATFORM"
    info "  Case:       $CASE"
    info "  Tasks:      $NTASKS"
    info "  Nodes:      $NNODES"
    info "  Executable: $EXEC"
    info "  Input:      $INP"
    [[ -n "$MAX_STEPS" ]] && info "  Max steps:  $MAX_STEPS"
    [[ -n "$STOP_TIME" ]] && info "  Stop time:  $STOP_TIME"
    echo

    if [[ -n "$DRY_RUN" ]]; then
        echo "Would execute:"
        echo "  cd $WORKDIR"
        echo "  $runcmd $EXEC $INP $ERF_EXTRA_ARGS"
        return 0
    fi

    export OMP_NUM_THREADS=1

    if [[ -n "$runcmd" ]]; then
        $runcmd $EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee "out.${PLATFORM}.log"
    else
        $EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee "out.${PLATFORM}.log"
    fi
}

run_batch() {
    local scheduler=$(get_config "$PLATFORM" "scheduler")
    local jobfile="erf.job"

    if [[ "$scheduler" == "direct" ]]; then
        warn "Platform '$PLATFORM' does not support batch mode, falling back to interactive"
        run_interactive
        return
    fi

    info "Submitting ERF batch job"
    info "  Platform:   $PLATFORM"
    info "  Case:       $CASE"
    info "  Tasks:      $NTASKS"
    info "  Nodes:      $NNODES"
    info "  Queue:      ${QUEUE:-default}"
    info "  Walltime:   $WALLTIME"
    info "  Executable: $EXEC"
    info "  Input:      $INP"
    [[ -n "$MAX_STEPS" ]] && info "  Max steps:  $MAX_STEPS"
    [[ -n "$STOP_TIME" ]] && info "  Stop time:  $STOP_TIME"
    echo

    case "$scheduler" in
        slurm)
            generate_slurm_batch "$jobfile"
            if [[ -n "$DRY_RUN" ]]; then
                echo "Would submit job script:"
                cat "$jobfile"
                return 0
            fi
            sbatch "$jobfile"
            ;;
        flux)
            generate_flux_batch "$jobfile"
            if [[ -n "$DRY_RUN" ]]; then
                echo "Would submit job script:"
                cat "$jobfile"
                return 0
            fi
            flux batch "$jobfile"
            ;;
        *)
            error "Unknown scheduler for batch mode: $scheduler"
            ;;
    esac

    info "Job submitted from directory: $WORKDIR"
}

# =============================================================================
# Main
# =============================================================================

# Parse command line arguments
CASE="${CASE:-}"
MODE="interactive"
OVERRIDE_NTASKS=""
OVERRIDE_NNODES=""
OVERRIDE_QUEUE=""
OVERRIDE_WALLTIME=""
MAX_STEPS=""
STOP_TIME=""
DRY_RUN=""
VERBOSE=""
SHOW_HELP=""

# Show help if no arguments provided
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--case=*)
            [[ "$1" == -c ]] && { shift; CASE="$1"; } || CASE="${1#*=}" ;;
        -m|--mode=*)
            [[ "$1" == -m ]] && { shift; MODE="$1"; } || MODE="${1#*=}" ;;
        -n|--ntasks=*)
            [[ "$1" == -n ]] && { shift; OVERRIDE_NTASKS="$1"; } || OVERRIDE_NTASKS="${1#*=}" ;;
        -N|--nnodes=*)
            [[ "$1" == -N ]] && { shift; OVERRIDE_NNODES="$1"; } || OVERRIDE_NNODES="${1#*=}" ;;
        -q|--queue=*)
            [[ "$1" == -q ]] && { shift; OVERRIDE_QUEUE="$1"; } || OVERRIDE_QUEUE="${1#*=}" ;;
        -t|--walltime=*)
            [[ "$1" == -t ]] && { shift; OVERRIDE_WALLTIME="$1"; } || OVERRIDE_WALLTIME="${1#*=}" ;;
        -s|--max-step=*)
            [[ "$1" == -s ]] && { shift; MAX_STEPS="$1"; } || MAX_STEPS="${1#*=}" ;;
        -T|--stop-time=*)
            [[ "$1" == -T ]] && { shift; STOP_TIME="$1"; } || STOP_TIME="${1#*=}" ;;
        -d|--dry-run)   DRY_RUN=1 ;;
        -v|--verbose)   VERBOSE=1 ;;
        -l|--list-cases) list_cases; exit 0 ;;
        -p|--list-platforms) list_platforms; exit 0 ;;
        -h|--help)      usage ;;
        *)              error "Unknown option: $1" ;;
    esac
    shift
done

# Set defaults
CASE="${CASE:-$DEFAULT_CASE}"

# Auto-detect platform from LCHOST, default to 'desktop'
if [[ -z "$LCHOST" ]]; then
    PLATFORM="desktop"
    info "LCHOST not set, assuming desktop environment"
else
    PLATFORM="$LCHOST"
fi

# Validate inputs and environment
validate

# Load platform configuration
SCHEDULER=$(get_config "$PLATFORM" "scheduler")
NTASKS="${OVERRIDE_NTASKS:-$(get_config "$PLATFORM" "ntasks" "4")}"
NNODES="${OVERRIDE_NNODES:-$(get_config "$PLATFORM" "nnodes" "1")}"
QUEUE="${OVERRIDE_QUEUE:-$(get_config "$PLATFORM" "queue")}"
WALLTIME="${OVERRIDE_WALLTIME:-$(get_config "$PLATFORM" "walltime" "12:00:00")}"
GPU_SUPPORT=$(get_config "$PLATFORM" "gpu_support" "false")
GPUS_PER_TASK=$(get_config "$PLATFORM" "gpus_per_task" "1")
ACCOUNT=$(get_config "$PLATFORM" "account")

# Override configuration for sdm_bimodal_amsu_big case
if [[ "$CASE" == "sdm_bimodal_amsu_big" ]]; then
    if [[ "$PLATFORM" == "dane" ]]; then
        # 64 nodes with 112 MPI ranks per node = 7168 tasks
        NNODES="64"
        NTASKS="7168"
        info "Using large configuration for $CASE on $PLATFORM: $NTASKS tasks on $NNODES nodes"
    elif [[ "$PLATFORM" == "tuolumne" ]]; then
        # 64 nodes with 4 GPUs per node = 256 GPUs (tasks)
        NNODES="64"
        NTASKS="256"
        info "Using large configuration for $CASE on $PLATFORM: $NTASKS tasks on $NNODES nodes"
    fi
    # Extended walltime for the big case
    WALLTIME="24:00:00"
    if [[ "$PLATFORM" == "tuolumne" ]]; then
        WALLTIME="24h"  # Flux uses a different format
    fi
fi

debug "Platform config loaded:"
debug "  scheduler=$SCHEDULER ntasks=$NTASKS nnodes=$NNODES"
debug "  queue=$QUEUE walltime=$WALLTIME gpu=$GPU_SUPPORT"

# Create working directory
WORKDIR="$ROOT_DIR/.run_${CASE}.${PLATFORM}.$(printf "nproc%05d" "$NTASKS")"
if [[ -d "$WORKDIR" ]]; then
    info "Removing existing directory: $WORKDIR"
    rm -rf "$WORKDIR"
fi
info "Creating working directory: $WORKDIR"
mkdir -p "$WORKDIR"

cd "$WORKDIR"

# Copy input file directly to the run directory
OVERRIDE_FILE=$(ls "$INPUTS_DIR/templates/overrides"/*${CASE}*.conf | head -1)
debug "Using input file: $OVERRIDE_FILE"

# Copy the override file as the input file
info "Copying input file for case: $CASE"
cp -f "$OVERRIDE_FILE" "$WORKDIR/inputs_${CASE}"
INP="inputs_${CASE}"

# Verify the input file was created
if [[ ! -f "$INP" ]]; then
    error "Failed to copy input file: $INP"
fi

# Create symlink to original input_sounding file
if [[ -n "$ERF_HOME" ]]; then
    SOUNDING_PATH="$ERF_HOME/Exec/DevTests/TemperatureSourceSpatial_cold/input_sounding"
    if [[ -f "$SOUNDING_PATH" ]]; then
        ln -sf "$SOUNDING_PATH" .
        info "Linked input_sounding file from $ERF_HOME"
    else
        warn "input_sounding file not found at $SOUNDING_PATH"
    fi
else
    warn "ERF_HOME environment variable not set, cannot link input_sounding"
fi

# Build extra arguments for ERF
ERF_EXTRA_ARGS=""
[[ -n "$MAX_STEPS" ]] && ERF_EXTRA_ARGS="$ERF_EXTRA_ARGS max_step=$MAX_STEPS"
[[ -n "$STOP_TIME" ]] && ERF_EXTRA_ARGS="$ERF_EXTRA_ARGS stop_time=$STOP_TIME"
# Trim leading space if present
ERF_EXTRA_ARGS="${ERF_EXTRA_ARGS# }"

# Create a run script in the run directory
create_run_script() {
    local script_file="$WORKDIR/run.sh"
    info "Creating run script in the run directory: $script_file"

    # Get the platform-specific MPI launcher
    local mpi_cmd=""
    local scheduler=$(get_config "$PLATFORM" "scheduler")

    case "$scheduler" in
        slurm)
            local debug_queue=$(get_config "$PLATFORM" "debug_queue" "pdebug")
            mpi_cmd="srun -n $NTASKS -N $NNODES -p $debug_queue --exclusive"
            if [[ "$GPU_SUPPORT" == "true" ]]; then
                mpi_cmd="$mpi_cmd --gpus-per-task=${GPUS_PER_TASK}"
            fi
            ;;
        flux)
            local debug_queue=$(get_config "$PLATFORM" "debug_queue" "pdebug")
            mpi_cmd="flux run --exclusive --nodes=$NNODES --ntasks $NTASKS -q=$debug_queue"
            ;;
        direct)
            local mpi_launcher=$(get_config "$PLATFORM" "mpi_launcher" "mpirun")
            if command -v "$mpi_launcher" &>/dev/null; then
                mpi_cmd="$mpi_launcher -n $NTASKS"
            fi
            ;;
        *)
            mpi_cmd=""
            ;;
    esac

    cat > "$script_file" << EOF
#!/bin/bash
# Auto-generated run script by run_erf.sh on $(date)
# Run this script to execute ERF in the current directory

export OMP_NUM_THREADS=1

# Execute the ERF binary with appropriate launcher
$mpi_cmd $EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee run_output.log

# Exit with the status of the ERF executable
exit \${PIPESTATUS[0]}
EOF

    chmod +x "$script_file"
}

# Execute based on mode
case "$MODE" in
    interactive|i)
        run_interactive
        create_run_script
        ;;
    batch|b)
        run_batch
        create_run_script
        ;;
    *)
        error "Unknown mode: $MODE (use 'interactive' or 'batch')"
        ;;
esac

info "Done."
