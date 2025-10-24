#!/bin/bash
set -e -u -o pipefail

# ==============================================================================
# STEP 4b: RECONSTRUCT HIGH-RESOLUTION B1000 VOLUME
# ==============================================================================
#
# - Similar to 4a, but reconstructs the mean b1000 image. This volume is
#   often better for cross-modal registration (e.g., to a T2 image).
#
# ==============================================================================

# --- Configuration ---
PREPROC_DIR="${DERIVATIVES_DIR}/02_preprocessed_stacks"
REG_DIR="${DERIVATIVES_DIR}/03_registration"
SVR_DIR="${DERIVATIVES_DIR}/04_svr_reconstruction"

REF_STACK_FILE="${DERIVATIVES_DIR}/reference_stack.txt"
REFERENCE_STACK=$(cat "$REF_STACK_FILE")

TEMPLATE_IMG="${PREPROC_DIR}/${REFERENCE_STACK}/final_b1000.nii.gz"
MASK_IMG="${PREPROC_DIR}/${REFERENCE_STACK}/brain_mask.nii.gz"
OUTPUT_SVR_B1000="${SVR_DIR}/b1000_SVR.nii.gz"

mkdir -p "${SVR_DIR}"
echo "--- Preparing for b1000 SVR Reconstruction ---"

# --- Gather Input Files for Reconstruction ---
STACK_FILES=()
DOF_FILES=()
# The thickness list is now built inside the loop for clarity
# THICKNESS_LIST=()

for acq_dir in "${PREPROC_DIR}"/*/; do
    ACQ_ID=$(basename "${acq_dir}")
    STACK_IMG_PATH="${PREPROC_DIR}/${ACQ_ID}/final_b1000_masked.nii.gz"
    
    STACK_FILES+=("${STACK_IMG_PATH}")
    
    DOF_PATH="${REG_DIR}/${ACQ_ID}_to_${REFERENCE_STACK}.dof"
    if [ ! -f "$DOF_PATH" ]; then
        echo "FATAL: Transform not found at ${DOF_PATH}" >&2; exit 1
    fi
    DOF_FILES+=("${DOF_PATH}")
done

NUM_STACKS=${#STACK_FILES[@]}
echo "Found ${NUM_STACKS} b1000 stacks for reconstruction."

# --- Prepare paths for Singularity (Robust Method) ---
# We replace the fragile path string manipulation with the reliable
# `realpath --relative-to` approach for all file paths.

echo "Building file lists for Singularity..."
SINGULARITY_STACK_ARGS=()
for file in "${STACK_FILES[@]}"; do
    SINGULARITY_STACK_ARGS+=("/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${file}")")
done

SINGULARITY_DOF_ARGS=()
for file in "${DOF_FILES[@]}"; do
    SINGULARITY_DOF_ARGS+=("/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${file}")")
done

# === CHANGE 1: Define the SVR directory relative to the bind point ===
SVR_DIR_RELATIVE=$(realpath --relative-to="${DERIVATIVES_DIR}" "${SVR_DIR}")

# --- Run SVR Reconstruction ---
echo "--- Executing mirtk reconstruct for b1000 ---"

# === CHANGE 2: Fix the --bind, --pwd, and all path arguments ===
singularity run --pwd "/shared/${SVR_DIR_RELATIVE}" --bind "${DERIVATIVES_DIR}":/shared \
    "${SVRTK_SIF_PATH}" \
    mirtk reconstruct \
    "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${OUTPUT_SVR_B1000}")" \
    "${NUM_STACKS}" \
    "${SINGULARITY_STACK_ARGS[@]}" \
    -dofin "${SINGULARITY_DOF_ARGS[@]}" \
    -template "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${TEMPLATE_IMG}")" \
    -mask "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${MASK_IMG}")" \
    -smooth_mask 4 \
    -resolution "${SVR_RESOLUTION}" \
    -iterations "${SVR_ITERATIONS}"


echo "--- High-resolution b1000 reconstruction complete! ---"