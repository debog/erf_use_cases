#!/bin/bash
#
# Unified ERF launcher script for 2D_TracersAdvection
# Supports multiple HPC platforms and local desktop execution
#
# Usage:
#   ./common/run.sh [OPTIONS]
#
# Options:
#   -c, --case=NAME       Input case name(s) - space separated or wildcards (e.g., Particle*)
#   -a, --all             Run all available cases
#   -m, --mode=MODE       Execution mode: interactive (default) or batch
#   -n, --ntasks=N        Override number of MPI tasks
#   -N, --nnodes=N        Override number of nodes
#   -q, --queue=NAME      Override queue/partition name
#   -t, --walltime=TIME   Override walltime (e.g., 1:00:00 or 1h)
#   -s, --max-steps=N     Override number of timesteps (uses input file default if unset)
#   -d, --dry-run         Show what would be executed without running
#   -l, --list-cases      List available input cases
#   -p, --list-platforms  List supported platforms
#   -v, --verbose         Enable verbose output
#   -h, --help            Show this help message
#
# Environment:
#   LCHOST            Platform identifier (auto-detected, or 'desktop' if unset)
#   ERF_BUILD         Path to ERF build directory (required)
#
# Examples:
#   # List available cases
#   ./common/run.sh -l
#
#   # Run a single case
#   ./common/run.sh -c ParticleFlat_AMR0
#
#   # Run multiple cases
#   ./common/run.sh -c ParticleFlat_AMR0 ParticleWoA_AMR0
#
#   # Run all cases matching pattern
#   ./common/run.sh -c Particle*
#
#   # Run all cases
#   ./common/run.sh -a
#
#   # Submit batch job
#   ./common/run.sh -c ParticleFlat_AMR0 -m batch
#

set -e

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SCRIPT_DIR/platforms.conf"
INPUTS_DIR="$ROOT_DIR/inputs"

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
    echo "Available cases in $INPUTS_DIR:"
    for f in "$INPUTS_DIR"/inputs_*; do
        [[ -f "$f" ]] || continue
        local name=$(basename "$f" | sed 's/^inputs_//')
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
    EXEC="$ERF_BUILD/Exec/erf_exec"
    if [[ ! -x "$EXEC" ]]; then
        error "ERF executable not found or not executable: $EXEC"
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

# Clean up previous run outputs
echo "Cleaning up previous run outputs..."
rm -f out.*.log Backtrace.* *core*
rm -rf plt* chk*

export OMP_NUM_THREADS=1

EOF

    # Build srun command with GPU support if needed
    if [[ "$GPU_SUPPORT" == "true" ]]; then
        local total_gpus=$((NTASKS * GPUS_PER_TASK))
        echo "srun --exclusive -N ${NNODES} -G ${total_gpus} -n ${NTASKS} $EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee out.${PLATFORM}.log" >> "$jobfile"
    else
        echo "srun -N ${NNODES} -n ${NTASKS} $EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee out.${PLATFORM}.log" >> "$jobfile"
    fi
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

# Clean up previous run outputs
echo "Cleaning up previous run outputs..."
rm -f out.*.log Backtrace.* *core*
rm -rf plt* chk*

export OMP_NUM_THREADS=1

flux run --exclusive --nodes=${NNODES} --ntasks ${NTASKS} $EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee out.${PLATFORM}.log
EOF
}

generate_run_script() {
    local runfile="run.sh"
    local scheduler=$(get_config "$PLATFORM" "scheduler")
    local runcmd=""

    case "$scheduler" in
        slurm)
            local debug_queue=$(get_config "$PLATFORM" "debug_queue" "pdebug")
            runcmd="srun --exclusive -N $NNODES -n $NTASKS -p $debug_queue"
            if [[ "$GPU_SUPPORT" == "true" ]]; then
                local total_gpus=$((NTASKS * GPUS_PER_TASK))
                runcmd="$runcmd -G ${total_gpus} --gpus-per-task=${GPUS_PER_TASK}"
            fi
            ;;
        flux)
            local debug_queue=$(get_config "$PLATFORM" "debug_queue" "pdebug")
            runcmd="flux run --exclusive --nodes=$NNODES --ntasks $NTASKS -q=$debug_queue"
            ;;
        direct)
            local mpi_launcher=$(get_config "$PLATFORM" "mpi_launcher" "mpirun")
            if command -v "$mpi_launcher" &>/dev/null; then
                runcmd="$mpi_launcher -n $NTASKS"
            else
                runcmd=""
            fi
            ;;
    esac

    cat > "$runfile" << EOF
#!/bin/bash
#
# Interactive run script for ERF case: $CASE
# Generated by run.sh on $(date)
#
# Platform: $PLATFORM
# Tasks:    $NTASKS
# Nodes:    $NNODES
#

set -e

# Clean up previous run outputs
echo "Cleaning up previous run outputs..."
rm -f out.*.log Backtrace.* *core*
rm -rf plt* chk*

export OMP_NUM_THREADS=1
EOF

    # Add environment variables for GPU support if needed
    local env_vars=$(get_config "$PLATFORM" "env_vars")
    if [[ -n "$env_vars" ]]; then
        for var in $env_vars; do
            echo "export $var" >> "$runfile"
        done
    fi

    cat >> "$runfile" << EOF

# Run ERF
EOF
    if [[ -n "$runcmd" ]]; then
        echo "$runcmd $EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee out.${PLATFORM}.log" >> "$runfile"
    else
        echo "$EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee out.${PLATFORM}.log" >> "$runfile"
    fi

    chmod +x "$runfile"
}

