#!/bin/bash
#
# Check current solutions against baseline
# Compares particle distributions and generates comparison plots
#
# Usage:
#   ./check_solution.sh [OPTIONS]
#
# Options:
#   -c, --case=NAME       Check specific case
#   -p, --platform=NAME   Check specific platform
#   -b, --baseline=DIR    Path to baseline directory (default: ../baselines)
#   -a, --all             Check all available cases
#   -l, --list            List available baseline cases
#   -h, --help            Show this help message
#
# Examples:
#   # List available baselines
#   ./check_solution.sh -l
#
#   # Check specific case
#   ./check_solution.sh -c mass_exponential -p matrix
#
#   # Check all cases for a platform
#   ./check_solution.sh -a -p matrix
#
#   # Use different baseline directory
#   ./check_solution.sh -b /path/to/baselines -a -p dane
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_CASE="mass_exponential"
DEFAULT_BASELINE_DIR="$ROOT_DIR/baselines"

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
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

error() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}WARNING:${NC} $*" >&2; }
pass()  { echo -e "${GREEN}PASS:${NC} $*"; }
fail()  { echo -e "${RED}FAIL:${NC} $*"; }

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# List available baseline cases
list_baselines() {
    if [[ ! -d "$BASELINE_DIR" ]]; then
        error "Baseline directory does not exist: $BASELINE_DIR"
    fi

    echo "Available baseline cases in $BASELINE_DIR:"
    echo

    # Find all baseline run directories
    BASELINE_RUNS=($(find "$BASELINE_DIR" -maxdepth 1 -type d -name ".run_*_initial" | sort))

    if [[ ${#BASELINE_RUNS[@]} -eq 0 ]]; then
        echo "  No baseline directories found"
        exit 0
    fi

    # Group by case name
    declare -A CASES_BY_NAME
    for baseline_run in "${BASELINE_RUNS[@]}"; do
        BASELINE_NAME=$(basename "$baseline_run")
        # Parse case and platform
        TEMP="${BASELINE_NAME#.run_}"
        TEMP="${TEMP%_initial}"
        PLATFORM="${TEMP##*_}"
        CASE="${TEMP%_*}"

        if [[ -z "${CASES_BY_NAME[$CASE]}" ]]; then
            CASES_BY_NAME[$CASE]="$PLATFORM"
        else
            CASES_BY_NAME[$CASE]="${CASES_BY_NAME[$CASE]}, $PLATFORM"
        fi
    done

    # Print grouped by case
    for case_name in $(echo "${!CASES_BY_NAME[@]}" | tr ' ' '\n' | sort); do
        printf "  %-35s (platforms: %s)\n" "$case_name" "${CASES_BY_NAME[$case_name]}"
    done

    echo
    echo "Total: ${#BASELINE_RUNS[@]} baseline directories"
    exit 0
}

# Parse arguments
# Show help if no arguments provided
if [[ $# -eq 0 ]]; then
    usage
fi

BASELINE_DIR="$DEFAULT_BASELINE_DIR"
CASE="$DEFAULT_CASE"
PLATFORM="${LCHOST:-}"
RUN_ALL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--case=*)
            [[ "$1" == -c ]] && { shift; CASE="$1"; } || CASE="${1#*=}" ;;
        -p|--platform=*)
            [[ "$1" == -p ]] && { shift; PLATFORM="$1"; } || PLATFORM="${1#*=}" ;;
        -b|--baseline=*)
            [[ "$1" == -b ]] && { shift; BASELINE_DIR="$1"; } || BASELINE_DIR="${1#*=}" ;;
        -a|--all)       RUN_ALL=1 ;;
        -l|--list)      list_baselines ;;
        -h|--help)      usage ;;
        *)              error "Unknown option: $1" ;;
    esac
    shift
done

# Check baseline directory exists
if [[ ! -d "$BASELINE_DIR" ]]; then
    error "Baseline directory does not exist: $BASELINE_DIR"
fi

# Create comparison output directory
COMPARE_DIR="$ROOT_DIR/comparisons"
mkdir -p "$COMPARE_DIR"

