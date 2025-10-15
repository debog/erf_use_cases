#!/bin/bash

clear
rootdir=$PWD

if [[ "x$CASE" == "x" ]]; then
    echo "CASE not specified; running default..."
    CASE=BF02_moist_bubble_SDM_unimodal_NaCl
fi
echo "CASE is $CASE"

ntasks=""
runcmd=""
if [[ "x$LCHOST" == "xdane" ]]; then
    ntasks=108
    nnodes=$(( (ntasks+56)/112 ))
    runcmd="srun -n $ntasks -N $nnodes -p pdebug"
elif [[ "x$LCHOST" == "xmatrix" ]]; then
    ntasks=4
    nnodes=$(( (ntasks+2)/4 ))
    runcmd="srun -p pdebug -n $ntasks -G $ntasks -N $nnodes"
elif [[ "x$LCHOST" == "xtuolumne" ]]; then
    ntasks=4
    nnodes=$(( (ntasks+2)/4 ))
    runcmd="flux run --exclusive --nodes=$nnodes --ntasks $ntasks -q=pdebug"
fi


export OMP_NUM_THREADS=1

INP_FILE=$rootdir/inputs/inputs_${CASE}
outfile=out.${LCHOST}.log

ERF_EXEC_PATH=${ERF_BUILD}/Exec/MoistRegTests/Bubble
EXEC=$(ls ${ERF_EXEC_PATH}/erf_*)
echo "Executable file is ${EXEC}."

dirname=".run_${CASE}.${LCHOST}.$(printf "nproc%05d" $ntasks)"
if [ -d "$dirname" ]; then
    echo "  deleting existing directory $dirname"
    rm -rf $dirname
fi
echo "  creating directory $dirname"
mkdir $dirname

cd $dirname
echo "  creating shortcut for input file"
ln -sf $INP_FILE .
INP=$(ls inputs_${CASE})
echo "  running ERF with input file $INP"
$runcmd $EXEC $INP 2>&1 |tee $outfile
cd $rootdir
