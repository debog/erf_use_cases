#!/bin/bash
#
# SDM Regression Test Runner
# Runs SDM tests similar to ctest, comparing results against gold files
#
# Usage:
#   ./run_sdm_tests.sh [OPTIONS]
#
# Options:
#   -n, --ntasks=N        Number of MPI tasks (default: 4)
#   -t, --test=NAME       Run only specific test(s) (can be repeated or comma-separated)
#   -l, --list            List available SDM tests
#   --output-on-failure   Show test output when a test fails
#   --rerun-failed        Rerun only tests that failed in the previous run
#   -v, --verbose         Enable verbose output
#   -d, --dry-run         Show what would be executed without running
#   -h, --help            Show this help message
#
# Environment:
#   ERF_HOME              Path to ERF source directory (required)
#   ERF_BUILD             Path to ERF build directory (required)
#   LCHOST                Platform identifier (auto-detected from HOSTNAME if unset)
#   ERF_LLNL_GOLDFILES_DIR  Gold files directory for LLNL machines (required on dane/matrix/tuolumne)
#
# Gold Files Location:
#   dane:      $ERF_LLNL_GOLDFILES_DIR/dane/
#   matrix:    $ERF_LLNL_GOLDFILES_DIR/matrix/gpu/
#   tuolumne:  $ERF_LLNL_GOLDFILES_DIR/tuolumne/gpu/
#   other:     $ERF_HOME/Tests/ERFGoldFiles
#

set -e

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NTASKS=4
VERBOSE=""
DRY_RUN=""
SELECTED_TESTS=""
OUTPUT_ON_FAILURE=""
RERUN_FAILED=""
FAILED_TESTS_FILE="$SCRIPT_DIR/.failed_tests"

# =============================================================================
# Color output (disabled if not a terminal)
# =============================================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
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

# =============================================================================
# Test configuration
# =============================================================================
# SDM test tolerances: TEST_NAME -> "RTOL ATOL PLTFILE"
declare -A SDM_TEST_CONFIG=(
    # From CTestList.cmake (lines 217-236)
    ["SDM_Bubble2D_Adv"]="1e-12 1e-12 plt00050"
    ["SDM_Bubble2D_Adv_wInjection"]="5e-12 5e-12 plt00050"
    ["SDM_Bubble2D_Adv_InitSampling"]="1e-14 1e-14 plt00000"
    ["SDM_Bubble2D_Adv_TfzINAS"]="1e-14 1e-14 plt00000"
    ["SDM_Box3D_Cond"]="1e-14 2e-13 plt00010"
    ["SDM_Box3D_IceFrzDep"]="1e-14 1e-12 plt00010"
    ["SDM_Box3D_IceSub"]="1e-14 2e-13 plt00010"
    ["SDM_Box3D_VTerm"]="5e-13 1e-14 plt00001"
    ["SDM_Box3D_Recycling"]="5e-13 1e-14 plt00020"
    ["SDM_Congestus3D"]="5e-13 5e-13 plt00020"
    ["SDM_RICO3D"]="5e-13 5e-13 plt00010"
    ["SDM_RICO3D_InitSampling"]="1e-14 2e-13 plt00000"
    ["SDM_MultiSpecies_Bubble2D"]="5e-12 1e-12 plt00001"
    ["SDM_SineMassFlux"]="1e-14 1e-14 plt00050"
)

# Executable mapping (pattern -> relative path from ERF_BUILD)
declare -A EXEC_MAP=(
    ["RICO"]="Exec/DevTests/RICO"
    ["MultiSpecies"]="Exec/DevTests/MultiSpeciesBubble"
    ["Congestus"]="Exec/DevTests/TemperatureSourceSpatial"
    ["SineMassFlux"]="Exec/DevTests/sinusoidal_mass_flux"
)
DEFAULT_EXEC_PATH="Exec/MoistRegTests/Bubble"

# Tests requiring input_sounding file
declare -A INPUT_SOUNDING_MAP=(
    ["SDM_Congestus3D"]="input_sounding"
    ["SDM_RICO3D"]="input_sounding"
    ["SDM_RICO3D_InitSampling"]="input_sounding"
    ["SDM_SineMassFlux"]="input_sounding"
)

