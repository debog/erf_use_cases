#!/bin/bash
#
# Common functions for ERF run scripts
#

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly" >&2
    exit 1
fi

# Directory setup (will be inherited from the sourcing script)
: "${SCRIPT_DIR:="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"}"
: "${ROOT_DIR:="$(dirname "$SCRIPT_DIR")"}"
: "${CONFIG_FILE:="$SCRIPT_DIR/platforms.conf"}"
: "${INPUTS_DIR:="$ROOT_DIR/inputs"}"
: "${OVERRIDE_DIR:="$ROOT_DIR/inputs/templates/overrides"}"

# Helper functions for text formatting and output
# These are defined as variables so they can be overridden by the sourcing script
: "${RED:='\033[0;31m'}"
: "${GREEN:='\033[0;32m'}"
: "${YELLOW:='\033[0;33m'}"
: "${BLUE:='\033[0;34m'}"
: "${CYAN:='\033[0;36m'}"
: "${NC:='\033[0m'}"

# Error, warning, and info functions (can be overridden by the sourcing script)
error() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
warn()  { echo -e "${YELLOW}WARNING:${NC} $*" >&2; }
info()  { echo -e "${GREEN}==>${NC} $*"; }
debug() { [[ -n "$VERBOSE" ]] && echo -e "${BLUE}DEBUG:${NC} $*" >&2 || true; }
prof()  { echo -e "${CYAN}[PROFILE]${NC} $*"; } # Used by profile_erf.sh

# Get all available cases as an array
get_all_cases() {
    echo "c1_ppb_2_13_golovin" "c1_ppb_2_17_golovin" \
         "c2_ppb_2_13_Halls" "c2_ppb_2_13_Longs" "c2_ppb_2_13_sedim" \
         "c2_ppb_2_17_Halls" "c2_ppb_2_17_Longs" "c2_ppb_2_17_sedim" \
         "c3_ppb_2_17_Halls" "c3_ppb_2_17_Longs" "c3_ppb_2_21_Halls" "c3_ppb_2_21_Longs"
}

