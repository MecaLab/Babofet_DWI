#!/bin/bash
# ==============================================================================
# STEP 1: PREPROCESS INDIVIDUAL DWI STACKS
# ==============================================================================
#
# For each DWI stack, this script performs:
#   1. Denoising (dwidenoise)
#   3. Field Map Estimation using TOPUP (if opposite PE fmap exists)
#   4. N4 Bias Field Correction
#   5. Eddy Current, Motion, and Distortion Correction (FSL Eddy with TOPUP)
#   6. Extraction of mean b0 and b1000 images for registration/reconstruction.
#
# ==============================================================================
source config/config.sh

# Look in OUTPUT_DIR for successfully preprocessed b1000 files
detected_stacks=( $(ls "${OUTPUT_DIR}"/${SUBJECT_ID}_${SESSION_ID}_*run-*_final_b1000.nii.gz 2>/dev/null | sort) )

for file_path in "${detected_stacks[@]}"; do
    filename=$(basename "$file_path" .nii.gz)          # e.g., sub-01_ses-01_dir-AP_run-01_final_b1000
    basename=${filename%_final_b1000}                  # e.g., sub-01_ses-01_dir-AP_run-01

    echo "Processing Acquisition: ${basename}"

    # extact new mask on the motion corrected data
    eval "$(conda shell.bash hook)"
    conda activate nnunet

    BRAIN_MASK="$OUTPUT_DIR/${basename}_brain_mask_eddycorr.nii.gz"

    python3 scripts/nnunet_brainmask.py \
        -i "$OUTPUT_DIR/${basename}_final_b0.nii.gz" \
        -o "$BRAIN_MASK" \
        --device "cpu"

    DILATED_BRAIN_MASK="$OUTPUT_DIR/${basename}_brain_mask_eddycorr_dilated.nii.gz"
    DILATED2_BRAIN_MASK="$OUTPUT_DIR/${basename}_brain_mask_eddycorr_dilated2.nii.gz"
    fslmaths "${BRAIN_MASK}" -kernel 3D -dilM "${DILATED_BRAIN_MASK}"
    fslmaths "${DILATED_BRAIN_MASK}" -kernel 2D -dilM "${DILATED2_BRAIN_MASK}"
        
    eval "$(conda shell.bash hook)"
    conda activate eddy3

    fslmaths "$OUTPUT_DIR/${basename}_final_b0.nii.gz" -mul "${DILATED_BRAIN_MASK}" "$OUTPUT_DIR/${basename}_final_b0_masked.nii.gz"
    fslmaths "$OUTPUT_DIR/${basename}_final_b1000.nii.gz" -mul "${DILATED_BRAIN_MASK}" "$OUTPUT_DIR/${basename}_final_b1000_masked.nii.gz"

    echo "✅ Finished preprocessing: ${basename}"

done