# =============================================================================
# Platform detection and gold files setup
# =============================================================================
detect_platform() {
    if [[ -z "$LCHOST" ]]; then
        LCHOST="${HOSTNAME%%.*}"
        debug "LCHOST not set, using hostname: $LCHOST"
    fi

    # Normalize to lowercase
    PLATFORM=$(echo "$LCHOST" | tr '[:upper:]' '[:lower:]')
    debug "Detected platform: $PLATFORM"
}

setup_goldfiles_dir() {
    case "$PLATFORM" in
        dane)
            if [[ -z "$ERF_LLNL_GOLDFILES_DIR" ]]; then
                error "ERF_LLNL_GOLDFILES_DIR is not set.
       This environment variable is required on LLNL machines (dane, matrix, tuolumne).
       Please set it to the root directory containing platform-specific gold files."
            fi
            GOLDFILES_DIR="$ERF_LLNL_GOLDFILES_DIR/dane"
            ;;
        matrix)
            if [[ -z "$ERF_LLNL_GOLDFILES_DIR" ]]; then
                error "ERF_LLNL_GOLDFILES_DIR is not set.
       This environment variable is required on LLNL machines (dane, matrix, tuolumne).
       Please set it to the root directory containing platform-specific gold files."
            fi
            GOLDFILES_DIR="$ERF_LLNL_GOLDFILES_DIR/matrix/gpu"
            ;;
        tuolumne)
            if [[ -z "$ERF_LLNL_GOLDFILES_DIR" ]]; then
                error "ERF_LLNL_GOLDFILES_DIR is not set.
       This environment variable is required on LLNL machines (dane, matrix, tuolumne).
       Please set it to the root directory containing platform-specific gold files."
            fi
            GOLDFILES_DIR="$ERF_LLNL_GOLDFILES_DIR/tuolumne/gpu"
            ;;
        *)
            GOLDFILES_DIR="$ERF_HOME/Tests/ERFGoldFiles"
            ;;
    esac

    if [[ ! -d "$GOLDFILES_DIR" ]]; then
        error "Gold files directory does not exist: $GOLDFILES_DIR"
    fi

    info "Using gold files from: $GOLDFILES_DIR"
}

setup_mpi_command() {
    case "$PLATFORM" in
        dane)
            MPI_CMD="srun -n $NTASKS -p pdebug"
            MPI_FCOMP_CMD="srun -n 1 -p pdebug"
            ;;
        matrix)
            MPI_CMD="srun -p pdebug -n $NTASKS -G $NTASKS -N 1"
            MPI_FCOMP_CMD="srun -p pdebug -n 1 -G 1 -N 1"
            ;;
        tuolumne)
            MPI_CMD="flux run --exclusive --nodes=1 --ntasks=$NTASKS -q pdebug"
            MPI_FCOMP_CMD="flux run --exclusive --nodes=1 --ntasks=1 -q pdebug"
            ;;
        *)
            if command -v mpirun &>/dev/null; then
                MPI_CMD="mpirun -n $NTASKS"
                MPI_FCOMP_CMD="mpirun -n 1"
            elif command -v mpiexec &>/dev/null; then
                MPI_CMD="mpiexec -n $NTASKS"
                MPI_FCOMP_CMD="mpiexec -n 1"
            else
                MPI_CMD=""
                MPI_FCOMP_CMD=""
            fi
            ;;
    esac

    debug "MPI command: $MPI_CMD"
}

