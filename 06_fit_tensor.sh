#!/bin/bash
set -e -u -o pipefail
source config/config.sh

# ==============================================================================
# STEP 7: FIT TENSOR AND COMPUTE METRICS
# ==============================================================================
#
# This script takes the final high-resolution reconstructed DWI volume and:
# 1. Computes a mean diffusion-weighted image to serve as a stable target.
# 2. Registers the high-resolution b0 volume to this mean DWI.
# 3. Concatenates the registered b0 and the DWI volume into a final 4D image.
# 4. Creates a corresponding gradient file with the b0 information.
# 5. Fits a diffusion tensor model using `dwi2tensor`.
# 6. Extracts key tensor metrics (FA, ADC, V1) using `tensor2metric`.
# 7. Estimates the fiber orientation distribution (FOD) using CSD.
#
# ==============================================================================

# --- Configuration ---
REF_STACK_FILE="${OUTPUT_DIR}/reference_stack.txt"
REFERENCE_STACK=$(cat "$REF_STACK_FILE")

# --- Input Files from Previous Steps ---
RECON_DWI="${OUTPUT_DIR}/${SESSION_BASENAME}_DWI_SVR_in_T2_space.nii.gz"
RECON_B0="${OUTPUT_DIR}/${SESSION_BASENAME}_b0_SVR.nii.gz"

# Use the cleaned gradient file for the reference acquisition as the base for our new one
BASE_GRAD_FILE="${OUTPUT_DIR}/final-b-file.b"

# --- Output Files for This Step ---
MEAN_DWI="${OUTPUT_DIR}/${SESSION_BASENAME}_mean_dwi_target.nii.gz"
REG_B0="${OUTPUT_DIR}/${SESSION_BASENAME}_b0_SVR_registered_to_dwi.nii.gz"
B0_TO_DWI_MAT="${OUTPUT_DIR}/${SESSION_BASENAME}_b0_to_dwi.mat"
CONCAT_DWI="${OUTPUT_DIR}/${SESSION_BASENAME}_dwi_final_with_b0.nii.gz"
FINAL_GRAD_FILE="${OUTPUT_DIR}/${SESSION_BASENAME}_gradient_table_with_b0.b"


TENSOR_MIF="${OUTPUT_DIR}/${SESSION_BASENAME}_tensor.mif"
TENSOR_NII="${OUTPUT_DIR}/${SESSION_BASENAME}_tensor.nii.gz"


RESPONSE_TXT="${OUTPUT_DIR}/${SESSION_BASENAME}_response_tournier.txt"
FOD_MIF="${OUTPUT_DIR}/${SESSION_BASENAME}_fod_csd.mif"
FOD_NII="${OUTPUT_DIR}/${SESSION_BASENAME}_fod_csd.nii.gz"
FOD_NORM_MIF="${OUTPUT_DIR}/${SESSION_BASENAME}_fod_csd_norm.mif"

echo "--- Starting tensor fitting and metric extraction ---"

# --- Step 1: Compute Average of Reconstructed DWI for Stable Registration Target ---
echo "STEP 7.1: Computing mean of the reconstructed DWI volume..."
mrmath "${RECON_DWI}" mean -axis 3 "${MEAN_DWI}" -force

# can we improve the alignemt of the t2 in the dwi space?
flirt -in "${T2W_RECONSTRUCTED}" \
      -ref "${MEAN_DWI}" \
      -out "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_in_DWI.nii.gz" \
      -omat "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_in_DWI.mat" \
      -interp spline \
      -searchrx -20 20 -searchry -20 20 -searchrz -20 20 \
      -cost normmi \
      -dof 6

cp "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_in_DWI.mat" "${DERIVATIVES_OUTPUT_DIR_SVRTK}/${SESSION_BASENAME}_from-T2w_to-dwi_mode-image_xfm.txt"

# B0 -> B0 in T2 space -> T2 to DWI
echo "STEP 7.2: Concatenating b0->T2 and T2->DWI transforms..."
convert_xfm \
    -omat "${OUTPUT_DIR}/${SESSION_BASENAME}_b0_to_dwi.mat" \
    -concat "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_in_DWI.mat" "${OUTPUT_DIR}/${SESSION_BASENAME}_b0_SVR_to_T2.mat"

flirt \
    -in "${RECON_B0}" \
    -ref "${MEAN_DWI}" \
    -out "${OUTPUT_DIR}/${SESSION_BASENAME}_b0_SVR_registered_to_DWI.nii.gz" \
    -init "${OUTPUT_DIR}/${SESSION_BASENAME}_b0_to_dwi.mat" \
    -applyxfm -interp spline


# ok terrible, we have the mask, lets use it and dilate it a bit
fslmaths "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_in_DWI.nii.gz" -thr 20 -bin "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_mask.nii.gz"


# --- Step 3: Concatenate Registered b0 and Reconstructed DWI ---
echo "STEP 7.3: Concatenating b0 and DWI volumes..."
mrcat "${OUTPUT_DIR}/${SESSION_BASENAME}_b0_SVR_registered_to_DWI.nii.gz" "${RECON_DWI}" "${CONCAT_DWI}" -nthreads 64 -force

