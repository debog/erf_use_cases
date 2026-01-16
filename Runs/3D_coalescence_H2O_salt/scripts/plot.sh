#!/bin/bash
#
# ERF plotting script
# Generates plots for ERF simulation output
#
# Usage:
#   ./plot.sh [OPTIONS]
#
# Options:
#   -c, --case=NAMES      Case names to plot (can be specified multiple times, or comma-separated, e.g. -c c1_ppb_2_13_golovin -c c2_ppb_2_13_Halls) (default: all)
#   -k, --kernel=TYPE     Kernel type to plot (golovin, halls, longs, sedim) (default: all)
#   -f, --format=FORMAT   Output format (png, eps, pdf) (default: png)
#   -d, --directory=DIR   Output directory for plots (default: ./plots)
#   -o, --engine=ENGINE   Plotting engine to use (python or gnuplot) (default: python)
#   -a, --all             Plot all cases
#   -m, --mode=MODE       Plot mode: display (default) or save
#   --dry-run             Show what would be executed without running
#   -v, --verbose         Enable verbose output
#   -l, --list-cases      List available cases to plot
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
DEFAULT_FORMAT="png"

# Import common functions
source "$SCRIPT_DIR/common_functions.sh"

# Script-specific settings
SCRIPT_NAME="plot.sh"

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# Get kernels to plot
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

# Get cases to plot
get_cases() {
    if [[ -n "$CASE" && "$CASE" != "all" ]]; then
        # Return the comma-separated case list as is
        echo "$CASE"
    else
        get_all_cases
    fi
}

# Create gnuplot script for a specific kernel and platform
generate_plot_script() {
    local kernel="$1"
    local platform="$2"
    local output_dir="$3"
    local format="$4"
    local case_name="$5"
    local plot_script="$output_dir/plot_${kernel}_${platform}.p"
    local terminal_type="postscript enhanced eps color \"Times\" 14"
    local file_extension="eps"

    # Determine terminal type and file extension based on format
    case "$format" in
        png)
            terminal_type="pngcairo enhanced font \"Times,14\" size 800,600"
            file_extension="png"
            ;;
        pdf)
            terminal_type="pdfcairo enhanced color font \"Times,14\" size 8,6"
            file_extension="pdf"
            ;;
        eps|*)
            terminal_type="postscript enhanced eps color \"Times\" 14"
            file_extension="eps"
            ;;
    esac

    # Convert kernel name to title case for the plot title
    local kernel_title="${kernel^}"

    # Create plot script
    cat > "$plot_script" << EOF
set terminal $terminal_type

set style line 11 dt 2 lw 2 lc rgbcolor "black"        pt 4 ps 1
set style line 12 dt 2 lw 2 lc rgbcolor "red"          pt 6 ps 1
set style line 13 dt 2 lw 2 lc rgbcolor "blue"         pt 8 ps 1
set style line 14 dt 2 lw 2 lc rgbcolor "dark-green"   pt 4 ps 1
set style line 15 dt 2 lw 2 lc rgbcolor "orange"       pt 6 ps 1
set style line 16 dt 2 lw 2 lc rgbcolor "skyblue"      pt 8 ps 1

set style line 21 dt 4 lw 1 lc rgbcolor "black"        pt 6 ps 0.5
set style line 22 dt 4 lw 1 lc rgbcolor "red"          pt 6 ps 0.5
set style line 23 dt 4 lw 1 lc rgbcolor "blue"         pt 6 ps 0.5
set style line 24 dt 4 lw 1 lc rgbcolor "dark-green"   pt 6 ps 0.5
set style line 25 dt 4 lw 1 lc rgbcolor "orange"       pt 6 ps 0.5
set style line 26 dt 4 lw 1 lc rgbcolor "skyblue"      pt 6 ps 0.5

set format x "%1g"
set format y "%1.1f"

set key width 0

set grid  xtics lw 1 dt 4 lc rgbcolor "gray"
set grid  ytics lw 1 dt 4 lc rgbcolor "gray"
set grid mxtics lw 1 dt 4 lc rgbcolor "gray"
set grid mytics lw 1 dt 4 lc rgbcolor "gray"

