#!/bin/bash

# ==============================================================================
# STEP 8: PROPAGATE MASKS
# ==============================================================================

# --- Configuration ---
SESSION_ID_NO_DASH=${SESSION_ID//-/}

TISSUE_SEGMENTATION="/envau/work/meca/data/babofetDiffusion/BIDS/derivatives/parcellations//${SUBJECT_ID}_${SESSION_ID_NO_DASH}.nii.gz"

ALIGN_DIR="${DERIVATIVES_DIR}/05_alignment_to_t2"
TENSOR_DIR="${DERIVATIVES_DIR}/07_tensor_fitting"
MASK_DIR="${DERIVATIVES_DIR}/08_mask_propagation"

mkdir -p "${MASK_DIR}"

# --- Step 1: convert t2 transformation to dof  ---
SRC="${ALIGN_DIR}/T2_template_local_copy.nii.gz"
REFERENCE="${TENSOR_DIR}/mean_dwi_target.nii.gz"
MAT="${TENSOR_DIR}/T2_in_DWI.mat"
DOF="${MASK_DIR}/T2_in_DWI.txt"

tools/c3d_affine_tool -ref "${REFERENCE}" -src "${SRC}" "${MAT}" -fsl2ras -oitk "${DOF}"

# --- Step 2: propagate mask from T2 to DWI space ---
TISSUE_SEGMENTATION_IN_DWI="${MASK_DIR}/tissue_segmentation_in_dwi.nii.gz"

antsApplyTransforms \
    -d 3 \
    -i "${TISSUE_SEGMENTATION}" \
    -r "${REFERENCE}" \
    -t "${DOF}" \
    -o "${TISSUE_SEGMENTATION_IN_DWI}" \
    --interpolation GenericLabel \

