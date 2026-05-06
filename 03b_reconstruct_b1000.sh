#!/bin/bash
set -e -u -o pipefail
source config/config.sh

# ==============================================================================
# STEP 3b: RECONSTRUCT HIGH-RESOLUTION B1000 VOLUME
# ==============================================================================
#
# - Uses Slice-to-Volume Reconstruction (SVR) via `mirtk reconstruct` to
#   create a single, high-resolution, motion-corrected b1000 volume from all
#   the individual preprocessed stacks.
# - Uses a pre-existing identity transform file for the reference stack.
#
# ==============================================================================

# --- Configuration ---
REF_STACK_FILE="${OUTPUT_DIR}/reference_stack.txt"
REFERENCE_STACK=$(cat "$REF_STACK_FILE")

TEMPLATE_IMG="$OUTPUT_DIR/${REFERENCE_STACK}_final_b1000.nii.gz"
MASK_IMG="$OUTPUT_DIR/${REFERENCE_STACK}_brain_mask_eddycorr_dilated.nii.gz"

session_basename="${SUBJECT_ID}_${SESSION_ID}_dir-AP"
OUTPUT_SVR_B1000="$OUTPUT_DIR/${session_basename}_b1000_SVR.nii.gz"

echo "--- Preparing for b1000 SVR Reconstruction ---"

# --- Gather Input Files for Reconstruction ---
STACK_FILES=()
DOF_FILES=()

# Look in OUTPUT_DIR for successfully preprocessed b1000 files
detected_stacks=( $(ls "${OUTPUT_DIR}"/${SUBJECT_ID}_${SESSION_ID}_*run-*_final_b1000.nii.gz 2>/dev/null | sort) )

for file_path in "${detected_stacks[@]}"; do
    filename=$(basename "$file_path" .nii.gz)          # e.g., sub-01_ses-01_dir-AP_run-01_final_b1000
    basename=${filename%_final_b1000}                  # e.g., sub-01_ses-01_dir-AP_run-01
    
    STACK_IMG_PATH="$OUTPUT_DIR/${basename}_final_b1000.nii.gz"
    STACK_FILES+=("${STACK_IMG_PATH}")
    
    DOF_PATH="$OUTPUT_DIR/${basename}_to_${REFERENCE_STACK}.dof"
    DOF_FILES+=("${DOF_PATH}")
done

NUM_STACKS=${#STACK_FILES[@]}
echo "Found ${NUM_STACKS} b1000 stacks for reconstruction."

# --- Prepare paths for Singularity ---
# We will bind OUTPUT_DIR to /bids-work inside the container
CONTAINER_ROOT="/bids-work"

echo "Building file lists for Singularity..."

SINGULARITY_STACK_ARGS=()
for file in "${STACK_FILES[@]}"; do
    # Logic: /bids-work/ + filename
    SINGULARITY_STACK_ARGS+=("${CONTAINER_ROOT}/$(basename "${file}")")
done

SINGULARITY_DOF_ARGS=()
for file in "${DOF_FILES[@]}"; do
    SINGULARITY_DOF_ARGS+=("${CONTAINER_ROOT}/$(basename "${file}")")
done

# --- Run SVR Reconstruction ---
echo "--- Executing mirtk reconstruct for b1000 ---"

# We bind OUTPUT_DIR to /bids-work
singularity run --cleanenv \
    --bind "${OUTPUT_DIR}:${CONTAINER_ROOT}" \
    --pwd "${CONTAINER_ROOT}" \
    "${svrtk_path}" \
    mirtk reconstruct \
    "${CONTAINER_ROOT}/$(basename "${OUTPUT_SVR_B1000}")" \
    "${NUM_STACKS}" \
    "${SINGULARITY_STACK_ARGS[@]}" \
    --dofin "${SINGULARITY_DOF_ARGS[@]}" \
    --template "${CONTAINER_ROOT}/$(basename "${TEMPLATE_IMG}")" \
    --mask "${CONTAINER_ROOT}/$(basename "${MASK_IMG}")" \
    --resolution "${SVR_B1000_RESOLUTION}" \
    --iterations "${SVR_B1000_ITERATIONS}" \

echo "--- High-resolution b1000 reconstruction complete! ---"