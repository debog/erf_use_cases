#!/bin/bash
#
# ERF profiling script
# Runs ERF with platform-appropriate profiling tools
#
# Usage:
#   ./profile_erf.sh [OPTIONS]
#
# Options:
#   -c, --case=NAME       Input case name (default: sdm_bimodal_amsu)
#   -m, --mode=MODE       Execution mode: interactive (default) or batch
#   -n, --ntasks=N        Override number of MPI tasks
#   -N, --nnodes=N        Override number of nodes
#   -q, --queue=NAME      Override queue/partition name
#   -t, --walltime=TIME   Override walltime (e.g., 1:00:00 or 1h)
#   -s, --max-step=N      Number of timesteps to run (default: 10)
#   -T, --stop-time=T     Override simulation stop time (uses input file default if unset)
#   -P, --profiler=NAME   Profiler to use (platform-specific, see --list-profilers)
#   -o, --output=NAME     Profile output name (default: profile)
#   -r, --report          Generate report after profiling (interactive mode only)
#   -d, --dry-run         Show what would be executed without running
#   -l, --list-cases      List available input cases
#   -p, --list-platforms  List supported platforms
#       --list-profilers  List available profilers for current platform
#   -v, --verbose         Enable verbose output
#   -h, --help            Show this help message
#
# Environment:
#   LCHOST            Platform identifier (auto-detected, or 'desktop' if unset)
#   ERF_BUILD         Path to ERF build directory (required)
#   CASE              Alternative way to specify case name
#
# Platform Profilers:
#   desktop:   perf (Linux perf tools)
#   dane:      perf (Linux perf tools)
#   matrix:    nsys (NVIDIA Nsight Systems), ncu (Nsight Compute)
#   tuolumne:  rocprof (AMD ROCm profiler), omniperf (AMD Omniperf)
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
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
fi

# =============================================================================
# Helper functions
# =============================================================================
error() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
warn()  { echo -e "${YELLOW}WARNING:${NC} $*" >&2; }
info()  { echo -e "${GREEN}==>${NC} $*"; }
debug() { [[ -n "$VERBOSE" ]] && echo -e "${BLUE}DEBUG:${NC} $*" >&2 || true; }
prof()  { echo -e "${CYAN}[PROFILE]${NC} $*"; }

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# Parse configuration file for a given platform
get_config() {
    local platform="$1" key="$2" default="${3:-}"
    local in_section=false value=""

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\] ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$platform" ]]; then
                in_section=true
            else
                in_section=false
            fi
            continue
        fi

        if $in_section && [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*) ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$key" ]]; then
                value="${BASH_REMATCH[2]}"
                value="${value%%#*}"
                value="${value%"${value##*[![:space:]]}"}"
                echo "$value"
                return 0
            fi
        fi
    done < "$CONFIG_FILE"

    echo "$default"
}

platform_exists() {
    local platform="$1"
    grep -q "^\[$platform\]" "$CONFIG_FILE" 2>/dev/null
}

list_platforms() {
    echo "Available platforms:"
    grep '^\[' "$CONFIG_FILE" | tr -d '[]' | while read -r p; do
        local scheduler=$(get_config "$p" "scheduler")
        local profiler=$(get_config "$p" "profiler")
        printf "  %-12s scheduler=%-6s profiler=%s\n" "$p" "$scheduler" "$profiler"
    done
}

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

