#!/bin/bash
source config/config.sh

# ==============================================================================
# STEP 6: RECONSTRUCT HIGH-RESOLUTION DWI SIGNAL (OPTION B: FORCED TRANSFORMS)
# ==============================================================================
#
# - Uses `mirtk reconstructDWI` to reconstruct the signal in T2 space.
# - Implements "Option B": Explicitly feeds a transformation file for EVERY
#   single 3D volume to the -dofin flag to bypass the parser behavior.
#
# ==============================================================================

# --- Configuration ---
PAD_SCRIPT_PATH="scripts/pad_stacks.py"
PAD_MODE="zero" 

REF_STACK_FILE="${OUTPUT_DIR}/reference_stack.txt"
REFERENCE_STACK=$(cat "$REF_STACK_FILE")

# --- Input Files ---
DOF_REF_TO_T2="${OUTPUT_DIR}/${REFERENCE_STACK}_to_T2.dof"
REF_STACK_MASK="${OUTPUT_DIR}/${REFERENCE_STACK}_brain_mask_eddycorr_dilated.nii.gz"

# --- Output Files ---
OUTPUT_DWI_PATH="${OUTPUT_DIR}/${SESSION_BASENAME}_DWI_SVR_in_T2_space.nii.gz"
PADDED_TEMPLATE_MASK="${OUTPUT_DIR}/${REFERENCE_STACK}_mask_padded.nii.gz" 
SLICE_INFO_PATH="${OUTPUT_DIR}/${SESSION_BASENAME}_slice_info.csv"

echo "--- Preparing for final DWI signal reconstruction ---"

# ==============================================================================
# --- STEP: Pad all DWI stacks to have a uniform slice count ---
# ==============================================================================

echo "--- Padding DWI stacks and preparing lists ---"
detected_stacks=( $(ls "${OUTPUT_DIR}"/${SUBJECT_ID}_${SESSION_ID}_*run-*_dwi_eddycorr.nii.gz 2>/dev/null | sort) )

max_slices=0
STACK_PATHS_TO_PROCESS=()
for file_path in "${detected_stacks[@]}"; do
    filename=$(basename "$file_path" .nii.gz)
    basename=${filename%_dwi_eddycorr}

    stack_path="${OUTPUT_DIR}/${basename}_dwi_eddycorr.nii.gz"
    if [ -f "$stack_path" ]; then
        STACK_PATHS_TO_PROCESS+=("${stack_path}")
        num_slices=$(fslval "${stack_path}" dim3)
        if (( num_slices > max_slices )); then
            max_slices=$num_slices
        fi
    fi
done
echo "Maximum slice count: ${max_slices}. Padding all data to this size."

# --- Pad the T2-space mask ---
python3 "${PAD_SCRIPT_PATH}" "${REF_STACK_MASK}" "${PADDED_TEMPLATE_MASK}" "${max_slices}" "${PAD_MODE}"


# --- Prepare Arrays (Using Local Paths for Readability) ---
PADDED_STACK_FILES=()
GRADIENT_FILES=()
EXPLODED_DOF_ARGS=() # This will hold the long list of transforms

current_index=0
REFERENCE_STACK_INDEX=-1 

for stack_path in "${STACK_PATHS_TO_PROCESS[@]}"; do

    filename=$(basename "${stack_path}") # sub-01_ses-01_dir-AP_run-01_dwi_eddycorr.nii.gz
    basename=${filename%%_dwi_eddycorr.nii.gz}  # e.g., sub-01_ses-01_dir-AP_run-01

    if [[ "${basename}" == "${REFERENCE_STACK}" ]]; then
        REFERENCE_STACK_INDEX=$current_index
    fi
    
    # 1. Pad the DWI stack
    padded_output_path="${OUTPUT_DIR}/${basename}_padded_dwi.nii.gz"
    python3 "${PAD_SCRIPT_PATH}" "${stack_path}" "${padded_output_path}" "${max_slices}" "${PAD_MODE}"
    PADDED_STACK_FILES+=("${padded_output_path}")

    # 2. Clean the gradient file
    original_gradient_path="${OUTPUT_DIR}/${basename}_gradients.b"
    cleaned_gradient_path="${OUTPUT_DIR}/${basename}_gradients_cleaned.b"
    tail -n +2 "${original_gradient_path}" > "${cleaned_gradient_path}"
    GRADIENT_FILES+=("${cleaned_gradient_path}")

    # 3. [NEW] Build the repeated transform list for this stack
    local_dof="${OUTPUT_DIR}/${basename}_to_T2.dof"
    
    # Count volumes (lines) in the cleaned gradient file (e.g., 30)
    num_volumes=$(wc -l < "${cleaned_gradient_path}")
    
    # Append the transform file to the array 'num_volumes' times
    for (( i=0; i<30; i++ )); do
        EXPLODED_DOF_ARGS+=("${local_dof}")
    done

    ((current_index++))
done

NUM_STACKS=${#PADDED_STACK_FILES[@]}


# ==============================================================================
# --- Convert Paths for Singularity ---
# ==============================================================================

SINGULARITY_STACK_ARGS=()
for file in "${PADDED_STACK_FILES[@]}"; do
    SINGULARITY_STACK_ARGS+=("/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${file}")")
done

SINGULARITY_GRADIENT_ARGS=()
for file in "${GRADIENT_FILES[@]}"; do
    SINGULARITY_GRADIENT_ARGS+=("/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${file}")")
done

SINGULARITY_DOF_ARGS=()
for file in "${EXPLODED_DOF_ARGS[@]}"; do
    SINGULARITY_DOF_ARGS+=("/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${file}")")
done


# --- Run DWI Reconstruction ---
echo "--- Assembling and executing mirtk reconstructDWI ---"

T2_DIR=$(dirname "${T2W_RECONSTRUCTED}")
T2_NAME=$(basename "${T2W_RECONSTRUCTED}")


singularity run \
    --pwd "/shared" \
    --bind "${OUTPUT_DIR}":/shared \
    --bind "${T2_DIR}":/t2_ref \
    "${svrtk_path}" mirtk reconstructDWI \
    "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${OUTPUT_DWI_PATH}")" \
    "${NUM_STACKS}" \
    "${SINGULARITY_STACK_ARGS[@]}" \
    "${SINGULARITY_GRADIENT_ARGS[@]}" \
    "${SVR_DWI_BVAL}" \
    "/t2_ref/${T2_NAME}" \
    "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${DOF_REF_TO_T2}")" \
    -mask "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${PADDED_TEMPLATE_MASK}")" \
    -dofin "${SINGULARITY_DOF_ARGS[@]}" \
    -template "${REFERENCE_STACK_INDEX}" \
    -resolution "${SVR_DWI_RESOLUTION}" \
    -iterations "${SVR_DWI_ITERATIONS}" \
    -order "${SVR_DWI_SH_ORDER}" \
    -motion_model_hs \
    -smooth_mask 5 \
    -motion_sigma 15 \
    -sigma 20 \
    -no_robust_statistics \
    -info "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${SLICE_INFO_PATH}")" \
    

echo
echo "--- DWI Reconstruction complete! ---"
echo "High-resolution DWI signal saved to: ${OUTPUT_DWI_PATH}"

cp "${OUTPUT_DIR}/shCoeff9.nii.gz" "${DERIVATIVES_OUTPUT_DIR_SVRTK}/${SESSION_BASENAME}_rec-svrtk_SH.nii.gz"

rm "${OUTPUT_DIR}"/{corrected,orig,simulated,stack}*.nii.gz