set logscale x
set xrange [10:5000]
set yrange [0:1.8]

set xlabel "Radius R (mu-m)" font "Times,20"
set ylabel "Mass density distribution g(ln R) (gm/m^3/unit ln R)" font "Times,16"
EOF

    # Add plot commands based on kernel type
    case "$kernel" in
        golovin)
            # This is for C1 cases
            cat >> "$plot_script" << EOF

set output "${kernel_title}.${platform}.${file_extension}"
set title "${kernel_title} kernel"
set key top right
plot \\
EOF

            # For C1 cases, we plot at t=0, 1200, 2400, 3600

            # Check if we need to filter to specific cases
            if [[ -n "$case_name" && "$case_name" != "all" ]]; then
                # Split case_name by commas into an array
                IFS=',' read -ra case_array <<< "$case_name"

                # Check if c1_ppb_2_13_golovin is in the list
                if [[ " ${case_array[*]} " =~ " c1_ppb_2_13_golovin " ]]; then
                    # Plot 2^13 case
                    cat >> "$plot_script" << EOF
'$ROOT_DIR/.run_c1_ppb_2_13_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 11 t "t =    0 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c1_ppb_2_13_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 12 t "t = 1200 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c1_ppb_2_13_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_48000.txt' u (\$1*1e6):(\$2*1000) w l ls 13 t "t = 2400 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c1_ppb_2_13_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_72000.txt' u (\$1*1e6):(\$2*1000) w l ls 14 t "t = 3600 s, N_s = 2^{13}", \\
EOF
                fi

                # Check if c1_ppb_2_17_golovin is in the list
                if [[ " ${case_array[*]} " =~ " c1_ppb_2_17_golovin " ]]; then
                    # Plot 2^17 case
                    cat >> "$plot_script" << EOF
'$ROOT_DIR/.run_c1_ppb_2_17_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 21 t "t =    0 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c1_ppb_2_17_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 22 t "t = 1200 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c1_ppb_2_17_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_48000.txt' u (\$1*1e6):(\$2*1000) w l ls 23 t "t = 2400 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c1_ppb_2_17_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_72000.txt' u (\$1*1e6):(\$2*1000) w l ls 24 t "t = 3600 s, N_s = 2^{17}", \\
EOF
                fi

                # If no specific C1 case matched, but at least one case is C1_*_golovin, plot both
                if [[ ! " ${case_array[*]} " =~ " c1_ppb_2_13_golovin " && ! " ${case_array[*]} " =~ " c1_ppb_2_17_golovin " ]]; then
                    # No C1 golovin cases in the list, skip plotting
                    return
                fi
            else
                # Plot both 2^13 and 2^17 cases
                cat >> "$plot_script" << EOF
'$ROOT_DIR/.run_c1_ppb_2_13_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 11 t "t =    0 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c1_ppb_2_13_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 12 t "t = 1200 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c1_ppb_2_13_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_48000.txt' u (\$1*1e6):(\$2*1000) w l ls 13 t "t = 2400 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c1_ppb_2_13_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_72000.txt' u (\$1*1e6):(\$2*1000) w l ls 14 t "t = 3600 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c1_ppb_2_17_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 21 t "t =    0 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c1_ppb_2_17_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 22 t "t = 1200 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c1_ppb_2_17_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_48000.txt' u (\$1*1e6):(\$2*1000) w l ls 23 t "t = 2400 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c1_ppb_2_17_${kernel}.${platform}.nproc00001/super_droplets_moisture_g_lnR_72000.txt' u (\$1*1e6):(\$2*1000) w l ls 24 t "t = 3600 s, N_s = 2^{17}", \\
EOF
            fi
            ;;

        halls|longs|sedim)
            # This is for C2 cases
            cat >> "$plot_script" << EOF

