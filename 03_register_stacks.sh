#!/bin/bash
set -e -u -o pipefail

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

# --- Configuration ---
PREPROC_DIR="${DERIVATIVES_DIR}/02_preprocessed_stacks"
REG_DIR="${DERIVATIVES_DIR}/03_registration"

MANUAL_MASKS_ROOT="/envau/work/meca/data/babofetDiffusion/BIDS/derivatives/manual_masks"
MANUAL_MASK_DIR="${MANUAL_MASKS_ROOT}/sub-${SUBJECT_ID}/${SESSION_ID}/"

mkdir -p "${REG_DIR}"

# select the reference stack
REFERENCE_STACK=$(python3 scripts/select_reference_stack.py "$MANUAL_MASK_DIR")

echo "Reference stack is: $REFERENCE_STACK"
echo "$REFERENCE_STACK" > "$REF_STACK_FILE"

# The reference image to which all others will be aligned
REFERENCE_IMG_MASKED="${PREPROC_DIR}/${REFERENCE_STACK}/final_b1000_masked.nii.gz"
REFERENCE_IMG_UNMASKED="${PREPROC_DIR}/${REFERENCE_STACK}/final_b1000.nii.gz"

echo "Registering all stacks to reference: ${REFERENCE_STACK}"

# --- Loop over all preprocessed acquisitions ---
for acq_dir in "${PREPROC_DIR}"/*/; do
    ACQ_ID=$(basename "${acq_dir}")

    echo "Processing registration for: ${ACQ_ID}"

    # --- Path Definitions ---
    # These paths are defined for every acquisition, including the reference
    MOVING_IMG_MASKED="${PREPROC_DIR}/${ACQ_ID}/final_b1000_masked.nii.gz"
    MOVING_IMG_UNMASKED="${PREPROC_DIR}/${ACQ_ID}/final_b1000.nii.gz"

    OUTPUT_PREFIX="${REG_DIR}/${ACQ_ID}_to_${REFERENCE_STACK}"
    OUTPUT_MAT="${OUTPUT_PREFIX}.mat"
    OUTPUT_DOF="${OUTPUT_PREFIX}.dof"

    # --- Step 1: Create Transformation Matrix ---
    # If the current stack is the reference, create an identity matrix.
    # Otherwise, run FLIRT to compute the registration.
    if [[ "$ACQ_ID" == "$REFERENCE_STACK" ]]; then
        echo "  -> This is the reference stack. Creating identity transform"
        # Create identity .mat file manually (4x4 identity matrix in FLIRT format)
        cat > "${OUTPUT_MAT}" << 'EOF'
1 0 0 0
0 1 0 0
0 0 1 0
0 0 0 1
EOF
    else
        echo "  -> Registering ${ACQ_ID} to ${REFERENCE_STACK} with FLIRT..."
        # Rigid Registration with FLIRT
        flirt -in "${MOVING_IMG_MASKED}" \
              -ref "${REFERENCE_IMG_MASKED}" \
              -out "${OUTPUT_PREFIX}_registered.nii.gz" \
              -omat "${OUTPUT_MAT}" \
              -dof 6  \
              -searchrx -180 180 -searchry -180 180 -searchrz -180 180
    fi

    # --- Step 2: Convert FLIRT .mat to MIRTK .dof ---
    # This step is now performed for all acquisitions, including the reference.
    echo "  -> Converting FLIRT matrix to MIRTK DOF"
    singularity run --pwd /shared --bind "${DERIVATIVES_DIR}":/shared \
        "${MIRTK_SIF_PATH}" \
        convert-dof "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${OUTPUT_MAT}")" \
                    "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${OUTPUT_DOF}")" \
        -input-format flirt -output-format mirtk_affine \
        -source "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${MOVING_IMG_MASKED}")" \
        -target "/shared/$(realpath --relative-to="${DERIVATIVES_DIR}" "${REFERENCE_IMG_MASKED}")"
done

echo "All registrations complete."