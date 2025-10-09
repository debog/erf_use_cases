#!/bin/bash

clear
rootdir=$PWD

if [[ "x$CASE" == "x" ]]; then
    echo "CASE not specified; running default..."
    CASE=BF02_moist_bubble_SDM_unimodal_NaCl
fi
echo "CASE is $CASE"

NPROC=108
NNODE=1
export OMP_NUM_THREADS=1

INP_FILE=$rootdir/inputs/inputs_${CASE}
outfile=out.${LCHOST}.log

ERF_EXEC_PATH=${ERF_BUILD}/Exec/MoistRegTests/Bubble
EXEC=$(ls ${ERF_EXEC_PATH}/erf_*)
echo "Executable file is ${EXEC}."

dirname=".run_${CASE}.${LCHOST}.$(printf "nproc%05d" $NPROC)"
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
srun -n $NPROC -p pdebug $EXEC $INP 2>&1 |tee $outfile
cd $rootdir
