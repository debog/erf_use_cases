#!/bin/bash
#
# ERF comparison script
# Compares simulation results against benchmark data
#
# Usage:
#   ./plot_compare.sh [OPTIONS]
#
# Options:
#   -c, --case=NAMES      Case names to compare (can be specified multiple times, or comma-separated, e.g. -c c1_ppb_2_13_golovin -c c2_ppb_2_13_Halls)
#                          Supports wildcards (e.g. -c c1* for all C1 cases, -c *_2_13_* for all 2^13 cases) (default: all)
#   -k, --kernel=TYPE     Kernel type to compare (golovin, halls, longs, sedim) (default: all)
#   -f, --format=FORMAT   Output format (png, eps, pdf) (default: png)
#   -d, --directory=DIR   Output directory for comparison plots (default: ./plots/benchmark)
#   -a, --all             Compare all cases
#   --dry-run             Show what would be executed without running
#   -v, --verbose         Enable verbose output
#   -l, --list-cases      List available cases to compare
#   -h, --help            Show this help message
#
# Environment:
#   LCHOST            Platform identifier (auto-detected, or 'desktop' if unset)
#

set -e

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PLOTS_DIR="$ROOT_DIR/plots"
BASELINE_DIR="$ROOT_DIR/baselines"
DEFAULT_FORMAT="png"

# Import common functions
source "$SCRIPT_DIR/common_functions.sh"

# Script-specific settings
SCRIPT_NAME="plot_compare.sh"

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# Get kernels to compare
get_kernels() {
    local kernels=()

    # If specific cases are provided, extract all kernels from them
    if [[ -n "$CASE" && "$CASE" != "all" ]]; then
        # Split CASE by commas into an array
        IFS=',' read -ra case_array <<< "$CASE"

        for case_item in "${case_array[@]}"; do
            if [[ "$case_item" == *"golovin"* && ! " ${kernels[@]} " =~ " golovin " ]]; then
                kernels+=("golovin")
            elif [[ "$case_item" == *"Halls"* && ! " ${kernels[@]} " =~ " halls " ]]; then
                kernels+=("halls")
            elif [[ "$case_item" == *"Longs"* && ! " ${kernels[@]} " =~ " longs " ]]; then
                kernels+=("longs")
            elif [[ "$case_item" == *"sedim"* && ! " ${kernels[@]} " =~ " sedim " ]]; then
                kernels+=("sedim")
            fi
        done

        # If no kernels were extracted from cases, use the KERNEL parameter
        if [[ ${#kernels[@]} -eq 0 ]]; then
            if [[ -n "$KERNEL" && "$KERNEL" != "all" ]]; then
                echo "$KERNEL"
            else
                echo "golovin halls longs sedim"
            fi
            return
        fi

        # Output the unique kernels
        echo "${kernels[@]}"
    else
        # No specific case, use the kernel parameter
        if [[ -n "$KERNEL" && "$KERNEL" != "all" ]]; then
            echo "$KERNEL"
        else
            echo "golovin halls longs sedim"
        fi
    fi
}

# Get cases to compare
get_cases() {
    if [[ -n "$CASE" && "$CASE" != "all" ]]; then
        # Return the comma-separated case list as is
        echo "$CASE"
    else
        get_all_cases
    fi
}

# Generate and run a Python comparison script
run_benchmark_comparison() {
    local kernel="$1"
    local platform="$2"
    local output_dir="$3"
    local output_format="$4"
    local case_name="$5"

    # Create Python script path
    local script_path="$output_dir/benchmark_${kernel}_${platform}.py"

    # Generate Python script from template
    sed -e "s|{root_dir}|$ROOT_DIR|g" \
        -e "s|{baseline_dir}|$BASELINE_DIR|g" \
        -e "s|{platform}|$platform|g" \
        -e "s|{output_dir}|$output_dir|g" \
        -e "s|{output_format}|$output_format|g" \
        -e "s|{case_name}|$case_name|g" \
        -e "s|{kernel}|$kernel|g" \
        "$SCRIPT_DIR/plot_compare_template.py" > "$script_path"

    # Make script executable
    chmod +x "$script_path"

    if [[ -n "$DRY_RUN" ]]; then
        info "Would run: python $script_path"
        return 0
    fi

    info "Running Python to generate comparison plots with baseline"
    info "  Case: $case_name"
    info "  Kernel: $kernel"
    python "$script_path"
}

# Function to handle Python comparison with proper kernel capitalization
run_benchmark_with_kernel() {
    local kernel_name="$1"
    local platform="$2"
    local output_dir="$3"
    local output_format="$4"
    local case_name="$5"

    # Ensure proper case for kernel name
    local kernel_dir="$kernel_name"

    # Capitalize first letter for Halls and Longs
    if [[ "$kernel_name" == "halls" || "$kernel_name" == "longs" ]]; then
        kernel_dir="${kernel_name^}"  # Capitalize first letter
    fi

    # Debug output
    info "Running comparison with baseline:"
    info "  kernel: $kernel_name"
    info "  kernel_dir: $kernel_dir"
    info "  case: $case_name"
    info "  platform: $platform"

    # Silently check if both run and baseline directories exist
    run_dir="$ROOT_DIR/.run_${case_name}.${platform}.nproc00001"
    baseline_dir="$BASELINE_DIR/.run_${case_name}.${platform}.nproc00001"

    if [[ ! -d "$run_dir" ]]; then
        warn "Run directory not found: $run_dir"
        return
    fi

    if [[ ! -d "$baseline_dir" ]]; then
        warn "Baseline directory not found: $baseline_dir"
        return
    fi

    run_benchmark_comparison "$kernel_dir" "$platform" "$output_dir" "$output_format" "$case_name"
}

# =============================================================================
# Main
# =============================================================================

# Parse command line arguments
CASE=""
KERNEL=""
OUTPUT_FORMAT="$DEFAULT_FORMAT"
OUTPUT_DIR="$PLOTS_DIR"
DRY_RUN=""
VERBOSE=""
PLOT_ALL=""
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
                    CASE_ARRAY+=("$CASE")
                fi
                CASE="$1"
            else
                # Handle --case=VALUE format
                if [[ -n "$CASE" ]]; then
                    CASE_ARRAY+=("$CASE")
                fi
                CASE="${1#*=}"
            fi
            ;;
        -k|--kernel=*)
            [[ "$1" == -k ]] && { shift; KERNEL="$1"; } || KERNEL="${1#*=}" ;;
        -f|--format=*)
            [[ "$1" == -f ]] && { shift; OUTPUT_FORMAT="$1"; } || OUTPUT_FORMAT="${1#*=}" ;;
        -d|--directory=*)
            [[ "$1" == -d ]] && { shift; OUTPUT_DIR="$1"; } || OUTPUT_DIR="${1#*=}" ;;
        -a|--all)       PLOT_ALL=1 ;;
        --dry-run)      DRY_RUN=1 ;;
        -v|--verbose)   VERBOSE=1 ;;
        -l|--list-cases) list_cases; exit 0 ;;
        -h|--help)      usage ;;
        *)
            # Check if this might be a case name (not starting with -)
            if [[ "$1" != -* ]] && ( [[ "$1" == c1_* ]] || [[ "$1" == c2_* ]] || [[ "$1" == c3_* ]] ); then
                # It looks like a case name, add it to our list
                if [[ -n "$CASE" ]]; then
                    CASE_ARRAY+=("$CASE")
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
    CASE_ARRAY+=("$CASE")

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
if [[ -n "$PLOT_ALL" ]]; then
    CASE="all"
    KERNEL="all"
