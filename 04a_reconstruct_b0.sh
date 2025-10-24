#!/bin/bash
set -e -u -o pipefail

# ==============================================================================
# STEP 4a: RECONSTRUCT HIGH-RESOLUTION B0 VOLUME
# ==============================================================================
#
# - Uses Slice-to-Volume Reconstruction (SVR) via `mirtk reconstruct` to
#   create a single, high-resolution, motion-corrected b0 volume from all
#   the individual preprocessed stacks.
# - Uses a pre-existing identity transform file for the reference stack.
#
# ==============================================================================

# --- Configuration ---
PREPROC_DIR="${DERIVATIVES_DIR}/02_preprocessed_stacks"
REG_DIR="${DERIVATIVES_DIR}/03_registration"
SVR_DIR="${DERIVATIVES_DIR}/04_svr_reconstruction"

REF_STACK_FILE="${DERIVATIVES_DIR}/reference_stack.txt"
REFERENCE_STACK=$(cat "$REF_STACK_FILE")

TEMPLATE_IMG="${PREPROC_DIR}/${REFERENCE_STACK}/final_b0.nii.gz"
MASK_IMG="${PREPROC_DIR}/${REFERENCE_STACK}/brain_mask.nii.gz"
OUTPUT_SVR_B0="${SVR_DIR}/b0_SVR.nii.gz"

# --- Identity Transform ---
# Path to your constant identity.dof file. This must be somewhere inside your
# ${PROJECT_ROOT} directory to be accessible by Singularity.

mkdir -p "${SVR_DIR}"
echo "--- Preparing for b0 SVR Reconstruction ---"

# --- Gather Input Files for Reconstruction ---
STACK_FILES=()
DOF_FILES=()

for acq_dir in "${PREPROC_DIR}"/*/; do
    ACQ_ID=$(basename "${acq_dir}")
    STACK_IMG_PATH="${PREPROC_DIR}/${ACQ_ID}/final_b0.nii.gz"
    
    STACK_FILES+=("${STACK_IMG_PATH}")
    
    DOF_PATH="${REG_DIR}/${ACQ_ID}_to_${REFERENCE_STACK}.dof"
    if [ ! -f "$DOF_PATH" ]; then
        echo "FATAL: Transform not found at ${DOF_PATH}" >&2; exit 1
    fi
    DOF_FILES+=("${DOF_PATH}")
done

NUM_STACKS=${#STACK_FILES[@]}
echo "Found ${NUM_STACKS} b0 stacks for reconstruction."

# --- Prepare paths for Singularity ---

echo "Building file lists for Singularity..."
SINGULARITY_STACK_ARGS=()
for file in "${STACK_FILES[@]}"; do
    SINGULARITY_STACK_ARGS+=("/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${file}")")
done

SINGULARITY_DOF_ARGS=()
for file in "${DOF_FILES[@]}"; do
    SINGULARITY_DOF_ARGS+=("/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${file}")")
done

# --- Run SVR Reconstruction ---
echo "--- Executing mirtk reconstruct for b0 ---"
SVR_DIR_RELATIVE=$(realpath --relative-to="${DERIVATIVES_DIR}" "${SVR_DIR}")

singularity run --pwd "/shared/${SVR_DIR_RELATIVE}" --bind "${DERIVATIVES_DIR}":/shared \
    "${SVRTK_SIF_PATH}" \
    mirtk reconstruct \
    "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${OUTPUT_SVR_B0}")" \
    "${NUM_STACKS}" \
    "${SINGULARITY_STACK_ARGS[@]}" \
    --dofin "${SINGULARITY_DOF_ARGS[@]}" \
    --template "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${TEMPLATE_IMG}")" \
    --mask "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${MASK_IMG}")" \
    --resolution "${SVR_RESOLUTION}" \
    --iterations "${SVR_ITERATIONS}" \
    --structural \
    --global_bias_correction

echo "--- High-resolution b0 reconstruction complete! ---"