# Get cases matching a pattern
# Returns a comma-separated list of cases matching the given pattern
match_cases() {
    local pattern="$1"
    local all_cases=($(get_all_cases))
    local matching_cases=()

    for case in "${all_cases[@]}"; do
        # Use bash pattern matching
        if [[ "$case" == $pattern ]]; then
            matching_cases+=("$case")
        fi
    done

    # Return the matching cases as comma-separated list
    if [[ ${#matching_cases[@]} -gt 0 ]]; then
        (IFS=,; echo "${matching_cases[*]}")
    fi
}

# List available input cases in a formatted way
list_cases() {
    echo "Available cases:"
    local all_cases=($(get_all_cases))

    # Display C1 cases - Golovin kernel
    echo "  C1 cases - Golovin kernel, 3600s:"
    for case in "${all_cases[@]}"; do
        if [[ "$case" == c1_* ]]; then
            echo "    $case"
        fi
    done

    # Display C2 cases - Other kernels, 1800s
    echo "  C2 cases - Various kernels, 1800s:"
    for case in "${all_cases[@]}"; do
        if [[ "$case" == c2_* ]]; then
            echo "    $case"
        fi
    done

    # Display C3 cases - Modified parameters
    echo "  C3 cases - Modified parameters, 3600s:"
    for case in "${all_cases[@]}"; do
        if [[ "$case" == c3_* ]]; then
            echo "    $case"
        fi
    done
}

# Get override files for a specific case
get_case_overrides() {
    local case_name="$1"
    local override_files=()

    # Base template is always used
    local base_template="$ROOT_DIR/inputs/templates/base.inputs"

    # Parse the case name to determine which overrides to use
    if [[ "$case_name" == c1_ppb_2_13_* ]]; then
        # C1: Golovin kernel, 3600s, 128 particles per cell
        override_files+=("$ROOT_DIR/inputs/templates/overrides/params_c1_ppb_2_13.conf")
        override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_golovin_kernel.conf")

    elif [[ "$case_name" == c1_ppb_2_17_* ]]; then
        # C1: Golovin kernel, 3600s, 2048 particles per cell
        override_files+=("$ROOT_DIR/inputs/templates/overrides/params_c1_ppb_2_17.conf")
        override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_golovin_kernel.conf")

    elif [[ "$case_name" == c2_ppb_2_13_* ]]; then
        # C2: Various kernels, 1800s, 128 particles per cell
        override_files+=("$ROOT_DIR/inputs/templates/overrides/params_c2_ppb_2_13.conf")

        # Add kernel-specific override
        if [[ "$case_name" == *_Halls ]]; then
            override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_halls_kernel.conf")
        elif [[ "$case_name" == *_Longs ]]; then
            override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_longs_kernel.conf")
        elif [[ "$case_name" == *_sedim ]]; then
            override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_sedimentation_kernel.conf")
        fi

    elif [[ "$case_name" == c2_ppb_2_17_* ]]; then
        # C2: Various kernels, 1800s, 2048 particles per cell
        override_files+=("$ROOT_DIR/inputs/templates/overrides/params_c2_ppb_2_17.conf")

        # Add kernel-specific override
        if [[ "$case_name" == *_Halls ]]; then
            override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_halls_kernel.conf")
        elif [[ "$case_name" == *_Longs ]]; then
            override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_longs_kernel.conf")
        elif [[ "$case_name" == *_sedim ]]; then
            override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_sedimentation_kernel.conf")
        fi

    elif [[ "$case_name" == c3_ppb_2_17_* ]]; then
        # C3: Modified parameters, 3600s
        override_files+=("$ROOT_DIR/inputs/templates/overrides/params_c3_ppb_2_17.conf")

        # Add kernel-specific override
        if [[ "$case_name" == *_Halls ]]; then
            override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_halls_kernel.conf")
        elif [[ "$case_name" == *_Longs ]]; then
            override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_longs_kernel.conf")
        fi

    elif [[ "$case_name" == c3_ppb_2_21_* ]]; then
        # C3: Modified parameters, 3600s, higher multiplicity
        override_files+=("$ROOT_DIR/inputs/templates/overrides/params_c3_ppb_2_21.conf")

        # Add kernel-specific override
        if [[ "$case_name" == *_Halls ]]; then
            override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_halls_kernel.conf")
        elif [[ "$case_name" == *_Longs ]]; then
            override_files+=("$ROOT_DIR/inputs/templates/overrides/sdm_longs_kernel.conf")
        fi
    fi

    # Return the base template and override files
    echo "$base_template" "${override_files[@]}"
}

# Merge input files: later files override earlier ones
# For AMReX inputs format: key = value
merge_inputs() {
    local output_file="$1"
    shift
    local files=("$@")
    local script_name="${SCRIPT_NAME:-script}"

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

                # No debug output for particles_per_cell
            fi
        done < "$file"
    done

    # Generate output with section comments
    {
        echo "# ------------------  INPUTS TO MAIN PROGRAM  -------------------"
        echo "# Generated by $script_name on $(date)"
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

        # Ensure particles_per_cell parameter is included
        if [[ ! " ${order[*]} " =~ " super_droplets_moisture.initial_particles_per_cell " ]]; then
            local case_name=$(basename "$output_file" | sed 's/inputs_//')
            if [[ "$case_name" == c*_ppb_2_13_* ]]; then
                echo "super_droplets_moisture.initial_particles_per_cell = 128"
            elif [[ "$case_name" == c*_ppb_2_17_* || "$case_name" == c*_ppb_2_21_* ]]; then
                echo "super_droplets_moisture.initial_particles_per_cell = 2048"
            fi
        fi
    } > "$output_file"
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

# List supported platforms from the config file
list_platforms() {
    echo "Available platforms:"
    grep '^\[' "$CONFIG_FILE" | tr -d '[]' | while read -r p; do
        local scheduler=$(get_config "$p" "scheduler")
        local gpu=$(get_config "$p" "gpu_support" "false")
        printf "  %-12s scheduler=%-6s gpu=%s\n" "$p" "$scheduler" "$gpu"
    done
}

# Common validation logic for both scripts
validate_case() {
    # Check if the case is valid
    local case_name="$1"

    # Special handling for "all" keyword
    if [[ "$case_name" == "all" ]]; then
        return 0
    fi

    # Check for comma-separated list of cases
    if [[ "$case_name" == *,* ]]; then
        # Split the comma-separated list into an array
        IFS=',' read -ra case_array <<< "$case_name"

        # Validate each case individually
        for individual_case in "${case_array[@]}"; do
            # Recursive call to validate each individual case
            validate_case "$individual_case"
        done
        return 0
    fi

    # Single case validation
    local all_cases=($(get_all_cases))
    local valid_case=0

    for valid_case_name in "${all_cases[@]}"; do
        if [[ "$case_name" == "$valid_case_name" ]]; then
            valid_case=1
            break
        fi
    done

    if [[ "$valid_case" -eq 0 ]]; then
        error "Invalid case name: $case_name
       Use --list-cases to see available cases."
    fi
}

# Display usage information from script header comments
usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# Generate input file in working directory
generate_input_file() {
    local case_name="$1"
    local working_dir="$2"
    local script_name="$3"

    # Get the input files for the case and generate the input file in the run directory
    local input_files=($(get_case_overrides "$case_name"))
    if [[ ${#input_files[@]} -eq 0 ]]; then
        error "Failed to determine input files for case: $case_name"
    fi

    local log_func="info"
    [[ "$script_name" == "profile_erf.sh" ]] && log_func="prof"

    # Redirecting log messages to stderr to avoid them being captured in command substitution
    $log_func "Generating input file for case: $case_name" >&2
    debug "Base: ${input_files[0]}" >&2
    debug "Overrides: ${input_files[@]:1}" >&2

    local inp="inputs_${case_name}"
    SCRIPT_NAME="$script_name" merge_inputs "$working_dir/$inp" "${input_files[@]}"

    # Return the full path to the input file
    echo "$working_dir/$inp"
}