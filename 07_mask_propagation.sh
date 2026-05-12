#!/bin/bash

# ==============================================================================
# STEP 7: PROPAGATE MASKS
# ==============================================================================
source config/config.sh

REFERENCE="${OUTPUT_DIR}/${SESSION_BASENAME}_mean_dwi_target.nii.gz"
DOF="${OUTPUT_DIR}/${SESSION_BASENAME}_T2_in_DWI.mat"
TISSUE_SEGMENTATION_IN_DWI="${OUTPUT_DIR}/${SESSION_BASENAME}_tissue_segmentation_in_dwi.nii.gz"

# convert .mat to .txt for antsApplyTransforms
$C3D_TOOL_PATH \
    -ref "${REFERENCE}" \
    -src "${T2W_RECONSTRUCTED}" \
    "${DOF}" \
    -fsl2ras \
    -oitk "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_in_DWI.txt"

antsApplyTransforms \
    -d 3 \
    -i "${T2W_RECONSTRUCTED_TISSUES}" \
    -r "${REFERENCE}" \
    -t "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_in_DWI.txt" \
    -o "${TISSUE_SEGMENTATION_IN_DWI}" \
    --interpolation GenericLabel \


cp "${TISSUE_SEGMENTATION_IN_DWI}" "${DERIVATIVES_OUTPUT_DIR_SVRTK}/${SESSION_BASENAME_NODIR}_desc-tissue_segmentation.nii.gz"

