#!/bin/bash
#SBATCH -J babofet
#SBATCH -p interactive
#SBATCH --ntasks-per-node=1
#SBATCH --mem=250GB 
#SBATCH -t 150:00:00
#SBATCH -N 1
#SBATCH -o ./logs2/%j.out
#SBATCH -e ./logs2/%j.err

mkdir -p ./logs2

SUBJECT_ID="$1"
SESSION_ID="$2"

bash ./00_run_pipeline.sh "${SUBJECT_ID}" "${SESSION_ID}"