list_profilers() {
    echo "Available profilers for platform '$PLATFORM':"
    local profiler=$(get_config "$PLATFORM" "profiler")
    local profiler_cmd=$(get_config "$PLATFORM" "profiler_cmd")
    local profiler_alt=$(get_config "$PLATFORM" "profiler_alt")
    local profiler_alt_cmd=$(get_config "$PLATFORM" "profiler_alt_cmd")

    if [[ -n "$profiler" ]]; then
        echo "  $profiler (default)"
        echo "    Command: $profiler_cmd"
    fi
    if [[ -n "$profiler_alt" ]]; then
        echo "  $profiler_alt (alternative)"
        echo "    Command: $profiler_alt_cmd"
    fi

    echo
    echo "Profiler descriptions:"
    case "$PLATFORM" in
        desktop|dane)
            echo "  perf     - Linux perf tools for CPU profiling (sampling-based)"
            echo "             Generates perf.data, view with 'perf report'"
            ;;
        matrix)
            echo "  nsys     - NVIDIA Nsight Systems for GPU timeline profiling"
            echo "             Generates .nsys-rep file, view with Nsight Systems GUI"
            echo "  ncu      - NVIDIA Nsight Compute for detailed kernel analysis"
            echo "             Generates .ncu-rep file, view with Nsight Compute GUI"
            ;;
        tuolumne)
            echo "  rocprof  - AMD ROCm profiler for GPU kernel profiling"
            echo "             Generates CSV files with kernel statistics"
            echo "  omniperf - AMD Omniperf for detailed GPU performance analysis"
            echo "             Generates profile directory for omniperf analyze"
            ;;
    esac
}

