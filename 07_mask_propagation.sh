#!/bin/bash

# ==============================================================================
# STEP 7: PROPAGATE MASKS
# ==============================================================================

REFERENCE="${OUTPUT_DIR}/${SESSION_BASENAME}_mean_dwi_target.nii.gz"
DOF="${OUTPUT_DIR}/${SESSION_BASENAME}_T2_in_DWI.mat"
TISSUE_SEGMENTATION_IN_DWI="${OUTPUT_DIR}/${SESSION_BASENAME}_tissue_segmentation_in_dwi.nii.gz"

antsApplyTransforms \
    -d 3 \
    -i "${T2W_RECONSTRUCTED_TISSUES}" \
    -r "${REFERENCE}" \
    -t "${DOF}" \
    -o "${TISSUE_SEGMENTATION_IN_DWI}" \
    --interpolation GenericLabel \

