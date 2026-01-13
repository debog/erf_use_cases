#!/bin/bash

set -e

# Check required environment variables
if [[ -z "$ERF_HOME" ]]; then
    echo "Error: ERF_HOME is not set" >&2
    exit 1
fi
if [[ -z "$ERF_BUILD" ]]; then
    echo "Error: ERF_BUILD is not set" >&2
    exit 1
fi

if [[ -z $LCHOST ]]; then
  LCHOST=$HOSTNAME
fi

clear
rootdir=$PWD
ntasks=4
outfile=out.$LCHOST.log

# Associative array for executable mapping (pattern -> relative path)
declare -A exec_map=(
    ["RICO"]="Exec/DevTests/RICO"
    ["MultiSpecies"]="Exec/DevTests/MultiSpeciesBubble"
    ["Congestus"]="Exec/DevTests/TemperatureSourceSpatial"
)
DEFAULT_EXEC_PATH="Exec/MoistRegTests/Bubble"

# Function to get executable path for a given SDM test
get_exec_path() {
    local sdm=$1
    for key in "${!exec_map[@]}"; do
        if [[ "$sdm" == *"$key"* ]]; then
            echo "${ERF_BUILD}/${exec_map[$key]}"
            return
        fi
    done
    echo "${ERF_BUILD}/${DEFAULT_EXEC_PATH}"
}

runcmd=""
if [[ "x$LCHOST" == "xdane" ]]; then
    runcmd="srun -n $ntasks -p pdebug"
elif [[ "x$LCHOST" == "xmatrix" ]]; then
    runcmd="srun -p pdebug -n $ntasks -G $ntasks -N 1"
elif [[ "x$LCHOST" == "xtuolumne" ]]; then
    runcmd="flux run --exclusive --nodes=1 --ntasks $ntasks -q=pdebug"
else
    runcmd="mpirun -n $ntasks"
fi

write_run () {

# argument 1: filename
# argument 2: SDM case

arg=("$@")

/bin/cat <<EOM >${arg[1]}
#!/bin/bash

rm -rf plt* *.txt Backtrace* *core*
$runcmd $EXEC ${arg[2]}.i 2>&1 |tee $outfile
EOM
}

write_run_tests () {

# argument 1: run tests filename
# argument 2: check tests filename

arg=("$@")

/bin/cat <<EOM >${arg[1]}
#!/bin/bash

cd $rundir && bash ./$runscript && cd ..
cd $rundir_copy && bash ./$runscript && cd ..
EOM

/bin/cat <<EOM >${arg[2]}
#!/bin/bash

echo "amrex_fcompare is \$AMREX_FCOMPARE"
cd $rundir
for i in plt*; do
    echo "  comparing \$i"
    $runcmd \$AMREX_FCOMPARE \$i ../$rundir_copy/\$i
done
cd ..

echo "amrex_pcompare is \$AMREX_PCOMPARE"
cd $rundir
for i in plt*; do
    echo "  comparing \$i"
    $runcmd \$AMREX_PCOMPARE \$i ../$rundir_copy/\$i super_droplets_moisture
done
cd ..
EOM
}

echo "LC host is $LCHOST"
echo "ERF directory is $ERF_HOME."
echo ""
testdir="$ERF_HOME/Tests/test_files"

# Dynamically discover SDM tests from ERF test_files directory
declare -a tests=()
for dir in "$testdir"/SDM_*/; do
    if [ -d "$dir" ]; then
        tests+=("$(basename "$dir")")
    fi
done

echo "Found ${#tests[@]} SDM tests: ${tests[*]}"
echo ""

testdir_prefix=".test_$LCHOST"
rundir_prefix="run"
runscript="run.sh"
runtests="run_sims.sh"
checktests="check_tests.sh"

for sdm in ${tests[@]}; do

    ERF_EXEC_PATH=$(get_exec_path "$sdm")
    EXEC=$(ls ${ERF_EXEC_PATH}/erf_* 2>/dev/null || true)

    # Validate executable exists
    if [[ -z "$EXEC" || ! -x "$EXEC" ]]; then
        echo "Warning: No executable found in ${ERF_EXEC_PATH} for $sdm; skipping..."
        continue
    fi

    inp_dir="$testdir/$sdm"
    if [ -d "$inp_dir" ]; then
        echo "Executable file is ${EXEC}."
        echo "Creating run directories for $sdm."
        dirname="${testdir_prefix}.$sdm"
        if [ -d "$dirname" ]; then
            echo "  deleting existing directory $dirname."
            rm -rf $dirname
        fi
        mkdir $dirname

        echo "  entering $dirname"
        cd $dirname
        rundir="${rundir_prefix}1"
        echo "  creating $rundir"
        mkdir $rundir
        echo "    entering $rundir"
        cd $rundir
        echo "    creating symlinks to all input files"
        for f in "$inp_dir"/*; do
            if [ -f "$f" ]; then
                ln -sf "$f" .
            fi
        done
        echo "    writing run script $runscript"
        write_run $# $runscript $sdm
        cd ..
        rundir_copy="${rundir_prefix}2"
        echo "  creating copy $rundir_copy"
        cp -r $rundir $rundir_copy
        echo "writing run and check scripts"
        write_run_tests $# $runtests $checktests
        echo "  done"
        echo ""
        cd ..
    else
        echo "$sdm doesn't exist in $testdir; skipping..."
    fi
done