# --- Step 4: Create Final Gradient File with b0 Entry ---
echo "STEP 7.4: Creating final gradient table..."
# Add the b=0 line at the beginning of the file
echo "0 0 0 0" > "${FINAL_GRAD_FILE}"
# Append the original diffusion gradient information
cat "${BASE_GRAD_FILE}" >> "${FINAL_GRAD_FILE}"
echo "Final gradient table created at ${FINAL_GRAD_FILE}"

mrconvert \
    $CONCAT_DWI \
    "${OUTPUT_DIR}/${SESSION_BASENAME}_dwi_final_with_b0.mif" \
    -grad "${FINAL_GRAD_FILE}" \
    -export_grad_fsl "${OUTPUT_DIR}/${SESSION_BASENAME}_dwi_final_with_b0.bvec" "${OUTPUT_DIR}/${SESSION_BASENAME}_dwi_final_with_b0.bval" \
    -force

cp "${OUTPUT_DIR}/${SESSION_BASENAME}_dwi_final_with_b0.nii.gz" "${DERIVATIVES_OUTPUT_DIR_SVRTK}/${SESSION_BASENAME_NODIR}_rec-svrtk_dwi.nii.gz"
cp "${OUTPUT_DIR}/${SESSION_BASENAME}_dwi_final_with_b0.bvec" "${DERIVATIVES_OUTPUT_DIR_SVRTK}/${SESSION_BASENAME_NODIR}_rec-svrtk_dwi.bvec"
cp "${OUTPUT_DIR}/${SESSION_BASENAME}_dwi_final_with_b0.bval" "${DERIVATIVES_OUTPUT_DIR_SVRTK}/${SESSION_BASENAME_NODIR}_rec-svrtk_dwi.bval"

# for bids need to say if dwi data is skull stripped or not
touch "${DERIVATIVES_OUTPUT_DIR_SVRTK}/${SESSION_BASENAME_NODIR}_rec-svrtk_dwi.json"
jq '. + {"SkullStripped": false}' "${DERIVATIVES_OUTPUT_DIR_SVRTK}/${SESSION_BASENAME_NODIR}_rec-svrtk_dwi.json"


# --- Step 5: Fit Diffusion Tensor ---
echo "STEP 7.5: Fitting the diffusion tensor model..."
dwi2tensor \
    "${CONCAT_DWI}" "${TENSOR_MIF}" \
    -grad "${FINAL_GRAD_FILE}" \
    -mask "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_mask.nii.gz" \
    -force

mrconvert \
    "${TENSOR_MIF}" \
    "${TENSOR_NII}" \
    -force

# --- Step 6: Extract Tensor Metrics ---
echo "STEP 7.6: Extracting tensor metrics ..."
tensor2metric "${TENSOR_MIF}" \
    -adc "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_adc.nii.gz" \
    -fa "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_fa.nii.gz" \
    -ad "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_ad.nii.gz" \
    -rd "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_rd.nii.gz" \
    -cl "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_cl.nii.gz" \
    -cp "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_cp.nii.gz" \
    -cs "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_cs.nii.gz" \
    -vec "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_v1.nii.gz" \
    -force

cp "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_fa.nii.gz" "${DERIVATIVES_OUTPUT_DIR_MRTRIX}/${SESSION_BASENAME_NODIR}_FA.nii.gz"
cp "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_adc.nii.gz" "${DERIVATIVES_OUTPUT_DIR_MRTRIX}/${SESSION_BASENAME_NODIR}_MD.nii.gz"
cp "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_v1.nii.gz" "${DERIVATIVES_OUTPUT_DIR_MRTRIX}/${SESSION_BASENAME_NODIR}_colFA.nii.gz"
cp "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_ad.nii.gz" "${DERIVATIVES_OUTPUT_DIR_MRTRIX}/${SESSION_BASENAME_NODIR}_AD.nii.gz"
cp "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor_rd.nii.gz" "${DERIVATIVES_OUTPUT_DIR_MRTRIX}/${SESSION_BASENAME_NODIR}_RD.nii.gz"
cp "${OUTPUT_DIR}/${SESSION_BASENAME}_tensor.nii.gz" "${DERIVATIVES_OUTPUT_DIR_MRTRIX}/${SESSION_BASENAME_NODIR}_tensor.nii.gz"




# --- Step 7: Estimate Response Function and Fiber Orientation Distribution (FOD) ---
echo "STEP 7.7: Estimating response function and FODs via CSD..."
# Estimate response function
dwi2response tournier \
    "${RECON_DWI}" "${RESPONSE_TXT}" \
    -lmax 6 \
    -grad "${BASE_GRAD_FILE}" \
    -mask "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_mask.nii.gz" \
    -nthreads 64 -force

# Estimate Fiber Orientation Distributions using CSD
dwi2fod csd \
    "${RECON_DWI}" \
    "${RESPONSE_TXT}" \
    "${FOD_MIF}" \
    -lmax 6 \
    -grad "${BASE_GRAD_FILE}" \
    -mask "${OUTPUT_DIR}/${SESSION_BASENAME}_T2_mask.nii.gz" \
    -nthreads 64 -force

mrconvert \
    "${FOD_MIF}" \
    "${FOD_NII}" \
    -force
echo "FOD estimation complete. Output saved to ${FOD_MIF}"

echo
echo "--- Tensor fitting and metric extraction complete! ---"