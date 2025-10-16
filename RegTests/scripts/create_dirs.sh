#!/bin/bash

clear
rootdir=$PWD
ntasks=4
outfile=out.$LCHOST.log

runcmd=""
if [[ "x$LCHOST" == "xdane" ]]; then
    runcmd="srun -n $ntasks -p pdebug"
elif [[ "x$LCHOST" == "xmatrix" ]]; then
    runcmd="srun -p pdebug -n $ntasks -G $ntasks -N 1"
elif [[ "x$LCHOST" == "xtuolumne" ]]; then
    runcmd="flux run --exclusive --nodes=1 --ntasks $ntasks -q=pdebug"
fi

write_run () {

# argument 1: filename
# argument 2: SDM case

arg=("$@")

/bin/cat <<EOM >${arg[1]}
#!/bin/bash

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

declare -a tests=("SDM_Box3D_Cond" \
                  "SDM_Box3D_Recycling" \
                  "SDM_Box3D_VTerm" \
                  "SDM_Bubble2D_Adv" \
                  "SDM_Bubble2D_Adv_InitSampling" \
                  "SDM_Congestus3D" \
                  "SDM_MultiSpecies_Bubble2D" \
                  "SDM_RICO3D" \
                  "SDM_RICO3D_InitSampling")

testdir_prefix=".test_$LCHOST"
rundir_prefix="run"
runscript="run.sh"
inpsoundfile="input_sounding"
runtests="run_sims.sh"
checktests="check_tests.sh"

for sdm in ${tests[@]}; do

    if [[ "$sdm" == "SDM_RICO3D"* ]]; then
        ERF_EXEC_PATH=${ERF_BUILD}/Exec/DevTests/RICO
    elif [[ "$sdm" == "SDM_MultiSpecies_Bubble2D"* ]]; then
        ERF_EXEC_PATH=${ERF_BUILD}/Exec/DevTests/MultiSpeciesBubble
    elif [[ "$sdm" == "SDM_Congestus3D"* ]]; then
        ERF_EXEC_PATH=${ERF_BUILD}/Exec/DevTests/TemperatureSourceSpatial
    else
        ERF_EXEC_PATH=${ERF_BUILD}/Exec/MoistRegTests/Bubble
    fi
    EXEC=$(ls ${ERF_EXEC_PATH}/erf_*)

    inp_dir="$testdir/$sdm"
    if [ -d "$inp_dir" ]; then
        inp_file=$inp_dir/$sdm.i
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
        echo "    creating symlink to $inp_file"
        ln -sf $inp_file .
        inpsound=$inp_dir/$inpsoundfile
        if [ -f "$inpsound" ]; then
            echo "    creating symlink to $inpsound"
            ln -sf $inpsound .
        fi
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
