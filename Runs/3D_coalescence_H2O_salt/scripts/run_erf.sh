#!/bin/bash
#
# Unified ERF launcher script
# Supports multiple HPC platforms and local desktop execution
#
# Usage:
#   ./run_erf.sh [OPTIONS]
#
# Options:
#   -c, --case=NAMES      Input case names (can be specified multiple times, or comma-separated, e.g. -c c1_ppb_2_13_golovin -c c2_ppb_2_13_Halls)
#                          Supports wildcards (e.g. -c c1* for all C1 cases, -c *_2_13_* for all 2^13 cases) (default: c1_ppb_2_13_golovin)
#   -m, --mode=MODE       Execution mode: interactive (default) or batch
#   -n, --ntasks=N        Override number of MPI tasks
#   -N, --nnodes=N        Override number of nodes
#   -q, --queue=NAME      Override queue/partition name
#   -t, --walltime=TIME   Override walltime (e.g., 1:00:00 or 1h)
#   -s, --max-steps=N     Override number of timesteps (uses input file default if unset)
#   -a, --all             Run all available cases sequentially
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
DEFAULT_CASE="c1_ppb_2_13_golovin"

# Import common functions
source "$SCRIPT_DIR/common_functions.sh"

# Script-specific settings
SCRIPT_NAME="run_erf.sh"

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
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
    ERF_EXEC_PATH="$ERF_BUILD/Exec/MoistRegTests/Bubble"
    if [[ ! -d "$ERF_EXEC_PATH" ]]; then
        error "ERF executable directory not found: $ERF_EXEC_PATH"
    fi

    EXEC=$(ls "$ERF_EXEC_PATH"/erf_* 2>/dev/null | head -1) || true
    if [[ -z "$EXEC" || ! -x "$EXEC" ]]; then
        error "No ERF executable found in $ERF_EXEC_PATH"
    fi

    # Validate case and platform
    validate_case "$CASE"

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

export OMP_NUM_THREADS=1

srun -n ${NTASKS} $EXEC $INP $ERF_EXTRA_ARGS 2>&1 | tee out.${PLATFORM}.log
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

# Parse command line arguments
CASE="${CASE:-}"
MODE="interactive"
OVERRIDE_NTASKS=""
OVERRIDE_NNODES=""
OVERRIDE_QUEUE=""
OVERRIDE_WALLTIME=""
MAX_STEPS=""
DRY_RUN=""
VERBOSE=""
RUN_ALL=""
declare -a CASE_ARRAY=()  # Array to collect multiple case arguments

