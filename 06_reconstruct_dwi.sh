#!/bin/bash

# ==============================================================================
# STEP 6: RECONSTRUCT HIGH-RESOLUTION DWI SIGNAL
# ==============================================================================
#
# - The final and most complex step. Uses `mirtk reconstructDWI` to reconstruct
#   the full diffusion signal in the high-resolution T2 template space.
# - It calls an external Python script to first pad all input DWI stacks to a
#   uniform slice count before running the reconstruction. This preserves all
#   acquired data.
#
# ==============================================================================

# --- Configuration ---
PAD_SCRIPT_PATH="scripts/pad_stacks.py"
PAD_MODE="zero" # Use 'zero' for padding. 'edge' is also an option.

PREPROC_DIR="${DERIVATIVES_DIR}/02_preprocessed_stacks"
ALIGN_DIR="${DERIVATIVES_DIR}/05_alignment_to_t2"
DWI_RECON_DIR="${DERIVATIVES_DIR}/06_dwi_reconstruction"

# --- Input Files from Previous Steps ---
LOCAL_T2_TEMPLATE_FROM_PREV_STEP="${ALIGN_DIR}/T2_template_local_copy.nii.gz"
DOF_REF_TO_T2="${ALIGN_DIR}/${REFERENCE_ACQ}_to_T2.dof"
REF_STACK_MASK="${PREPROC_DIR}/${REFERENCE_ACQ}/brain_mask.nii.gz"
REF_STACK_TO_T2_MAT="${ALIGN_DIR}/${REFERENCE_ACQ}_to_T2.mat"

# --- Output Files for This Step ---
OUTPUT_DWI_PATH="${DWI_RECON_DIR}/DWI_SVR_in_T2_space.nii.gz"
PADDED_TEMPLATE_MASK="${DWI_RECON_DIR}/template_mask_padded.nii.gz" 

SLICE_INFO_PATH="${DWI_RECON_DIR}/slice_info.csv"

mkdir -p "${DWI_RECON_DIR}"
echo "--- Preparing for final DWI signal reconstruction ---"

# ==============================================================================
# --- STEP: Pad all DWI stacks to have a uniform slice count ---
# ==============================================================================

echo "--- Padding DWI stacks to have uniform slice count ---"

max_slices=0 # Initialize with zero
STACK_PATHS_TO_PROCESS=()
for acq_dir in "${PREPROC_DIR}"/*/; do
    stack_path="${acq_dir}/dwi_eddycorr.nii.gz"
    STACK_PATHS_TO_PROCESS+=("${stack_path}")
    num_slices=$(fslval "${stack_path}" dim3)
    if (( num_slices > max_slices )); then
        max_slices=$num_slices
    fi
done
echo "Maximum slice count found across all stacks: ${max_slices}. Padding all data to this size."

# --- Pad the T2-space mask to the target slice count ---
echo "Padding the reference brain mask to ${max_slices} slices..."
python3 "${PAD_SCRIPT_PATH}" "${REF_STACK_MASK}" "${PADDED_TEMPLATE_MASK}" "${max_slices}" "${PAD_MODE}"


# --- Perform padding/copying and gather final file lists ---
PADDED_STACK_FILES=()
GRADIENT_FILES=()
DOF_FILES=()

current_index=0
REFERENCE_STACK_INDEX=-1 # Initialize to an invalid value

for stack_path in "${STACK_PATHS_TO_PROCESS[@]}"; do
    acq_dir=$(dirname "${stack_path}")
    ACQ_ID=$(basename "${acq_dir}")

    # Check if the current stack is our designated reference stack
    if [[ "${ACQ_ID}" == "${REFERENCE_STACK}" ]]; then
        REFERENCE_STACK_INDEX=$current_index
        echo "✅ Found reference stack '${ACQ_ID}' at index ${REFERENCE_STACK_INDEX}"
    fi
    
    # 1. Pad the DWI stack
    padded_output_path="${DWI_RECON_DIR}/padded_${ACQ_ID}_dwi.nii.gz" # UPDATED
    python3 "${PAD_SCRIPT_PATH}" "${stack_path}" "${padded_output_path}" "${max_slices}" "${PAD_MODE}"
    PADDED_STACK_FILES+=("${padded_output_path}")

    # 2. Clean the gradient file by removing the header
    original_gradient_path="${PREPROC_DIR}/${ACQ_ID}/gradients_rounded.b"
    cleaned_gradient_path="${DWI_RECON_DIR}/${ACQ_ID}_gradients_cleaned.b"
    echo "Cleaning gradient file for ${ACQ_ID}..."
    tail -n +2 "${original_gradient_path}" > "${cleaned_gradient_path}"
    GRADIENT_FILES+=("${cleaned_gradient_path}")

    # 3. Gather the corresponding transform file
    DOF_FILES+=("${ALIGN_DIR}/${ACQ_ID}_to_T2.dof")

    ((current_index++))
done

NUM_STACKS=${#PADDED_STACK_FILES[@]}
echo "Prepared ${NUM_STACKS} uniformly-sized DWI stacks for final reconstruction."

# --- Prepare paths for Singularity (Robust Method) ---
echo "Building file lists for Singularity..."
SINGULARITY_STACK_ARGS=()
for file in "${PADDED_STACK_FILES[@]}"; do
    SINGULARITY_STACK_ARGS+=("/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${file}")")
done
SINGULARITY_GRADIENT_ARGS=()
for file in "${GRADIENT_FILES[@]}"; do
    SINGULARITY_GRADIENT_ARGS+=("/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${file}")")
done
SINGULARITY_DOF_ARGS=()
for file in "${DOF_FILES[@]}"; do
    SINGULARITY_DOF_ARGS+=("/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${file}")")
done


# --- Run DWI Reconstruction ---
echo "--- Assembling and executing mirtk reconstructDWI ---"
DWI_RECON_DIR_RELATIVE=$(realpath --relative-to="${DERIVATIVES_DIR}" "${DWI_RECON_DIR}")

singularity run \
    --pwd "/shared/${DWI_RECON_DIR_RELATIVE}" \
    --bind "${DERIVATIVES_DIR}":/shared \
    "${SVRTK_SIF_PATH}" mirtk reconstructDWI \
    "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${OUTPUT_DWI_PATH}")" \
    "${NUM_STACKS}" \
    "${SINGULARITY_STACK_ARGS[@]}" \
    "${SINGULARITY_GRADIENT_ARGS[@]}" \
    "${DWI_RECON_BVAL}" \
    "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${LOCAL_T2_TEMPLATE_FROM_PREV_STEP}")" \
    "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${DOF_REF_TO_T2}")" \
    -mask "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${PADDED_TEMPLATE_MASK}")" \
    -template "${REFERENCE_STACK_INDEX}" \
    -resolution "${DWI_RECON_RESOLUTION}" \
    -iterations "${DWI_RECON_ITERATIONS}" \
    -order "${DWI_RECON_SH_ORDER}" \
    -motion_model_hs \
    -smooth_mask 5 \
    -motion_sigma 15 \
    -sigma 20 \
    -no_robust_statistics \
    -info "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${SLICE_INFO_PATH}")"

echo
echo "--- DWI Reconstruction complete! ---"
echo "High-resolution DWI signal saved to: ${OUTPUT_DWI_PATH}"

rm "${DWI_RECON_DIR}"/{corrected,orig,simulated,stack}*.nii.gz
  