generate_standalone_job_script() {
    local jobfile="erf.job"
    local scheduler=$(get_config "$PLATFORM" "scheduler")

    if [[ "$scheduler" == "direct" ]]; then
        # For desktop, just create a simple run script
        cat > "$jobfile" << EOF
#!/bin/bash
#
# Job script for ERF case: $CASE
# Platform '$PLATFORM' does not support batch mode
# Use ./run.sh to run interactively
#

echo "Platform '$PLATFORM' does not support batch submission."
echo "Please use ./run.sh to run interactively."
exit 1
EOF
        chmod +x "$jobfile"
        return
    fi

    case "$scheduler" in
        slurm)
            generate_slurm_batch "$jobfile"
            ;;
        flux)
            generate_flux_batch "$jobfile"
            ;;
        *)
            error "Unknown scheduler: $scheduler"
            ;;
    esac

    chmod +x "$jobfile"
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
            runcmd="srun --exclusive -N $NNODES -n $NTASKS -p $debug_queue"
            if [[ "$GPU_SUPPORT" == "true" ]]; then
                local total_gpus=$((NTASKS * GPUS_PER_TASK))
                runcmd="$runcmd -G ${total_gpus} --gpus-per-task=${GPUS_PER_TASK}"
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

# Show help if no arguments provided
if [[ $# -eq 0 ]]; then
    usage
fi

# Parse command line arguments
CASES=()
RUN_ALL=false
MODE="interactive"
OVERRIDE_NTASKS=""
OVERRIDE_NNODES=""
OVERRIDE_QUEUE=""
OVERRIDE_WALLTIME=""
MAX_STEPS=""
DRY_RUN=""
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
            RUN_ALL=true
            ;;
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
        -s|--max-steps=*)
            [[ "$1" == -s ]] && { shift; MAX_STEPS="$1"; } || MAX_STEPS="${1#*=}" ;;
        -d|--dry-run)   DRY_RUN=1 ;;
        -v|--verbose)   VERBOSE=1 ;;
        -l|--list-cases) list_cases; exit 0 ;;
        -p|--list-platforms) list_platforms; exit 0 ;;
        -h|--help)      usage ;;
        *)              error "Unknown option: $1" ;;
    esac
    shift
done

# Auto-detect platform from LCHOST, default to 'desktop'
if [[ -z "$LCHOST" ]]; then
    PLATFORM="desktop"
    info "LCHOST not set, using desktop mode (generic Linux PC with mpirun)"
else
    PLATFORM="$LCHOST"
fi

# Validate inputs and environment
validate

# Determine which cases to run
if [[ "$RUN_ALL" == true ]]; then
    CASES=()
    for f in "$INPUTS_DIR"/inputs_*; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f" | sed 's/^inputs_//')
        CASES+=("$name")
    done
    info "Running all ${#CASES[@]} cases"
elif [[ ${#CASES[@]} -eq 0 ]]; then
    error "No cases specified. Use -c to specify case name(s), -a for all cases, or -l to list available cases."
fi

# Load platform configuration
SCHEDULER=$(get_config "$PLATFORM" "scheduler")
NTASKS="${OVERRIDE_NTASKS:-$(get_config "$PLATFORM" "ntasks" "4")}"
NNODES="${OVERRIDE_NNODES:-$(get_config "$PLATFORM" "nnodes" "1")}"
QUEUE="${OVERRIDE_QUEUE:-$(get_config "$PLATFORM" "queue")}"
WALLTIME="${OVERRIDE_WALLTIME:-$(get_config "$PLATFORM" "walltime" "12:00:00")}"
GPU_SUPPORT=$(get_config "$PLATFORM" "gpu_support" "false")
GPUS_PER_TASK=$(get_config "$PLATFORM" "gpus_per_task" "1")
CORES_PER_NODE=$(get_config "$PLATFORM" "cores_per_node" "4")
ACCOUNT=$(get_config "$PLATFORM" "account")

debug "Platform config loaded:"
debug "  scheduler=$SCHEDULER ntasks=$NTASKS nnodes=$NNODES"
debug "  queue=$QUEUE walltime=$WALLTIME gpu=$GPU_SUPPORT"

# Run each case
for CASE in "${CASES[@]}"; do
    info "========================================"
    info "Processing case: $CASE"
    info "========================================"

    # Check input file
    INPUT_FILE="$INPUTS_DIR/inputs_${CASE}"
    if [[ ! -f "$INPUT_FILE" ]]; then
        error "Input file not found: $INPUT_FILE
       Use --list-cases to see available cases."
    fi

    # Create working directory
    WORKDIR="$ROOT_DIR/.run_${CASE}.${PLATFORM}.$(printf "nproc%05d" "$NTASKS")"
    if [[ -d "$WORKDIR" ]]; then
        info "Removing existing directory: $WORKDIR"
        rm -rf "$WORKDIR"
    fi
    info "Creating working directory: $WORKDIR"
    mkdir -p "$WORKDIR"

    cd "$WORKDIR"

    # Create symlink to input file
    ln -sf "$INPUT_FILE" .
    INP="inputs_${CASE}"

    # Build extra arguments for ERF
    ERF_EXTRA_ARGS=""
    [[ -n "$MAX_STEPS" ]] && ERF_EXTRA_ARGS="max_step=$MAX_STEPS"

    # Generate run.sh and erf.job scripts in the run directory
    info "Generating run scripts in $WORKDIR"
    generate_run_script
    generate_standalone_job_script
    info "  Created run.sh for interactive execution"
    info "  Created erf.job for batch submission"

    # Execute based on mode
    case "$MODE" in
        interactive|i)
            run_interactive
            ;;
        batch|b)
            run_batch
            ;;
        *)
            error "Unknown mode: $MODE (use 'interactive' or 'batch')"
            ;;
    esac

    cd "$ROOT_DIR"
    echo
done

info "Done."