# Display help if no arguments provided
if [[ $# -eq 0 ]]; then
    usage
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--case=*)
            if [[ "$1" == -c ]]; then
                shift
                # If there are multiple -c options, collect them
                if [[ -n "$CASE" ]]; then
                    CASE_ARRAY[${#CASE_ARRAY[@]}]="$CASE"
                fi
                CASE="$1"
            else
                # Handle --case=VALUE format
                if [[ -n "$CASE" ]]; then
                    CASE_ARRAY[${#CASE_ARRAY[@]}]="$CASE"
                fi
                CASE="${1#*=}"
            fi
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
        -a|--all)       RUN_ALL=1 ;;
        -d|--dry-run)   DRY_RUN=1 ;;
        -v|--verbose)   VERBOSE=1 ;;
        -l|--list-cases) list_cases; exit 0 ;;
        -p|--list-platforms) list_platforms; exit 0 ;;
        -h|--help)      usage ;;
        *)
            # Check if this might be a case name (not starting with -)
            if [[ "$1" != -* ]] && ( [[ "$1" == c1_* ]] || [[ "$1" == c2_* ]] || [[ "$1" == c3_* ]] ); then
                # It looks like a case name, add it to our list
                if [[ -n "$CASE" ]]; then
                    CASE_ARRAY[${#CASE_ARRAY[@]}]="$CASE"
                fi
                CASE="$1"
            else
                error "Unknown option: $1"
            fi
            ;;
    esac
    shift
done

# If we collected multiple cases, combine them with commas
if [[ ${#CASE_ARRAY[@]} -gt 0 ]]; then
    # Add the last case to the array
    CASE_ARRAY[${#CASE_ARRAY[@]}]="$CASE"

    # Join the array with commas
    CASE=$(IFS=,; echo "${CASE_ARRAY[*]}")
fi

# Handle wildcard patterns in case names
if [[ "$CASE" == *"*"* || "$CASE" == *"?"* ]]; then
    # Split by commas if multiple patterns
    if [[ "$CASE" == *","* ]]; then
        IFS=',' read -ra pattern_array <<< "$CASE"

        # Clear CASE for new matched cases
        CASE=""

        # Process each pattern
        for pattern in "${pattern_array[@]}"; do
            matching=$(match_cases "$pattern")
            if [[ -n "$matching" ]]; then
                # Add matching cases to CASE with comma separation
                if [[ -n "$CASE" ]]; then
                    CASE="$CASE,$matching"
                else
                    CASE="$matching"
                fi
            else
                warn "No cases match pattern: $pattern"
            fi
        done
    else
        # Single pattern
        matching=$(match_cases "$CASE")
        if [[ -n "$matching" ]]; then
            CASE="$matching"
        else
            warn "No cases match pattern: $CASE"
            exit 1
        fi
    fi

    # Debug output for matched cases
    debug "Expanded case patterns to: $CASE"
fi

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
WALLTIME="${OVERRIDE_WALLTIME:-$(get_config "$PLATFORM" "walltime" "1:00:00")}"
GPU_SUPPORT=$(get_config "$PLATFORM" "gpu_support" "false")
GPUS_PER_TASK=$(get_config "$PLATFORM" "gpus_per_task" "1")
ACCOUNT=$(get_config "$PLATFORM" "account")

debug "Platform config loaded:"
debug "  scheduler=$SCHEDULER ntasks=$NTASKS nnodes=$NNODES"
debug "  queue=$QUEUE walltime=$WALLTIME gpu=$GPU_SUPPORT"

# For single case or all cases, we'll use the run_single_case function
# No need to create the directory here

# Build extra arguments for ERF
ERF_EXTRA_ARGS=""
[[ -n "$MAX_STEPS" ]] && ERF_EXTRA_ARGS="max_step=$MAX_STEPS"

# Function to run all available cases
run_all_cases() {
    local mode="$1"
    local all_cases=( $(get_all_cases) )

    info "Running all ${#all_cases[@]} cases in $mode mode"

    for case_name in "${all_cases[@]}"; do
        info "======================"
        info "Running case: $case_name"
        info "======================"

        CASE="$case_name"

        # Create working directory for this case
        WORKDIR="$ROOT_DIR/.run_${CASE}.${PLATFORM}.$(printf "nproc%05d" "$NTASKS")"
        if [[ -d "$WORKDIR" ]]; then
            info "Removing existing directory: $WORKDIR"
            rm -rf "$WORKDIR"
        fi
        info "Creating working directory: $WORKDIR"
        mkdir -p "$WORKDIR"

        cd "$WORKDIR"

        # Generate input file in the run directory
        generate_input_file "$case_name" "$WORKDIR" "$SCRIPT_NAME" > /dev/null

        # Set the input file path (following the pattern used in reference scripts)
        INP="inputs_${case_name}"

        # Execute based on mode
        case "$mode" in
            interactive|i)
                run_interactive
                ;;
            batch|b)
                run_batch
                ;;
            *)
                error "Unknown mode: $mode (use 'interactive' or 'batch')"
                ;;
        esac

        echo ""  # Add an empty line between cases
    done

    info "All cases completed."
}

# Function to run a single case
run_single_case() {
    local case_to_run="$1"
    local run_mode="$2"

    info "======================"
    info "Running case: $case_to_run"
    info "======================"

    # Create working directory for this case
    local case_workdir="$ROOT_DIR/.run_${case_to_run}.${PLATFORM}.$(printf "nproc%05d" "$NTASKS")"
    if [[ -d "$case_workdir" ]]; then
        info "Removing existing directory: $case_workdir"
        rm -rf "$case_workdir"
    fi
    info "Creating working directory: $case_workdir"
    mkdir -p "$case_workdir"

    cd "$case_workdir"

    # Generate input file in the run directory
    generate_input_file "$case_to_run" "$case_workdir" "$SCRIPT_NAME" > /dev/null

    # Set the input file path (following the pattern used in reference scripts)
    local case_inp="inputs_${case_to_run}"

    # Save current global variables
    local saved_workdir="$WORKDIR"
    local saved_inp="$INP"
    local saved_case="$CASE"

    # Set global variables for the run functions
    WORKDIR="$case_workdir"
    INP="$case_inp"
    CASE="$case_to_run"

    # Execute based on mode
    case "$run_mode" in
        interactive|i)
            run_interactive
            ;;
        batch|b)
            run_batch
            ;;
        *)
            error "Unknown mode: $run_mode (use 'interactive' or 'batch')"
            ;;
    esac

    # Restore global variables
    WORKDIR="$saved_workdir"
    INP="$saved_inp"
    CASE="$saved_case"

    echo ""  # Add an empty line between cases
}

# Execute based on mode and whether to run all cases
if [[ -n "$RUN_ALL" ]]; then
    run_all_cases "$MODE"
elif [[ "$CASE" == *","* ]]; then
    # Multiple cases specified with comma separation
    info "Running multiple cases: $CASE"

    # Split CASE by commas into an array
    IFS=',' read -ra case_array <<< "$CASE"

    # Run each case in the array
    for case_item in "${case_array[@]}"; do
        run_single_case "$case_item" "$MODE"
    done
else
    # Single case
    run_single_case "$CASE" "$MODE"
fi

info "Done."
