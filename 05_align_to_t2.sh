#!/bin/bash
set -e -u -o pipefail

# ==============================================================================
# STEP 5: ALIGN RECONSTRUCTED VOLUMES TO T2 TEMPLATE
# ==============================================================================
#
# The final DWI reconstruction will happen in a high-resolution anatomical
# space (T2 template). This script computes all the necessary transforms.
#
# A local copy of the T2 template is made in the output directory to keep
# this step self-contained.
#
# ==============================================================================

# --- Configuration ---
PREPROC_DIR="${DERIVATIVES_DIR}/02_preprocessed_stacks"
REG_DIR="${DERIVATIVES_DIR}/03_registration"
SVR_DIR="${DERIVATIVES_DIR}/04_svr_reconstruction"
ALIGN_DIR="${DERIVATIVES_DIR}/05_alignment_to_t2"

REF_STACK_FILE="${DERIVATIVES_DIR}/reference_stack.txt"
REFERENCE_STACK=$(cat "$REF_STACK_FILE")

# Input files
RECON_B0_IMG="${SVR_DIR}/b0_SVR.nii.gz"
RECON_B1000_IMG="${SVR_DIR}/b1000_SVR.nii.gz"
REF_STACK_IMG="${PREPROC_DIR}/${REFERENCE_STACK}/final_b0_masked.nii.gz"

# Define a path for the local copy of the T2 template 
# This makes the alignment directory self-contained.
LOCAL_T2_TEMPLATE="${ALIGN_DIR}/T2_template_local_copy.nii.gz"

mkdir -p "${ALIGN_DIR}"
echo "--- Aligning all data to T2 template space ---"

# Copy the T2 template into the alignment directory 
echo "Copying T2 template to local alignment directory..."
cp -vn "${T2_TEMPLATE_IMAGE}" "${LOCAL_T2_TEMPLATE}"

# --- Step 1: Register SVR b0 to T2 Template ---
SVR_TO_T2_MAT="${ALIGN_DIR}/b0_SVR_to_T2.mat"
echo "Registering SVR b0 -> T2 Template"

# Use the local T2 template 
flirt -in "${RECON_B0_IMG}" \
      -ref "${LOCAL_T2_TEMPLATE}" \
      -out "${ALIGN_DIR}/b0_SVR_to_T2_registered.nii.gz" \
      -omat "${SVR_TO_T2_MAT}" \
      -searchrx -180 180 -searchry -180 180 -searchrz -180 180 \
      -cost mutualinfo \
      -dof 6

# --- Step 2: Compute Transform from Reference Stack to T2 Template ---
REF_STACK_TO_SVR_MAT="${ALIGN_DIR}/${REFERENCE_STACK}_to_SVR.mat"
echo "Registering Reference Stack -> SVR b1000"
flirt -in "${REF_STACK_IMG}" \
      -ref "${RECON_B0_IMG}" \
      -out "${ALIGN_DIR}/${REFERENCE_STACK}_to_SVR_registered.nii.gz" \
      -omat "${REF_STACK_TO_SVR_MAT}" \
      -searchrx -180 180 -searchry -180 180 -searchrz -180 180 \
      -dof 6


REF_STACK_TO_T2_MAT="${ALIGN_DIR}/${REFERENCE_STACK}_to_T2.mat"
echo "Concatenating transforms to get Reference Stack -> T2"
convert_xfm -omat "${REF_STACK_TO_T2_MAT}" -concat "${SVR_TO_T2_MAT}" "${REF_STACK_TO_SVR_MAT}"

# --- Step 3: Compute Transform from ALL Stacks to T2 Template ---
echo "Calculating final transforms for all stacks to T2 space..."
ALIGN_DIR_RELATIVE=$(realpath --relative-to="${DERIVATIVES_DIR}" "${ALIGN_DIR}")

for acq_dir in "${PREPROC_DIR}"/*/; do
    ACQ_ID=$(basename "${acq_dir}")
    
    STACK_IMG="${PREPROC_DIR}/${ACQ_ID}/final_b1000.nii.gz"
    STACK_TO_T2_MAT="${ALIGN_DIR}/${ACQ_ID}_to_T2.mat"
    STACK_TO_T2_DOF="${ALIGN_DIR}/${ACQ_ID}_to_T2.dof"
    
    if [[ "${ACQ_ID}" == "${REFERENCE_STACK}" ]]; then
        echo "Processing reference stack: ${ACQ_ID} (transform already exists)"
    else
        echo "Processing moving stack: ${ACQ_ID}"
        STACK_TO_REF_MAT="${REG_DIR}/${ACQ_ID}_to_${REFERENCE_STACK}.mat"
        if [ ! -f "${STACK_TO_REF_MAT}" ]; then
            echo "FATAL: FSL transform not found at ${STACK_TO_REF_MAT}. Did a previous step fail?" >&2; exit 1
        fi
        convert_xfm -omat "${STACK_TO_T2_MAT}" -concat "${REF_STACK_TO_T2_MAT}" "${STACK_TO_REF_MAT}"
    fi

    # Convert the final .mat file to a .dof file for mirtk.
    singularity run \
        --pwd "/shared/${ALIGN_DIR_RELATIVE}" \
        --bind "${DERIVATIVES_DIR}":/shared \
        "${MIRTK_SIF_PATH}" \
        convert-dof \
        "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${STACK_TO_T2_MAT}")" \
        "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${STACK_TO_T2_DOF}")" \
        -input-format flirt -output-format mirtk_affine \
        -source "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${STACK_IMG}")" \
        -target "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${LOCAL_T2_TEMPLATE}")"

echo "--- Alignment to T2 space complete. ---"