# Handle --all flag
if [[ -n "$RUN_ALL" ]]; then
    # Check platform is specified
    if [[ -z "$PLATFORM" ]]; then
        error "Platform must be specified with -p when using --all"
    fi

    info "Checking all 7 cases for platform: $PLATFORM"
    info "Baseline directory: $BASELINE_DIR"
    echo

    FAILED_CASES=()
    MISSING_CASES=()
    PASSED=0
    FAILED=0
    MISSING=0

    # Arrays to store error values for table
    declare -A MEAN_ERRORS
    declare -A STD_ERRORS
    declare -A STATUS

    for case_name in "${ALL_CASES[@]}"; do
        info "----------------------------------------------------------------------"
        info "Checking: $case_name on $PLATFORM"

        # Find baseline
        BASELINE_RUN="$BASELINE_DIR/.run_${case_name}_${PLATFORM}_initial"
        if [[ ! -d "$BASELINE_RUN" ]]; then
            warn "Baseline not found: $BASELINE_RUN"
            MISSING=$((MISSING + 1))
            MISSING_CASES+=("${case_name}_${PLATFORM}")
            STATUS["$case_name"]="MISSING"
            MEAN_ERRORS["$case_name"]="N/A"
            STD_ERRORS["$case_name"]="N/A"
            echo
            continue
        fi

        # Find current run
        CURRENT_RUN="$ROOT_DIR/.run_${case_name}_${PLATFORM}_initial"
        if [[ ! -d "$CURRENT_RUN" ]]; then
            fail "Current run directory not found: $CURRENT_RUN"
            MISSING=$((MISSING + 1))
            MISSING_CASES+=("${case_name}_${PLATFORM}")
            STATUS["$case_name"]="MISSING"
            MEAN_ERRORS["$case_name"]="N/A"
            STD_ERRORS["$case_name"]="N/A"
            echo
            continue
        fi

        # Run comparison and capture output
        OUTPUT_FILE="$COMPARE_DIR/${case_name}_${PLATFORM}_comparison.png"

        # Temporarily disable exit-on-error to capture comparison results
        set +e
        COMPARE_OUTPUT=$(python3 "$SCRIPT_DIR/compare_distributions.py" \
            "$BASELINE_RUN" \
            "$CURRENT_RUN" \
            -o "$OUTPUT_FILE" \
            -c "$case_name" 2>&1)
        COMPARE_EXIT=$?
        set -e

        # Parse errors from output
        MEAN_ERROR=$(echo "$COMPARE_OUTPUT" | grep "mean_radius:" | awk '{print $2}')
        STD_ERROR=$(echo "$COMPARE_OUTPUT" | grep "std_radius:" | awk '{print $2}')

        # Store results (use N/A if parsing failed)
        MEAN_ERRORS["$case_name"]="${MEAN_ERROR:-N/A}"
        STD_ERRORS["$case_name"]="${STD_ERROR:-N/A}"

        if [[ $COMPARE_EXIT -eq 0 ]]; then
            pass "$case_name on $PLATFORM"
            PASSED=$((PASSED + 1))
            STATUS["$case_name"]="PASS"
        else
            fail "$case_name on $PLATFORM"
            FAILED=$((FAILED + 1))
            FAILED_CASES+=("${case_name}_${PLATFORM}")
            STATUS["$case_name"]="FAIL"
        fi
        echo
    done

    # Print results table
    info "======================================================================"
    info "Results Summary"
    info "======================================================================"
    echo
    printf "%-40s %-15s %-15s %-10s\n" "Case" "Mean Error" "Std Error" "Status"
    printf "%-40s %-15s %-15s %-10s\n" "----" "----------" "---------" "------"

    for case_name in "${ALL_CASES[@]}"; do
        if [[ -n "${STATUS[$case_name]}" ]]; then
            # Get values
            MEAN_VAL="${MEAN_ERRORS[$case_name]}"
            STD_VAL="${STD_ERRORS[$case_name]}"
            STATUS_VAL="${STATUS[$case_name]}"

            # Format status with color
            if [[ "$STATUS_VAL" == "PASS" ]]; then
                STATUS_STR="${GREEN}PASS${NC}"
            elif [[ "$STATUS_VAL" == "FAIL" ]]; then
                STATUS_STR="${RED}FAIL${NC}"
            elif [[ "$STATUS_VAL" == "MISSING" ]]; then
                STATUS_STR="${YELLOW}MISSING${NC}"
            fi

            # Print entire line at once
            printf "%-40s %-15s %-15s %b\n" "$case_name" "$MEAN_VAL" "$STD_VAL" "$STATUS_STR"
        fi
    done
    echo

    # Print summary
    info "======================================================================"
    info "Summary"
    info "======================================================================"
    echo
    info "Total cases checked: $((PASSED + FAILED + MISSING))"
    pass "Passed: $PASSED"

    if [[ $FAILED -gt 0 ]]; then
        fail "Failed: $FAILED"
        echo "  Failed cases:"
        for case in "${FAILED_CASES[@]}"; do
            echo "    - $case"
        done
        echo
    fi

    if [[ $MISSING -gt 0 ]]; then
        warn "Missing: $MISSING"
        echo "  Missing cases (baseline or current not found):"
        for case in "${MISSING_CASES[@]}"; do
            echo "    - $case"
        done
        echo
    fi

    info "Comparison plots saved to: $COMPARE_DIR"
    echo

    if [[ $FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
fi

# Single case check
if [[ -z "$PLATFORM" ]]; then
    error "Platform must be specified with -p"
fi

info "Checking solution: $CASE on $PLATFORM"
info "Baseline directory: $BASELINE_DIR"
echo

# Find baseline
BASELINE_RUN="$BASELINE_DIR/.run_${CASE}_${PLATFORM}_initial"
if [[ ! -d "$BASELINE_RUN" ]]; then
    error "Baseline not found: $BASELINE_RUN"
fi

# Find current run
CURRENT_RUN="$ROOT_DIR/.run_${CASE}_${PLATFORM}_initial"
if [[ ! -d "$CURRENT_RUN" ]]; then
    error "Current run directory not found: $CURRENT_RUN"
fi

# Run comparison
OUTPUT_FILE="$COMPARE_DIR/${CASE}_${PLATFORM}_comparison.png"

info "Running comparison..."
echo

# Temporarily disable exit-on-error to capture comparison results
set +e
COMPARE_OUTPUT=$(python3 "$SCRIPT_DIR/compare_distributions.py" \
    "$BASELINE_RUN" \
    "$CURRENT_RUN" \
    -o "$OUTPUT_FILE" \
    -c "$CASE" 2>&1)
COMPARE_EXIT=$?
set -e

# Display output
echo "$COMPARE_OUTPUT"

# Parse errors from output (use N/A if parsing failed)
MEAN_ERROR=$(echo "$COMPARE_OUTPUT" | grep "mean_radius:" | awk '{print $2}')
STD_ERROR=$(echo "$COMPARE_OUTPUT" | grep "std_radius:" | awk '{print $2}')
MEAN_ERROR="${MEAN_ERROR:-N/A}"
STD_ERROR="${STD_ERROR:-N/A}"

echo
if [[ $COMPARE_EXIT -eq 0 ]]; then
    pass "Comparison successful: $CASE on $PLATFORM"
else
    fail "Comparison failed: $CASE on $PLATFORM"
fi

# Print results table
echo
info "======================================================================"
info "Results"
info "======================================================================"
echo
printf "%-40s %-15s %-15s %-10s\n" "Case" "Mean Error" "Std Error" "Status"
printf "%-40s %-15s %-15s %-10s\n" "----" "----------" "---------" "------"

if [[ $COMPARE_EXIT -eq 0 ]]; then
    STATUS_STR="${GREEN}PASS${NC}"
else
    STATUS_STR="${RED}FAIL${NC}"
fi
printf "%-40s %-15s %-15s %b\n" "$CASE" "$MEAN_ERROR" "$STD_ERROR" "$STATUS_STR"
echo

info "Comparison plot saved to: $OUTPUT_FILE"

if [[ $COMPARE_EXIT -ne 0 ]]; then
    exit 1
fi