# =============================================================================
# Validation
# =============================================================================
validate_environment() {
    if [[ -z "$ERF_HOME" ]]; then
        error "ERF_HOME environment variable is not set.
       Please set it to your ERF source directory, e.g.:
       export ERF_HOME=/path/to/ERF"
    fi

    if [[ ! -d "$ERF_HOME" ]]; then
        error "ERF_HOME directory does not exist: $ERF_HOME"
    fi

    if [[ -z "$ERF_BUILD" ]]; then
        error "ERF_BUILD environment variable is not set.
       Please set it to your ERF build directory, e.g.:
       export ERF_BUILD=/path/to/ERF/Build"
    fi

    if [[ ! -d "$ERF_BUILD" ]]; then
        error "ERF_BUILD directory does not exist: $ERF_BUILD"
    fi

    # Check for fcompare
    FCOMPARE_EXE=$(find "$ERF_BUILD" -name "amrex_fcompare" -type f -executable 2>/dev/null | head -1) || true
    if [[ -z "$FCOMPARE_EXE" ]]; then
        # Try AMREX_FCOMPARE environment variable
        if [[ -n "$AMREX_FCOMPARE" && -x "$AMREX_FCOMPARE" ]]; then
            FCOMPARE_EXE="$AMREX_FCOMPARE"
        else
            error "Cannot find amrex_fcompare. Build AMReX tools or set AMREX_FCOMPARE."
        fi
    fi
    debug "Using fcompare: $FCOMPARE_EXE"

    # Check for pcompare (optional, for particle tests)
    PCOMPARE_EXE=$(find "$ERF_BUILD" -name "amrex_pcompare" -type f -executable 2>/dev/null | head -1) || true
    if [[ -z "$PCOMPARE_EXE" ]]; then
        if [[ -n "$AMREX_PCOMPARE" && -x "$AMREX_PCOMPARE" ]]; then
            PCOMPARE_EXE="$AMREX_PCOMPARE"
        else
            warn "Cannot find amrex_pcompare. Particle comparison will be skipped."
        fi
    fi
    debug "Using pcompare: $PCOMPARE_EXE"
}

# =============================================================================
# Test discovery and execution
# =============================================================================
get_exec_path() {
    local test_name="$1"
    for pattern in "${!EXEC_MAP[@]}"; do
        if [[ "$test_name" == *"$pattern"* ]]; then
            echo "${ERF_BUILD}/${EXEC_MAP[$pattern]}"
            return
        fi
    done
    echo "${ERF_BUILD}/${DEFAULT_EXEC_PATH}"
}

discover_tests() {
    local testdir="$ERF_HOME/Tests/test_files"
    AVAILABLE_TESTS=()

    for dir in "$testdir"/SDM_*/; do
        if [[ -d "$dir" ]]; then
            AVAILABLE_TESTS+=("$(basename "$dir")")
        fi
    done

    debug "Found ${#AVAILABLE_TESTS[@]} SDM tests"
}

list_tests() {
    discover_tests
    echo "Available SDM tests:"
    for test in "${AVAILABLE_TESTS[@]}"; do
        local config="${SDM_TEST_CONFIG[$test]:-}"
        if [[ -n "$config" ]]; then
            read -r rtol atol pltfile <<< "$config"
            printf "  %-35s rtol=%-8s atol=%-8s plt=%s\n" "$test" "$rtol" "$atol" "$pltfile"
        else
            printf "  %-35s (no tolerance config)\n" "$test"
        fi
    done
}

