#!/bin/bash
source config/config.sh


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

REF_STACK_FILE="${OUTPUT_DIR}/reference_stack.txt"
REFERENCE_STACK=$(cat "$REF_STACK_FILE")

# Input files
RECON_B0_IMG="${OUTPUT_DIR}/${SESSION_BASENAME}_b0_SVR.nii.gz"
RECON_B1000_IMG="${OUTPUT_DIR}/${SESSION_BASENAME}_b1000_SVR.nii.gz"
REF_STACK_IMG="${OUTPUT_DIR}/${REFERENCE_STACK}_final_b0_masked.nii.gz"

T2_DIR=$(dirname "${T2W_RECONSTRUCTED}")
T2_NAME=$(basename "${T2W_RECONSTRUCTED}")

# check if T2 without background exists, if not bet the T2 with bg and save it
if [[ ! -f "${T2W_RECONSTRUCTED}" ]]; then
    echo "T2 template without background not found. Extracting brain from T2 with background..."
    fslmaths "${T2W_RECONSTRUCTED_BG}" -mul "${T2W_RECONSTRUCTED_MASK}" "${T2W_RECONSTRUCTED}"
else
    echo "T2 template without background already exists. Skipping brain extraction."
fi

echo "--- Aligning all data to T2 template space ---"

# --- Step 1: Register SVR b0 to T2 Template ---
SVR_TO_T2_MAT="${OUTPUT_DIR}/${SESSION_BASENAME}_b0_SVR_to_T2.mat"
echo "Registering SVR b0 -> T2 Template"

# Use the local T2 template 
flirt -in "${RECON_B0_IMG}" \
      -ref "${T2W_RECONSTRUCTED}" \
      -out "${OUTPUT_DIR}/${SESSION_BASENAME}_b0_SVR_to_T2_registered.nii.gz" \
      -omat "${SVR_TO_T2_MAT}" \
      -searchrx -180 180 -searchry -180 180 -searchrz -180 180 \
      -cost mutualinfo \
      -dof 6

# --- Step 2: Compute Transform from Reference Stack to T2 Template ---
REF_STACK_TO_SVR_MAT="${OUTPUT_DIR}/${REFERENCE_STACK}_to_SVR.mat"
echo "Registering Reference Stack -> SVR b1000"
flirt -in "${REF_STACK_IMG}" \
      -ref "${RECON_B0_IMG}" \
      -out "${OUTPUT_DIR}/${REFERENCE_STACK}_to_SVR_registered.nii.gz" \
      -omat "${REF_STACK_TO_SVR_MAT}" \
      -searchrx -180 180 -searchry -180 180 -searchrz -180 180 \
      -dof 6


REF_STACK_TO_T2_MAT="${OUTPUT_DIR}/${REFERENCE_STACK}_to_T2.mat"
echo "Concatenating transforms to get Reference Stack -> T2"
convert_xfm \
    -omat "${REF_STACK_TO_T2_MAT}" \
    -concat "${SVR_TO_T2_MAT}" "${REF_STACK_TO_SVR_MAT}"

# --- Step 3: Compute Transform from ALL Stacks to T2 Template ---
echo "Calculating final transforms for all stacks to T2 space..."

# Look in OUTPUT_DIR for successfully preprocessed b1000 files
detected_stacks=( $(ls "${OUTPUT_DIR}"/${SUBJECT_ID}_${SESSION_ID}_*run-*_final_b1000.nii.gz 2>/dev/null | sort) )

for file_path in "${detected_stacks[@]}"; do
    filename=$(basename "$file_path" .nii.gz)          # e.g., sub-01_ses-01_dir-AP_run-01_final_b1000
    basename=${filename%_final_b1000}                  # e.g., sub-01_ses-01_dir-AP_run-01
    
    STACK_IMG="${OUTPUT_DIR}/${basename}_final_b1000.nii.gz"
    STACK_TO_T2_MAT="${OUTPUT_DIR}/${basename}_to_T2.mat"
    STACK_TO_T2_DOF="${OUTPUT_DIR}/${basename}_to_T2.dof"
    
    if [[ "${basename}" == "${REFERENCE_STACK}" ]]; then
        echo "Processing reference stack: ${basename} (transform already exists)"
    else
        echo "Processing moving stack: ${basename}"
        STACK_TO_REF_MAT="${OUTPUT_DIR}/${basename}_to_${REFERENCE_STACK}.mat"
        convert_xfm -omat "${STACK_TO_T2_MAT}" -concat "${REF_STACK_TO_T2_MAT}" "${STACK_TO_REF_MAT}"
    fi

    # Convert the final .mat file to a .dof file for mirtk.
    singularity run \
        --pwd "/shared" \
        --bind "${OUTPUT_DIR}":/shared \
        --bind "${T2_DIR}":/t2_ref \
        "${mirtk_path}" \
        convert-dof \
        "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${STACK_TO_T2_MAT}")" \
        "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${STACK_TO_T2_DOF}")" \
        -input-format flirt -output-format mirtk_affine \
        -source "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${STACK_IMG}")" \
        -target "/t2_ref/${T2_NAME}"
done

echo "--- Alignment to T2 space complete. ---"