fi

# Auto-detect platform from LCHOST, default to 'desktop'
if [[ -z "$LCHOST" ]]; then
    PLATFORM="desktop"
    info "LCHOST not set, assuming desktop environment"
else
    PLATFORM="$LCHOST"
fi

# Ensure output directory exists
if [[ ! -d "$OUTPUT_DIR" ]]; then
    info "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# Get kernels and cases to compare
KERNELS=($(get_kernels))
CASES=($(get_cases))

info "Starting comparison with baseline"
info "  Platform:       $PLATFORM"
info "  Output format:  $OUTPUT_FORMAT"
info "  Output directory: $OUTPUT_DIR"
[[ -n "$DRY_RUN" ]] && info "  Dry run:        Yes"
echo

# Process each case individually
if [[ "$CASE" == "all" ]]; then
    # If all cases requested, get the full list
    case_list=($(get_all_cases))
elif [[ "$CASE" == *","* ]]; then
    # If comma-separated list, split into array
    IFS=',' read -ra case_list <<< "$CASE"
else
    # Single case
    case_list=("$CASE")
fi

for case_item in "${case_list[@]}"; do
    # Skip c3_ppb_2_21* cases as they take too long and don't finish within the max walltime limit
    if [[ "$case_item" == c3_ppb_2_21* ]]; then
        warn "Skipping $case_item (exceeds max walltime)"
        continue
    fi

    info "Processing case: $case_item"

    # Extract kernel from case name
    if [[ "$case_item" == *"golovin"* ]]; then
        kernel="golovin"
    elif [[ "$case_item" == *"Halls"* ]]; then
        kernel="halls"
    elif [[ "$case_item" == *"Longs"* ]]; then
        kernel="longs"
    elif [[ "$case_item" == *"sedim"* ]]; then
        kernel="sedim"
    else
        warn "Unknown kernel type in case: $case_item, skipping"
        continue
    fi

    # Run the benchmark comparison
    run_benchmark_with_kernel "$kernel" "$PLATFORM" "$OUTPUT_DIR" "$OUTPUT_FORMAT" "$case_item"

    echo
done

info "Done comparison with baseline"