set output "${kernel_title}.${platform}.${file_extension}"
set title "${kernel_title} kernel"
set key top right
plot \\
EOF

            # For C2 cases, we plot at t=0, 600, 1200, 1800

            # Check if we need to filter to specific cases
            if [[ -n "$case_name" && "$case_name" != "all" ]]; then
                # Split case_name by commas into an array
                IFS=',' read -ra case_array <<< "$case_name"

                # Check if c2_ppb_2_13_${kernel} is in the list
                if [[ " ${case_array[*]} " =~ " c2_ppb_2_13_${kernel} " ]]; then
                    # Plot 2^13 case
                    # Use proper case for kernel name in directory path
                    local kernel_dir="$kernel"
                    # Capitalize first letter for Halls and Longs
                    if [[ "$kernel" == "halls" || "$kernel" == "longs" ]]; then
                        kernel_dir="${kernel^}"  # Capitalize first letter
                    fi
                    cat >> "$plot_script" << EOF
'$ROOT_DIR/.run_c2_ppb_2_13_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 11 t "t =    0 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c2_ppb_2_13_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_12000.txt' u (\$1*1e6):(\$2*1000) w l ls 12 t "t =  600 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c2_ppb_2_13_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 13 t "t = 1200 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c2_ppb_2_13_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_36000.txt' u (\$1*1e6):(\$2*1000) w l ls 14 t "t = 1800 s, N_s = 2^{13}", \\
EOF
                fi

                # Check if c2_ppb_2_17_${kernel} is in the list
                if [[ " ${case_array[*]} " =~ " c2_ppb_2_17_${kernel} " ]]; then
                    # Plot 2^17 case
                    # Use proper case for kernel name in directory path
                    local kernel_dir="$kernel"
                    # Capitalize first letter for Halls and Longs
                    if [[ "$kernel" == "halls" || "$kernel" == "longs" ]]; then
                        kernel_dir="${kernel^}"  # Capitalize first letter
                    fi
                    cat >> "$plot_script" << EOF
'$ROOT_DIR/.run_c2_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 21 t "t =    0 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c2_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_12000.txt' u (\$1*1e6):(\$2*1000) w l ls 22 t "t =  600 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c2_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 23 t "t = 1200 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c2_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_36000.txt' u (\$1*1e6):(\$2*1000) w l ls 24 t "t = 1800 s, N_s = 2^{17}", \\
EOF
                fi

                # If no specific C2 case for this kernel matched, skip this kernel
                if [[ ! " ${case_array[*]} " =~ " c2_ppb_2_13_${kernel} " && ! " ${case_array[*]} " =~ " c2_ppb_2_17_${kernel} " ]]; then
                    # No C2 cases with this kernel in the list, skip plotting
                    return
                fi
            else
                # Plot both 2^13 and 2^17 cases
                # Use proper case for kernel name in directory path
                local kernel_dir="$kernel"
                # Capitalize first letter for Halls and Longs
                if [[ "$kernel" == "halls" || "$kernel" == "longs" ]]; then
                    kernel_dir="${kernel^}"  # Capitalize first letter
                fi
                cat >> "$plot_script" << EOF
'$ROOT_DIR/.run_c2_ppb_2_13_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 11 t "t =    0 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c2_ppb_2_13_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_12000.txt' u (\$1*1e6):(\$2*1000) w l ls 12 t "t =  600 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c2_ppb_2_13_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 13 t "t = 1200 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c2_ppb_2_13_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_36000.txt' u (\$1*1e6):(\$2*1000) w l ls 14 t "t = 1800 s, N_s = 2^{13}", \\
'$ROOT_DIR/.run_c2_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 21 t "t =    0 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c2_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_12000.txt' u (\$1*1e6):(\$2*1000) w l ls 22 t "t =  600 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c2_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 23 t "t = 1200 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c2_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_36000.txt' u (\$1*1e6):(\$2*1000) w l ls 24 t "t = 1800 s, N_s = 2^{17}", \\
EOF
            fi

            # Only add C3 plots for Halls and Longs kernels (not sedim)
            if [[ "$kernel" == "halls" || "$kernel" == "longs" ]]; then
                cat >> "$plot_script" << EOF

set xrange [2:5000]
set yrange [0:1.8]