validate() {
    if [[ -z "$ERF_BUILD" ]]; then
        error "ERF_BUILD environment variable is not set.
       Please set it to your ERF build directory, e.g.:
       export ERF_BUILD=/path/to/ERF/Build"
    fi

    if [[ ! -d "$ERF_BUILD" ]]; then
        error "ERF_BUILD directory does not exist: $ERF_BUILD"
    fi

    EXEC="$ERF_BUILD/Exec/erf_exec"
    if [[ ! -x "$EXEC" ]]; then
        error "ERF executable not found or not executable: $EXEC"
    fi

    # Check if override file exists for the case
    if ! ls "$INPUTS_DIR/templates/overrides"/*${CASE}*.conf &> /dev/null; then
        error "No override file found for case: $CASE
       Use -l to see available cases."
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Platform configuration file not found: $CONFIG_FILE"
    fi

    if ! platform_exists "$PLATFORM"; then
        error "Unknown platform: $PLATFORM
       Use -p to see available platforms."
    fi
}

# =============================================================================
# Profiler setup functions
# =============================================================================

get_profiler_cmd() {
    local profiler="$1"
    local default_profiler=$(get_config "$PLATFORM" "profiler")
    local alt_profiler=$(get_config "$PLATFORM" "profiler_alt")

    if [[ -z "$profiler" || "$profiler" == "$default_profiler" ]]; then
        get_config "$PLATFORM" "profiler_cmd"
    elif [[ "$profiler" == "$alt_profiler" ]]; then
        get_config "$PLATFORM" "profiler_alt_cmd"
    else
        error "Unknown profiler '$profiler' for platform '$PLATFORM'.
       Use --list-profilers to see available options."
    fi
}

get_profiler_report_cmd() {
    local profiler="$1"
    local default_profiler=$(get_config "$PLATFORM" "profiler")

    if [[ -z "$profiler" || "$profiler" == "$default_profiler" ]]; then
        get_config "$PLATFORM" "profiler_report"
    else
        # Alternative profilers typically need GUI tools
        echo ""
    fi
}

setup_profiler_env() {
    # Platform-specific environment setup for profiling
    case "$PLATFORM" in
        tuolumne)
            # AMD profiling setup
            export HSA_TOOLS_LIB=""
            ;;
    esac
}

# =============================================================================
# Job generation functions
# =============================================================================

generate_slurm_profile_batch() {
    local jobfile="$1"
    local prof_cmd="$2"

    cat > "$jobfile" << EOF
#!/bin/bash

#SBATCH -J profile_erf_${CASE}
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

echo "Starting profiled ERF run at \$(date)"
echo "Profiler: $PROFILER"
echo "Output: $PROFILE_OUTPUT"

# Build ERF arguments
local erf_args="max_step=$MAX_STEPS"
[[ -n "$STOP_TIME" ]] && erf_args="$erf_args stop_time=$STOP_TIME"

# Run with profiler
srun -n ${NTASKS} --exclusive $prof_cmd $EXEC $INP $erf_args 2>&1 | tee out.profile.${PLATFORM}.log

echo "Profiling completed at \$(date)"
echo "Profile output: \$(ls -la ${PROFILE_OUTPUT}* 2>/dev/null || echo 'Check working directory')"
EOF
}

generate_flux_profile_batch() {
    local jobfile="$1"
    local prof_cmd="$2"

    cat > "$jobfile" << EOF
#!/bin/bash

#flux: --job-name=profile_erf_${CASE}
#flux: --output={{name}}-{{id}}.out
#flux: --nodes=${NNODES}
#flux: --time=${WALLTIME}
#flux: --exclusive
EOF

    [[ -n "$ACCOUNT" ]] && echo "#flux: --bank=${ACCOUNT}" >> "$jobfile"
    [[ -n "$QUEUE" ]] && echo "#flux: --queue=${QUEUE}" >> "$jobfile"

    local env_vars=$(get_config "$PLATFORM" "env_vars")
    if [[ -n "$env_vars" ]]; then
        for var in $env_vars; do
            echo "export $var" >> "$jobfile"
        done
    fi

    cat >> "$jobfile" << EOF

export OMP_NUM_THREADS=1

echo "Starting profiled ERF run at \$(date)"
echo "Profiler: $PROFILER"
echo "Output: $PROFILE_OUTPUT"

# Build ERF arguments
local erf_args="max_step=$MAX_STEPS"
[[ -n "$STOP_TIME" ]] && erf_args="$erf_args stop_time=$STOP_TIME"

# Run with profiler
flux run --exclusive --nodes=${NNODES} --ntasks ${NTASKS} $prof_cmd $EXEC $INP $erf_args 2>&1 | tee out.profile.${PLATFORM}.log

echo "Profiling completed at \$(date)"
echo "Profile output: \$(ls -la ${PROFILE_OUTPUT}* 2>/dev/null || echo 'Check working directory')"
EOF
}

# =============================================================================
# Execution functions
# =============================================================================

run_profile_interactive() {
    local scheduler=$(get_config "$PLATFORM" "scheduler")
    local prof_cmd=$(get_profiler_cmd "$PROFILER")
    local runcmd=""

    # Replace output placeholder in profiler command
    prof_cmd="${prof_cmd//profile/$PROFILE_OUTPUT}"

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

    prof "Profiling ERF"
    info "  Platform:   $PLATFORM"
    info "  Case:       $CASE"
    info "  Tasks:      $NTASKS"
    info "  Nodes:      $NNODES"
    info "  Executable: $EXEC"
    info "  Input:      $INP"
    prof "  Profiler:   $PROFILER"
    prof "  Max steps:  $MAX_STEPS"
    [[ -n "$STOP_TIME" ]] && prof "  Stop time:  $STOP_TIME"
    prof "  Command:    $prof_cmd"
    prof "  Output:     $PROFILE_OUTPUT"
    echo

    if [[ -n "$DRY_RUN" ]]; then
        echo "Would execute:"
        echo "  cd $WORKDIR"
        if [[ -n "$runcmd" ]]; then
            echo "  $runcmd $prof_cmd $EXEC $INP max_step=$MAX_STEPS"
        else
            echo "  $prof_cmd $EXEC $INP max_step=$MAX_STEPS"
        fi
        return 0
    fi

    setup_profiler_env
    export OMP_NUM_THREADS=1

    # Build ERF arguments
    local erf_args="max_step=$MAX_STEPS"
    [[ -n "$STOP_TIME" ]] && erf_args="$erf_args stop_time=$STOP_TIME"

    prof "Starting profiled run..."
    local start_time=$(date +%s)

    if [[ -n "$runcmd" ]]; then
        $runcmd $prof_cmd $EXEC $INP $erf_args 2>&1 | tee "out.profile.${PLATFORM}.log"
    else
        $prof_cmd $EXEC $INP $erf_args 2>&1 | tee "out.profile.${PLATFORM}.log"
    fi

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    prof "Profiling completed in ${elapsed}s"

    # List generated profile files
    prof "Generated profile files:"
    ls -la ${PROFILE_OUTPUT}* 2>/dev/null || echo "  (check working directory for output)"

    # Generate report if requested
    if [[ -n "$GENERATE_REPORT" ]]; then
        local report_cmd=$(get_profiler_report_cmd "$PROFILER")
        if [[ -n "$report_cmd" ]]; then
            report_cmd="${report_cmd//profile/$PROFILE_OUTPUT}"
            prof "Generating report..."
            echo
            eval "$report_cmd" || warn "Report generation failed"
        else
            prof "No automatic report available for $PROFILER"
            prof "Use the appropriate GUI tool to analyze the profile"
        fi
    fi
}

run_profile_batch() {
    local scheduler=$(get_config "$PLATFORM" "scheduler")
    local prof_cmd=$(get_profiler_cmd "$PROFILER")
    local jobfile="profile_erf.job"

    # Replace output placeholder
    prof_cmd="${prof_cmd//profile/$PROFILE_OUTPUT}"

    if [[ "$scheduler" == "direct" ]]; then
        warn "Platform '$PLATFORM' does not support batch mode, falling back to interactive"
        run_profile_interactive
        return
    fi

    prof "Submitting profiled ERF batch job"
    info "  Platform:   $PLATFORM"
    info "  Case:       $CASE"
    info "  Tasks:      $NTASKS"
    info "  Nodes:      $NNODES"
    info "  Queue:      ${QUEUE:-default}"
    info "  Walltime:   $WALLTIME"
    info "  Executable: $EXEC"
    info "  Input:      $INP"
    prof "  Profiler:   $PROFILER"
    prof "  Max steps:  $MAX_STEPS"
    [[ -n "$STOP_TIME" ]] && prof "  Stop time:  $STOP_TIME"
    prof "  Output:     $PROFILE_OUTPUT"
    echo

    case "$scheduler" in
        slurm)
            generate_slurm_profile_batch "$jobfile" "$prof_cmd"
            if [[ -n "$DRY_RUN" ]]; then
                echo "Would submit job script:"
                cat "$jobfile"
                return 0
            fi
            sbatch "$jobfile"
            ;;
        flux)
            generate_flux_profile_batch "$jobfile" "$prof_cmd"
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

    prof "Job submitted from directory: $WORKDIR"
    prof "Profile output will be in: $WORKDIR/${PROFILE_OUTPUT}*"
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
PROFILER=""
PROFILE_OUTPUT="profile"
MAX_STEPS="10"
STOP_TIME=""
GENERATE_REPORT=""
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
        -P|--profiler=*)
            [[ "$1" == -P ]] && { shift; PROFILER="$1"; } || PROFILER="${1#*=}" ;;
        -o|--output=*)
            [[ "$1" == -o ]] && { shift; PROFILE_OUTPUT="$1"; } || PROFILE_OUTPUT="${1#*=}" ;;
        -r|--report)    GENERATE_REPORT=1 ;;
        -d|--dry-run)   DRY_RUN=1 ;;
        -v|--verbose)   VERBOSE=1 ;;
        -l|--list-cases) list_cases; exit 0 ;;
        -p|--list-platforms) list_platforms; exit 0 ;;
        --list-profilers)
            # Need platform first
            if [[ -z "$LCHOST" ]]; then
                PLATFORM="desktop"
            else
                PLATFORM="$LCHOST"
            fi
            list_profilers
            exit 0
            ;;
        -h|--help)      usage ;;
        *)              error "Unknown option: $1" ;;
    esac
    shift
done

# Set defaults
CASE="${CASE:-$DEFAULT_CASE}"

# Auto-detect platform
if [[ -z "$LCHOST" ]]; then
    PLATFORM="desktop"
    info "LCHOST not set, assuming desktop environment"
else
    PLATFORM="$LCHOST"
fi

# Set default profiler for platform
if [[ -z "$PROFILER" ]]; then
    PROFILER=$(get_config "$PLATFORM" "profiler")
    if [[ -z "$PROFILER" ]]; then
        error "No profiler configured for platform '$PLATFORM'"
    fi
fi

# Validate inputs and environment
validate

# Validate profiler is configured for this platform
validate_profiler() {
    local profiler="$1"
    local default_profiler=$(get_config "$PLATFORM" "profiler")
    local alt_profiler=$(get_config "$PLATFORM" "profiler_alt")

    if [[ -z "$profiler" || "$profiler" == "$default_profiler" ]]; then
        return 0
    elif [[ -n "$alt_profiler" && "$profiler" == "$alt_profiler" ]]; then
        return 0
    else
        return 1
    fi
}

if ! validate_profiler "$PROFILER"; then
    error "Unknown profiler '$PROFILER' for platform '$PLATFORM'.
       Use --list-profilers to see available options."
fi

# Check if profiler is available in PATH
if ! command -v "$PROFILER" &>/dev/null; then
    if [[ "$MODE" == "interactive" || "$MODE" == "i" ]]; then
        error "Profiler '$PROFILER' not found in PATH.
       Please ensure the profiler is installed and available.
       On HPC systems, you may need to load a module first:
         module load $PROFILER
       Or use --list-profilers to see available options."
    else
        warn "Profiler '$PROFILER' not found in PATH"
        warn "Assuming it will be available on compute nodes (batch mode)"
        warn "If the job fails, ensure the profiler module is loaded in the job script"
    fi
fi

# Load platform configuration
SCHEDULER=$(get_config "$PLATFORM" "scheduler")
NTASKS="${OVERRIDE_NTASKS:-$(get_config "$PLATFORM" "ntasks" "4")}"
NNODES="${OVERRIDE_NNODES:-$(get_config "$PLATFORM" "nnodes" "1")}"
QUEUE="${OVERRIDE_QUEUE:-$(get_config "$PLATFORM" "queue")}"
WALLTIME="${OVERRIDE_WALLTIME:-$(get_config "$PLATFORM" "walltime" "12:00:00")}"
GPU_SUPPORT=$(get_config "$PLATFORM" "gpu_support" "false")
GPUS_PER_TASK=$(get_config "$PLATFORM" "gpus_per_task" "1")
ACCOUNT=$(get_config "$PLATFORM" "account")

debug "Platform config loaded:"
debug "  scheduler=$SCHEDULER ntasks=$NTASKS nnodes=$NNODES"
debug "  queue=$QUEUE walltime=$WALLTIME gpu=$GPU_SUPPORT"
debug "  profiler=$PROFILER"

# Create working directory
WORKDIR="$ROOT_DIR/.profile_${CASE}.${PLATFORM}.$(printf "nproc%05d" "$NTASKS")"
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
prof "Copying input file for case: $CASE"
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
        prof "Linked input_sounding file from $ERF_HOME"
    else
        warn "input_sounding file not found at $SOUNDING_PATH"
    fi
else
    warn "ERF_HOME environment variable not set, cannot link input_sounding"
fi

# Create a profile script in the run directory
create_profile_script() {
    local script_file="$WORKDIR/profile.sh"
    prof "Creating profile script in the run directory: $script_file"

    local prof_cmd=$(get_profiler_cmd "$PROFILER")
    prof_cmd="${prof_cmd//profile/$PROFILE_OUTPUT}"

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
# Auto-generated profile script by profile_erf.sh on $(date)
# Run this script to profile ERF in the current directory

export OMP_NUM_THREADS=1

# Platform-specific profiler environment variables
$(case "$PLATFORM" in
    tuolumne) echo 'export HSA_TOOLS_LIB=""' ;;
    *) echo '# No special environment variables needed for this platform' ;;
esac)

# Execute the ERF binary with profiler and appropriate launcher
$mpi_cmd $prof_cmd $EXEC $INP max_step=$MAX_STEPS 2>&1 | tee profile_output.log

# Exit with the status of the ERF executable
exit \${PIPESTATUS[0]}
EOF

    chmod +x "$script_file"
}

# Execute based on mode
case "$MODE" in
    interactive|i)
        run_profile_interactive
        create_profile_script
        ;;
    batch|b)
        run_profile_batch
        create_profile_script
        ;;
    *)
        error "Unknown mode: $MODE (use 'interactive' or 'batch')"
        ;;
esac

prof "Done."
