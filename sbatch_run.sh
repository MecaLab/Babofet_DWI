#!/bin/bash
#SBATCH -J babofet
#SBATCH -p interactive
#SBATCH --ntasks-per-node=1
#SBATCH --mem=250GB 
#SBATCH -t 150:00:00
#SBATCH -N 1
#SBATCH -o ./logs/%j.out
#SBATCH -e ./logs/%j.err

mkdir -p ./logs

# Set subject and sessions
ALL_SUBJECTS=("sub-Aziza" "sub-Borgne" "sub-Bibi" "sub-Filoutte" "sub-Forme" "sub-Formule" "sub-Fabienne")
ALL_SESSIONS=("ses-01" "ses-02" "ses-03" "ses-04" "ses-05" "ses-06" "ses-07" "ses-08" "ses-09" "ses-10")

SPECIFIC_SUBJECTS=("sub-Prisme")
SPECIFIC_SESSIONS=("ses-06")

# Loop through sessions
for SUBJECT_ID in "${SPECIFIC_SUBJECTS[@]}"; do
    for SESSION_ID in "${SPECIFIC_SESSIONS[@]}"; do
        echo "Processing ${SUBJECT_ID} ${SESSION_ID}..."
        bash ./00_run_pipeline.sh "${SUBJECT_ID}" "${SESSION_ID}"
    done
done