set output "${kernel_title}.c3.${platform}.${file_extension}"
set title "${kernel_title} kernel"
set key top right
plot \\
EOF
                # For C3 cases, we plot at t=0, 1200, 2400, 3600

                # Check if we need to filter to specific cases
                if [[ -n "$case_name" && "$case_name" != "all" ]]; then
                    # Split case_name by commas into an array
                    IFS=',' read -ra case_array <<< "$case_name"

                    # Check if c3_ppb_2_17_${kernel} is in the list
                    if [[ " ${case_array[*]} " =~ " c3_ppb_2_17_${kernel} " ]]; then
                        # Plot 2^17 case
                        # Use proper case for kernel name in directory path
                        local kernel_dir="$kernel"
                        # Capitalize first letter for Halls and Longs
                        if [[ "$kernel" == "halls" || "$kernel" == "longs" ]]; then
                            kernel_dir="${kernel^}"  # Capitalize first letter
                        fi
                        cat >> "$plot_script" << EOF
'$ROOT_DIR/.run_c3_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 11 t "t =    0 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c3_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 12 t "t = 1200 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c3_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_48000.txt' u (\$1*1e6):(\$2*1000) w l ls 13 t "t = 2400 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c3_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_72000.txt' u (\$1*1e6):(\$2*1000) w l ls 14 t "t = 3600 s, N_s = 2^{17}", \\
EOF
                    fi

                    # Check if c3_ppb_2_21_${kernel} is in the list
                    if [[ " ${case_array[*]} " =~ " c3_ppb_2_21_${kernel} " ]]; then
                        # Plot 2^21 case
                        # Use proper case for kernel name in directory path
                        local kernel_dir="$kernel"
                        # Capitalize first letter for Halls and Longs
                        if [[ "$kernel" == "halls" || "$kernel" == "longs" ]]; then
                            kernel_dir="${kernel^}"  # Capitalize first letter
                        fi
                        cat >> "$plot_script" << EOF
'$ROOT_DIR/.run_c3_ppb_2_21_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 21 t "t =    0 s, N_s = 2^{21}", \\
'$ROOT_DIR/.run_c3_ppb_2_21_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 22 t "t = 1200 s, N_s = 2^{21}", \\
'$ROOT_DIR/.run_c3_ppb_2_21_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_48000.txt' u (\$1*1e6):(\$2*1000) w l ls 23 t "t = 2400 s, N_s = 2^{21}", \\
'$ROOT_DIR/.run_c3_ppb_2_21_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_72000.txt' u (\$1*1e6):(\$2*1000) w l ls 24 t "t = 3600 s, N_s = 2^{21}", \\
EOF
                    fi

                    # If no specific C3 case for this kernel matched, skip this kernel
                    if [[ ! " ${case_array[*]} " =~ " c3_ppb_2_17_${kernel} " && ! " ${case_array[*]} " =~ " c3_ppb_2_21_${kernel} " ]]; then
                        # No C3 cases with this kernel in the list, skip plotting
                        return
                    fi
                else
                    # Plot both 2^17 and 2^21 cases
                    # Use proper case for kernel name in directory path
                    local kernel_dir="$kernel"
                    # Capitalize first letter for Halls and Longs
                    if [[ "$kernel" == "halls" || "$kernel" == "longs" ]]; then
                        kernel_dir="${kernel^}"  # Capitalize first letter
                    fi
                    cat >> "$plot_script" << EOF
'$ROOT_DIR/.run_c3_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 11 t "t =    0 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c3_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 12 t "t = 1200 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c3_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_48000.txt' u (\$1*1e6):(\$2*1000) w l ls 13 t "t = 2400 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c3_ppb_2_17_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_72000.txt' u (\$1*1e6):(\$2*1000) w l ls 14 t "t = 3600 s, N_s = 2^{17}", \\
'$ROOT_DIR/.run_c3_ppb_2_21_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_00000.txt' u (\$1*1e6):(\$2*1000) w l ls 21 t "t =    0 s, N_s = 2^{21}", \\
'$ROOT_DIR/.run_c3_ppb_2_21_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_24000.txt' u (\$1*1e6):(\$2*1000) w l ls 22 t "t = 1200 s, N_s = 2^{21}", \\
'$ROOT_DIR/.run_c3_ppb_2_21_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_48000.txt' u (\$1*1e6):(\$2*1000) w l ls 23 t "t = 2400 s, N_s = 2^{21}", \\
'$ROOT_DIR/.run_c3_ppb_2_21_${kernel_dir}.${platform}.nproc00001/super_droplets_moisture_g_lnR_72000.txt' u (\$1*1e6):(\$2*1000) w l ls 24 t "t = 3600 s, N_s = 2^{21}", \\
EOF
                fi
            fi
            ;;
    esac

    echo "$plot_script"
}

