#!/bin/bash
set -e -u -o pipefail

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
SVR_DIR="${DERIVATIVES_DIR}/04_svr_reconstruction"
ALIGN_DIR="${DERIVATIVES_DIR}/05_alignment_to_t2"
DWI_RECON_DIR="${DERIVATIVES_DIR}/06_dwi_reconstruction"
TENSOR_DIR="${DERIVATIVES_DIR}/07_tensor_fitting"

REF_STACK_FILE="${DERIVATIVES_DIR}/reference_stack.txt"
REFERENCE_STACK=$(cat "$REF_STACK_FILE")

# --- Input Files from Previous Steps ---
RECON_DWI="${DWI_RECON_DIR}/DWI_SVR_in_T2_space.nii.gz"
RECON_B0="${SVR_DIR}/b0_SVR.nii.gz"
# Use the cleaned gradient file for the reference acquisition as the base for our new one
BASE_GRAD_FILE="${DWI_RECON_DIR}/final-b-file.b"

# --- Output Files for This Step ---
MEAN_DWI="${TENSOR_DIR}/mean_dwi_target.nii.gz"
REG_B0="${TENSOR_DIR}/b0_SVR_registered_to_dwi.nii.gz"
B0_TO_DWI_MAT="${TENSOR_DIR}/b0_to_dwi.mat"
CONCAT_DWI="${TENSOR_DIR}/dwi_final_with_b0.nii.gz"
FINAL_GRAD_FILE="${TENSOR_DIR}/gradient_table_with_b0.b"


TENSOR_MIF="${TENSOR_DIR}/tensor.mif"
TENSOR_NII="${TENSOR_DIR}/tensor.nii.gz"


RESPONSE_TXT="${TENSOR_DIR}/response_tournier.txt"
FOD_MIF="${TENSOR_DIR}/fod_csd.mif"
FOD_NII="${TENSOR_DIR}/fod_csd.nii.gz"
FOD_NORM_MIF="${TENSOR_DIR}/fod_csd_norm.mif"
AFD_TOTAL_NII="${TENSOR_DIR}/afd_total.nii.gz"

mkdir -p "${TENSOR_DIR}"
echo "--- Starting tensor fitting and metric extraction ---"

# --- Step 1: Compute Average of Reconstructed DWI for Stable Registration Target ---
echo "STEP 7.1: Computing mean of the reconstructed DWI volume..."
mrmath "${RECON_DWI}" mean -axis 3 "${MEAN_DWI}" -force

# can we improve the alignemt of the t2 in the dwi space?
flirt -in "${T2_TEMPLATE_IMAGE}" \
      -ref "${MEAN_DWI}" \
      -out "${TENSOR_DIR}/T2_in_DWI.nii.gz" \
      -omat "${TENSOR_DIR}/T2_in_DWI.mat" \
      -interp spline \
      -searchrx -20 20 -searchry -20 20 -searchrz -20 20 \
      -cost normmi \
      -dof 6

# B0 -> B0 in T2 space -> T2 to DWI
echo "STEP 7.2: Concatenating b0->T2 and T2->DWI transforms..."
convert_xfm -omat "${TENSOR_DIR}/b0_to_dwi.mat" -concat "${TENSOR_DIR}/T2_in_DWI.mat" "${ALIGN_DIR}/b0_SVR_to_T2.mat"

flirt -in "${RECON_B0}" -ref "${MEAN_DWI}" -out "${TENSOR_DIR}/b0_SVR_registered_to_DWI.nii.gz" -init "${TENSOR_DIR}/b0_to_dwi.mat" -applyxfm -interp spline

fslmaths "${TENSOR_DIR}/T2_in_DWI.nii.gz" -thr 20 -bin "${TENSOR_DIR}/T2_mask.nii.gz"


# --- Step 3: Concatenate Registered b0 and Reconstructed DWI ---
echo "STEP 7.3: Concatenating b0 and DWI volumes..."
mrcat "${TENSOR_DIR}/b0_SVR_registered_to_DWI.nii.gz" "${RECON_DWI}" "${CONCAT_DWI}" -force

# --- Step 4: Create Final Gradient File with b0 Entry ---
echo "STEP 7.4: Creating final gradient table..."
# Add the b=0 line at the beginning of the file
echo "0 0 0 0" > "${FINAL_GRAD_FILE}"
# Append the original diffusion gradient information
cat "${BASE_GRAD_FILE}" >> "${FINAL_GRAD_FILE}"
echo "Final gradient table created at ${FINAL_GRAD_FILE}"

# --- Step 5: Fit Diffusion Tensor ---
echo "STEP 7.5: Fitting the diffusion tensor model..."
dwi2tensor "${CONCAT_DWI}" "${TENSOR_MIF}" -grad "${FINAL_GRAD_FILE}" -mask "${TENSOR_DIR}/T2_mask.nii.gz" -force
mrconvert "${TENSOR_MIF}" "${TENSOR_NII}" -force

# --- Step 6: Extract Tensor Metrics ---
echo "STEP 7.6: Extracting tensor metrics ..."
tensor2metric "${TENSOR_MIF}" \
    -adc "${TENSOR_DIR}/tensor_adc.nii.gz" \
    -fa "${TENSOR_DIR}/tensor_fa.nii.gz" \
    -ad "${TENSOR_DIR}/tensor_ad.nii.gz" \
    -rd "${TENSOR_DIR}/tensor_rd.nii.gz" \
    -cl "${TENSOR_DIR}/tensor_cl.nii.gz" \
    -cp "${TENSOR_DIR}/tensor_cp.nii.gz" \
    -cs "${TENSOR_DIR}/tensor_cs.nii.gz" \
    -vec "${TENSOR_DIR}/tensor_v1.nii.gz" \
    -force

# --- Step 7: Estimate Response Function and Fiber Orientation Distribution (FOD) ---
echo "STEP 7.7: Estimating response function and FODs via CSD..."
# Estimate response function
dwi2response tournier "${RECON_DWI}" "${RESPONSE_TXT}" -lmax 6 -grad "${BASE_GRAD_FILE}" -mask "${TENSOR_DIR}/T2_mask.nii.gz" -force

# Estimate Fiber Orientation Distributions using CSD
dwi2fod csd "${RECON_DWI}" "${RESPONSE_TXT}" "${FOD_MIF}" -lmax 6 -grad "${BASE_GRAD_FILE}" -mask "${TENSOR_DIR}/T2_mask.nii.gz" -nthreads 64 -force
mrconvert "${FOD_MIF}" "${FOD_NII}" -force
echo "FOD estimation complete. Output saved to ${FOD_MIF}"

echo
echo "--- Tensor fitting and metric extraction complete! ---"