run_single_test() {
    local test_name="$1"
    local test_dir="$ERF_HOME/Tests/test_files/$test_name"
    local work_dir="$PWD/.regtest_${PLATFORM}.${test_name}"

    # Get test configuration
    local config="${SDM_TEST_CONFIG[$test_name]:-}"
    if [[ -z "$config" ]]; then
        warn "No tolerance config for $test_name, using defaults"
        config="1e-12 1e-12 plt00010"
    fi
    read -r rtol atol pltfile <<< "$config"

    # Get gold file path
    local gold_dir="$GOLDFILES_DIR/$test_name"
    if [[ ! -d "$gold_dir" ]]; then
        echo -e "${YELLOW}SKIP${NC} - Gold files not found: $gold_dir"
        return 2
    fi

    # Get executable
    local exec_path=$(get_exec_path "$test_name")
    local exec_file=$(ls "$exec_path"/erf_* 2>/dev/null | head -1) || true
    if [[ -z "$exec_file" || ! -x "$exec_file" ]]; then
        echo -e "${YELLOW}SKIP${NC} - No executable found in $exec_path"
        return 2
    fi

    if [[ -n "$DRY_RUN" ]]; then
        echo "  Would run: $exec_file"
        echo "  Work dir:  $work_dir"
        echo "  Gold dir:  $gold_dir"
        echo "  Compare:   $pltfile (rtol=$rtol, atol=$atol)"
        return 0
    fi

    # Create work directory
    rm -rf "$work_dir"
    mkdir -p "$work_dir"

    # Copy input files
    for f in "$test_dir"/*; do
        if [[ -f "$f" ]]; then
            cp "$f" "$work_dir/"
        fi
    done

    # Run test
    local log_file="$work_dir/${test_name}.log"
    local input_file="$work_dir/${test_name}.i"

    # Build runtime options
    local runtime_opts=""
    if [[ -n "${INPUT_SOUNDING_MAP[$test_name]:-}" ]]; then
        local sounding="${INPUT_SOUNDING_MAP[$test_name]}"
        runtime_opts="erf.input_sounding_file=$work_dir/$sounding"
    fi

    debug "Running: $MPI_CMD $exec_file $input_file $runtime_opts"

    pushd "$work_dir" > /dev/null

    local start_time=$(date +%s)
    if $MPI_CMD "$exec_file" "$input_file" $runtime_opts > "$log_file" 2>&1; then
        local end_time=$(date +%s)
        local elapsed=$((end_time - start_time))

        # Check if output plotfile exists
        if [[ ! -d "$pltfile" ]]; then
            echo -e "${RED}FAIL${NC} - Output $pltfile not found (${elapsed}s)"
            popd > /dev/null
            return 1
        fi

        # Compare with gold file using fcompare
        local fcompare_flags="--abort_if_not_all_found --allow_diff_grids --rel_tol $rtol --abs_tol $atol"
        debug "Comparing: $MPI_FCOMP_CMD $FCOMPARE_EXE $fcompare_flags $gold_dir $pltfile"

        local fcompare_result=0
        if [[ -n "$VERBOSE" ]]; then
            echo ""
            echo -e "${CYAN}--- amrex_fcompare output for $test_name ---${NC}"
            $MPI_FCOMP_CMD "$FCOMPARE_EXE" $fcompare_flags "$gold_dir" "$pltfile" | tee -a "$log_file" || fcompare_result=$?
            echo -e "${CYAN}--- End of amrex_fcompare output ---${NC}"
            echo ""
        else
            $MPI_FCOMP_CMD "$FCOMPARE_EXE" $fcompare_flags "$gold_dir" "$pltfile" >> "$log_file" 2>&1 || fcompare_result=$?
        fi

        if [[ $fcompare_result -eq 0 ]]; then
            # Also run pcompare for particle data if available
            local particle_check_passed=true
            if [[ -n "$PCOMPARE_EXE" && -d "$pltfile/super_droplets_moisture" ]]; then
                if [[ -n "$VERBOSE" ]]; then
                    echo ""
                    echo -e "${CYAN}--- amrex_pcompare output for $test_name ---${NC}"
                    if ! $MPI_FCOMP_CMD "$PCOMPARE_EXE" "$gold_dir" "$pltfile" super_droplets_moisture | tee -a "$log_file"; then
                        particle_check_passed=false
                    fi
                    echo -e "${CYAN}--- End of amrex_pcompare output ---${NC}"
                    echo ""
                else
                    if ! $MPI_FCOMP_CMD "$PCOMPARE_EXE" "$gold_dir" "$pltfile" super_droplets_moisture >> "$log_file" 2>&1; then
                        particle_check_passed=false
                    fi
                fi
            fi

            if $particle_check_passed; then
                echo -e "${GREEN}PASS${NC} (${elapsed}s)"
                popd > /dev/null
                return 0
            else
                echo -e "${RED}FAIL${NC} - Particle comparison failed (${elapsed}s)"
                popd > /dev/null
                return 1
            fi
        else
            echo -e "${RED}FAIL${NC} - Field comparison failed (${elapsed}s)"
            popd > /dev/null
            return 1
        fi
    else
        local end_time=$(date +%s)
        local elapsed=$((end_time - start_time))
        echo -e "${RED}FAIL${NC} - Execution failed (${elapsed}s)"
        popd > /dev/null
        return 1
    fi
}

run_tests() {
    local tests_to_run=()
    local failed_tests=()

    # Handle --rerun-failed
    if [[ -n "$RERUN_FAILED" ]]; then
        if [[ ! -f "$FAILED_TESTS_FILE" ]]; then
            info "No failed tests file found. Nothing to rerun."
            return 0
        fi
        mapfile -t tests_to_run < "$FAILED_TESTS_FILE"
        if [[ ${#tests_to_run[@]} -eq 0 ]]; then
            info "No failed tests to rerun."
            return 0
        fi
        info "Rerunning ${#tests_to_run[@]} previously failed test(s)"
    elif [[ -n "$SELECTED_TESTS" ]]; then
        # Parse comma-separated or space-separated test names
        IFS=', ' read -ra tests_to_run <<< "$SELECTED_TESTS"
    else
        tests_to_run=("${AVAILABLE_TESTS[@]}")
    fi

    local total=${#tests_to_run[@]}
    local passed=0
    local failed=0
    local skipped=0

    # Calculate max test name length for alignment
    local max_name_len=0
    for test_name in "${tests_to_run[@]}"; do
        if [[ ${#test_name} -gt $max_name_len ]]; then
            max_name_len=${#test_name}
        fi
    done

    echo ""
    echo -e "${BOLD}Running SDM Regression Tests${NC}"
    echo "Platform:   $PLATFORM"
    echo "MPI tasks:  $NTASKS"
    echo "Gold files: $GOLDFILES_DIR"
    echo ""
    echo "========================================"

    local start_time=$(date +%s)

    for test_name in "${tests_to_run[@]}"; do
        printf "[%d/%d] %-${max_name_len}s : " "$((passed + failed + skipped + 1))" "$total" "$test_name"

        # Verify test exists
        if [[ ! -d "$ERF_HOME/Tests/test_files/$test_name" ]]; then
            echo -e "${YELLOW}SKIP${NC} - Test directory not found"
            ((++skipped))
            continue
        fi

        local result=0
        run_single_test "$test_name" || result=$?

        case $result in
            0) ((++passed)) ;;
            1)
                ((++failed))
                failed_tests+=("$test_name")
                # Show output on failure if requested
                if [[ -n "$OUTPUT_ON_FAILURE" ]]; then
                    local log_file="$PWD/.regtest_${PLATFORM}.${test_name}/${test_name}.log"
                    if [[ -f "$log_file" ]]; then
                        echo ""
                        echo -e "${CYAN}--- Output of $test_name ---${NC}"
                        cat "$log_file"
                        echo -e "${CYAN}--- End of $test_name output ---${NC}"
                        echo ""
                    fi
                fi
                ;;
            2) ((++skipped)) ;;
        esac
    done

    local end_time=$(date +%s)
    local total_elapsed=$((end_time - start_time))

    echo "========================================"
    echo ""
    echo -e "${BOLD}Test Summary${NC}"
    echo "Total:   $total"
    echo -e "Passed:  ${GREEN}$passed${NC}"
    echo -e "Failed:  ${RED}$failed${NC}"
    echo -e "Skipped: ${YELLOW}$skipped${NC}"
    echo "Time:    ${total_elapsed}s"
    echo ""

    # Save failed tests for --rerun-failed
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        printf '%s\n' "${failed_tests[@]}" > "$FAILED_TESTS_FILE"
        echo -e "${RED}Some tests failed. Check .regtest_* directories for logs.${NC}"
        echo "Use --rerun-failed to rerun only the failed tests."
        return 1
    else
        # Clear failed tests file on success
        rm -f "$FAILED_TESTS_FILE"
        if [[ $passed -eq 0 && $skipped -eq $total ]]; then
            echo -e "${YELLOW}All tests were skipped.${NC}"
            return 1
        else
            echo -e "${GREEN}All tests passed!${NC}"
            return 0
        fi
    fi
}

# =============================================================================
# Argument parsing
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--ntasks)
                NTASKS="$2"
                shift 2
                ;;
            --ntasks=*)
                NTASKS="${1#*=}"
                shift
                ;;
            -t|--test)
                if [[ -n "$SELECTED_TESTS" ]]; then
                    SELECTED_TESTS="$SELECTED_TESTS,$2"
                else
                    SELECTED_TESTS="$2"
                fi
                shift 2
                ;;
            --test=*)
                if [[ -n "$SELECTED_TESTS" ]]; then
                    SELECTED_TESTS="$SELECTED_TESTS,${1#*=}"
                else
                    SELECTED_TESTS="${1#*=}"
                fi
                shift
                ;;
            -l|--list)
                list_tests
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=1
                shift
                ;;
            --output-on-failure)
                OUTPUT_ON_FAILURE=1
                shift
                ;;
            --rerun-failed)
                RERUN_FAILED=1
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"

    detect_platform
    validate_environment
    setup_goldfiles_dir
    setup_mpi_command
    discover_tests

    run_tests
}

main "$@"