# Run gnuplot for a specific script
run_gnuplot() {
    local script="$1"
    local mode="$2"

    if [[ -n "$DRY_RUN" ]]; then
        info "Would run: gnuplot \"$script\""
        return 0
    fi

    if [[ "$mode" == "display" ]]; then
        info "Running gnuplot with display"
        gnuplot -persist "$script"
    else
        info "Running gnuplot to generate plot files"
        gnuplot "$script"
    fi
}

# Generate and run a Python plotting script
run_python_plot() {
    local kernel="$1"
    local platform="$2"
    local output_dir="$3"
    local output_format="$4"
    local case_name="$5"

    # Create Python script path
    local script_path="$output_dir/plot_${kernel}_${platform}.py"

    # Generate Python script from template
    sed -e "s|{root_dir}|$ROOT_DIR|g" \
        -e "s|{platform}|$platform|g" \
        -e "s|{output_dir}|$output_dir|g" \
        -e "s|{output_format}|$output_format|g" \
        -e "s|{case_name}|$case_name|g" \
        -e "s|{kernel}|$kernel|g" \
        "$SCRIPT_DIR/plot_template.py" > "$script_path"

    # Make script executable
    chmod +x "$script_path"

    if [[ -n "$DRY_RUN" ]]; then
        info "Would run: python $script_path"
        return 0
    fi

    info "Running Python to generate plot files"
    info "  Case: $case_name"
    info "  Kernel: $kernel"
    python "$script_path"
}

# =============================================================================
# Main
# =============================================================================

# Parse command line arguments
CASE=""
KERNEL=""
OUTPUT_FORMAT="$DEFAULT_FORMAT"
OUTPUT_DIR="$ROOT_DIR/plots"
MODE="save"
PLOT_ENGINE="python"
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
        -o|--engine=*)
            [[ "$1" == -o ]] && { shift; PLOT_ENGINE="$1"; } || PLOT_ENGINE="${1#*=}" ;;
        -m|--mode=*)
            [[ "$1" == -m ]] && { shift; MODE="$1"; } || MODE="${1#*=}" ;;
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

# Get kernels and cases to plot
KERNELS=($(get_kernels))
CASES=($(get_cases))

info "Starting plot generation"
info "  Platform:       $PLATFORM"
info "  Output format:  $OUTPUT_FORMAT"
info "  Output directory: $OUTPUT_DIR"
info "  Plotting engine: $PLOT_ENGINE"
info "  Mode:           $MODE"
[[ -n "$DRY_RUN" ]] && info "  Dry run:        Yes"
echo

# Function to handle Python plotting with proper kernel capitalization
run_python_with_kernel() {
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
    info "Running Python plotting with:"
    info "  kernel: $kernel_name"
    info "  kernel_dir: $kernel_dir"
    info "  case: $case_name"
    info "  platform: $platform"

    # Silently check if run directories exist (no output)
    # Removed debug output that was listing all directories

    run_python_plot "$kernel_dir" "$platform" "$output_dir" "$output_format" "$case_name"
}

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

    # Choose plotting engine based on user selection
    if [[ "$PLOT_ENGINE" == "python" ]]; then
        # Use Python for plotting with proper case handling
        run_python_with_kernel "$kernel" "$PLATFORM" "$OUTPUT_DIR" "$OUTPUT_FORMAT" "$case_item"
    else
        # Default to gnuplot
        script=$(generate_plot_script "$kernel" "$PLATFORM" "$OUTPUT_DIR" "$OUTPUT_FORMAT" "$case_item")
        run_gnuplot "$script" "$MODE"
    fi

    echo
done

info "Done plotting"