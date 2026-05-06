#!/bin/bash
set -e -u -o pipefail
source config/config.sh


# ==============================================================================
# STEP 3: REGISTER STACKS TO REFERENCE
# ==============================================================================
#
# - Registers the mean b1000 image from each preprocessed stack to the
#   mean b1000 image of a designated reference stack (e.g., an axial scan).
# - For the reference stack itself, an identity transformation is created.
# - Uses FSL FLIRT to compute a 6 DOF (rigid) transformation for non-reference
#   stacks.
# - Converts all resulting .mat transform files to MIRTK's .dof format,
#   which is required for the SVR reconstruction steps.
#
# ==============================================================================

detected_stacks=( $(ls "${OUTPUT_DIR}"/${SUBJECT_ID}_${SESSION_ID}_*run-*_final_b1000.nii.gz 2>/dev/null | sort) )

# select the reference stack
MASK_DIR="${DERIVATIVES_DIR}/svrtk/${SUBJECT_ID}/${SESSION_ID}/dwi"

REFERENCE_STACK=$(python3 scripts/select_reference_stack.py \
    --subject "$SUBJECT_ID" \
    --session "$SESSION_ID" \
    --output-dir "$OUTPUT_DIR" \
    --mask-dir "$MASK_DIR" \
    --use-mask)

REF_STACK_FILE="${OUTPUT_DIR}/reference_stack.txt"

echo "Reference stack is: $REFERENCE_STACK"
echo "$REFERENCE_STACK" > "$REF_STACK_FILE"

# The reference image to which all others will be aligned
REFERENCE_IMG_MASKED="$OUTPUT_DIR/${REFERENCE_STACK}_final_b1000_masked.nii.gz"
REFERENCE_IMG_UNMASKED="$OUTPUT_DIR/${REFERENCE_STACK}_final_b1000.nii.gz"

echo "Registering all stacks to reference: ${REFERENCE_STACK}"

# --- Loop over all preprocessed acquisitions ---
for file_path in "${detected_stacks[@]}"; do
    filename=$(basename "$file_path" .nii.gz)          # e.g., sub-01_ses-01_dir-AP_run-01_final_b1000
    basename=${filename%_final_b1000}                  # e.g., sub-01_ses-01_dir-AP_run-01
    
    echo "Processing registration for: ${basename}"

    # --- Path Definitions ---
    # These paths are defined for every acquisition, including the reference
    MOVING_IMG_MASKED="$OUTPUT_DIR/${basename}_final_b1000_masked.nii.gz"
    MOVING_IMG_UNMASKED="$OUTPUT_DIR/${basename}_final_b1000.nii.gz"

    OUTPUT_PREFIX="$OUTPUT_DIR/${basename}_to_${REFERENCE_STACK}"
    OUTPUT_MAT="${OUTPUT_PREFIX}.mat"
    OUTPUT_DOF="${OUTPUT_PREFIX}.dof"

    # --- Step 1: Create Transformation Matrix ---
    # If the current stack is the reference, create an identity matrix.
    # Otherwise, run FLIRT to compute the registration.
    if [[ "$basename" == "$REFERENCE_STACK" ]]; then
        echo "  -> This is the reference stack. Creating identity transform"
        cp tools/identity.mat "${OUTPUT_MAT}"
    else
        echo "  -> Registering ${basename} to ${REFERENCE_STACK} with FLIRT..."
        # Rigid Registration with FLIRT
        flirt -in "${MOVING_IMG_MASKED}" \
              -ref "${REFERENCE_IMG_MASKED}" \
              -out "${OUTPUT_PREFIX}_registered.nii.gz" \
              -omat "${OUTPUT_MAT}" \
              -dof 6  \
              -searchrx -180 180 -searchry -180 180 -searchrz -180 180
    fi

    # --- Step 2: Convert FLIRT .mat to MIRTK .dof ---
    echo "  -> Converting FLIRT matrix to MIRTK DOF"
    singularity run --pwd /shared --bind "${OUTPUT_DIR}":/shared \
        "${mirtk_path}" \
        convert-dof "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${OUTPUT_MAT}")" \
                    "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${OUTPUT_DOF}")" \
        -input-format flirt -output-format mirtk_affine \
        -source "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${MOVING_IMG_MASKED}")" \
        -target "/shared/$(realpath --relative-to="${OUTPUT_DIR}" "${REFERENCE_IMG_MASKED}")"
done

echo "All registrations complete."