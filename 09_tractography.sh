#!/bin/bash
set -euo pipefail

# ==========================================================
# Configuration 
# ==========================================================

TENSOR_DIR="${DERIVATIVES_DIR}/07_tensor_fitting"
MASKS_DIR="${DERIVATIVES_DIR}/08_mask_propagation"
TRACTOGRAPHY_DIR="${DERIVATIVES_DIR}/09_tractography"
mkdir -p "${TRACTOGRAPHY_DIR}"

TISSUE_SEG="${MASKS_DIR}/tissue_segmentation_in_dwi.nii.gz"
ODF_FILE="${TENSOR_DIR}/fod_csd.nii.gz"



# ==========================================================
# 1. Create semi-5TT tissue masks
# ==========================================================
fslmaths "${TISSUE_SEG}" -thr 3 -uthr 3 -bin "${TRACTOGRAPHY_DIR}/mask_cortex"
fslmaths "${TISSUE_SEG}" -thr 2 -uthr 2 -bin "${TRACTOGRAPHY_DIR}/mask_wm"
fslmaths "${TISSUE_SEG}" -thr 1 -uthr 1 -bin "${TRACTOGRAPHY_DIR}/mask_csf"
fslmaths "${TISSUE_SEG}" -thr 4 -uthr 4 -bin -add "${TRACTOGRAPHY_DIR}/mask_csf" "${TRACTOGRAPHY_DIR}/mask_csf"
fslmaths "${TISSUE_SEG}" -mul 0 "${TRACTOGRAPHY_DIR}/mask_empty"

# Merge into a 4D 5TT-like volume
fslmerge -t "${TRACTOGRAPHY_DIR}/5tt_tissues.nii.gz" \
  "${TRACTOGRAPHY_DIR}/mask_cortex.nii.gz" \
  "${TRACTOGRAPHY_DIR}/mask_empty.nii.gz" \
  "${TRACTOGRAPHY_DIR}/mask_wm.nii.gz" \
  "${TRACTOGRAPHY_DIR}/mask_csf.nii.gz" \
  "${TRACTOGRAPHY_DIR}/mask_empty.nii.gz"

# Clean temporary masks
rm "${TRACTOGRAPHY_DIR}"/mask_{cortex,empty,wm,csf}.nii.gz



# ==========================================================
# 2. Brain mask and GM/WM interface seed
# ==========================================================
fslmaths "${TISSUE_SEG}" -bin "${TRACTOGRAPHY_DIR}/mask_brain.nii.gz"
5tt2gmwmi "${TRACTOGRAPHY_DIR}/5tt_tissues.nii.gz" "${TRACTOGRAPHY_DIR}/gmwm_seed.nii.gz" -force



# ==========================================================
# 3. Compute streamline length limits
# ==========================================================
VOLUME=$(fslstats "${TRACTOGRAPHY_DIR}/mask_brain.nii.gz" -V | awk '{print $2}')
LENGTH_MIN=$(awk "BEGIN{print (${VOLUME})^(1/3)/1.6}")
LENGTH_MAX=$(awk "BEGIN{print (${VOLUME})^(1/3)/0.55}")



# ==========================================================
# 4. Tractography generation 
# ==========================================================
ANGLES=(25)
N_STREAMLINES=5000000
N_SUBSET=200000
N_THREADS=64

for ANGLE in "${ANGLES[@]}"; do
  echo "Generating streamlines with angle ${ANGLE}°..."
  tckgen \
    -act "${TRACTOGRAPHY_DIR}/5tt_tissues.nii.gz" -backtrack \
    -seed_gmwmi "${TRACTOGRAPHY_DIR}/gmwm_seed.nii.gz" \
    -angle "${ANGLE}" \
    -nthreads "${N_THREADS}" \
    -maxlength "${LENGTH_MAX}" \
    -minlength "${LENGTH_MIN}" \
    -select "${N_STREAMLINES}" \
    "${ODF_FILE}" "${TRACTOGRAPHY_DIR}/tracks_${N_STREAMLINES}_angle_${ANGLE}.tck" \
    -force

  # Extract subset
  tckedit \
    "${TRACTOGRAPHY_DIR}/tracks_${N_STREAMLINES}_angle_${ANGLE}.tck" \
    -number "${N_SUBSET}" \
    "${TRACTOGRAPHY_DIR}/tracks_${N_SUBSET}_angle_${ANGLE}.tck" \
    -force
done
