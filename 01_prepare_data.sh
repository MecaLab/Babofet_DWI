#!/bin/bash
set -e -u -o pipefail

# ==============================================================================
# STEP 1: PREPARE, ORGANIZE, AND EQUALIZE BIDS DATA
# ==============================================================================
#
# This script performs two main functions:
# 1. Copies raw DWI data (.nii.gz, .bval, .bvec, .json) into a clean
#    derivatives structure.
#
# ==============================================================================

# --- Directory and Script Setup ---
RAW_DWI_DIR="${BIDS_ROOT_DIR}/sub-${SUBJECT_ID}/sub-${SUBJECT_ID}_${SESSION_ID}/dwi"
PREPARED_DIR="${DERIVATIVES_DIR}/01_prepared_stacks"

# --- Step 1.1: Copy and Organize Raw Data ---
echo "================================================="
echo "STEP 1.1: COPYING RAW DATA"
echo "================================================="

# Clean up previous runs and create directories
rm -rf "${PREPARED_DIR}"
mkdir -p "${PREPARED_DIR}"

echo "Searching for DWI scans in: ${RAW_DWI_DIR}"
echo "Copying and organizing into: ${PREPARED_DIR}"

# Find all dwi.nii.gz files and loop through them
find "${RAW_DWI_DIR}" -type f -name "*_dwi.nii.gz" | while read -r nifti_file; do
    # Extract the base name without the extension
    base_name=$(basename "${nifti_file}" .nii.gz)

    # Extract the acquisition and run identifier (e.g., acq-ax_run-1)
    acq_id=$(echo "${base_name}" | sed -n 's/.*\(acq-[^_]*_run-[0-9]*\).*/\1/p')

    if [[ -z "${acq_id}" ]]; then
        echo "WARNING: Could not determine acq_id for ${base_name}. Skipping."
        continue
    fi

    echo "Found acquisition: ${acq_id}"

    # Create a dedicated directory for this acquisition
    out_acq_dir="${PREPARED_DIR}/${acq_id}"
    mkdir -p "${out_acq_dir}"

    # Copy all associated files
    cp "${RAW_DWI_DIR}/${base_name}.nii.gz" "${out_acq_dir}/dwi.nii.gz"
    cp "${RAW_DWI_DIR}/${base_name}.bval"   "${out_acq_dir}/dwi.bval"
    cp "${RAW_DWI_DIR}/${base_name}.bvec"   "${out_acq_dir}/dwi.bvec"
    cp "${RAW_DWI_DIR}/${base_name}.json"   "${out_acq_dir}/dwi.json"
done

echo "Data copying finished. Found $(ls -1 "${PREPARED_DIR}" | wc -l) acquisitions."
