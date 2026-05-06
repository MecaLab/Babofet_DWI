#!/bin/bash
set -e -u -o pipefail # Fail on error, undefined variable, or pipe failure

# ==============================================================================
# MASTER SCRIPT FOR FETAL DWI RECONSTRUCTION PIPELINE
# ==============================================================================

# --- USER CONFIGURATION ---

if [ -f "config/env_setup.sh" ]; then
    source "config/env_setup.sh"
fi

# Check if required tools are in PATH
for cmd in mrconvert fslmaths antsRegistration singularity; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd could not be found. Please ensure FSL, MRtrix, ANTs, and Singularity are installed and loaded."
        exit 1
    fi
done


if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <SUBJECT_ID> <SESSION_ID>"
    exit 1
fi

export SUBJECT_ID="$1"
export SESSION_ID="$2"
source 'config/config.sh'

export SESSION_BASENAME="${SUBJECT_ID}_${SESSION_ID}_dir-AP"
export SESSION_BASENAME_NODIR="${SUBJECT_ID}_${SESSION_ID}"

export SESSION_RAW_DATA_DIR="${RAWDATA_DIR}/${SUBJECT_ID}/${SESSION_ID}/dwi"
export SESSION_FMAP_DATA_DIR="${RAWDATA_DIR}/${SUBJECT_ID}/${SESSION_ID}/fmap"
export T2W_RECONSTRUCTED="${DERIVATIVES_DIR}/niftymic/${SUBJECT_ID}/${SESSION_ID}/anat/${SUBJECT_ID}_${SESSION_ID}_rec-niftymic_desc-brain_T2w.nii.gz"
export T2W_RECONSTRUCTED_BG="${DERIVATIVES_DIR}/niftymic/${SUBJECT_ID}/${SESSION_ID}/anat/${SUBJECT_ID}_${SESSION_ID}_rec-niftymic_desc-brainbg_T2w.nii.gz"
export T2W_RECONSTRUCTED_MASK="${DERIVATIVES_DIR}/niftymic/${SUBJECT_ID}/${SESSION_ID}/anat/${SUBJECT_ID}_${SESSION_ID}_rec-niftymic_desc-brain_mask.nii.gz"
export T2W_RECONSTRUCTED_TISSUES="${DERIVATIVES_DIR}/longiseg/${SUBJECT_ID}/${SESSION_ID}/anat/${SUBJECT_ID}_${SESSION_ID}_desc-longiseg_dseg.nii.gz"


export OUTPUT_DIR=${OUTPUT_TMP_DIR}/${SUBJECT_ID}/${SESSION_ID}
export DERIVATIVES_OUTPUT_DIR_SVRTK="${DERIVATIVES_DIR}/svrtk/${SUBJECT_ID}/${SESSION_ID}/dwi"
export DERIVATIVES_OUTPUT_DIR_SVRTK_XFM="${DERIVATIVES_DIR}/svrtk/${SUBJECT_ID}/${SESSION_ID}/xfm"
export DERIVATIVES_OUTPUT_DIR_MRTRIX="${DERIVATIVES_DIR}/mrtrix/${SUBJECT_ID}/${SESSION_ID}/dwi"

mkdir -p "${OUTPUT_DIR}"
mkdir -p "${DERIVATIVES_OUTPUT_DIR_SVRTK}"
mkdir -p "${DERIVATIVES_OUTPUT_DIR_SVRTK_XFM}"
mkdir -p "${DERIVATIVES_OUTPUT_DIR_MRTRIX}"


export detected_stacks=( $(ls "${SESSION_RAW_DATA_DIR}"/${SUBJECT_ID}_${SESSION_ID}_*run-*_dwi.nii.gz 2>/dev/null | sort) )
stack_count=${#detected_stacks[@]}

# --- Execute Pipeline Steps ---

echo "========================================="
echo "STARTING BABOFET DWI PIPELINE"
echo "========================================="
echo "Subject: ${SUBJECT_ID}"
echo "Session: ${SESSION_ID}"
echo "Number of stacks: ${stack_count}"
echo "-----------------------------------------"

echo "STEP 1: Preprocessing individual DWI stacks..."
bash ./01_preprocess_stacks.sh
echo "✅ STEP 1 complete."
echo "-----------------------------------------"

echo "STEP 1a: Extracting brain mask..."
bash ./01a_brain_extraction.sh
echo "✅ STEP 1a complete."
echo "-----------------------------------------"

echo "STEP 2: Registering stacks to reference..."
bash ./02_register_stacks.sh
echo "✅ STEP 2 complete."
echo "-----------------------------------------"

echo "STEP 3a: Reconstructing high-resolution b0 volume..."
bash ./03a_reconstruct_b0.sh
echo "✅ STEP 3a complete."
echo "-----------------------------------------"

echo "STEP 3b: Reconstructing high-resolution b1000 volume..."
bash ./03b_reconstruct_b1000.sh
echo "✅ STEP 3b complete."
echo "-----------------------------------------"

echo "STEP 4: Aligning reconstructed volumes to T2 template..."
bash ./04_align_to_t2.sh
echo "✅ STEP 4 complete."
echo "-----------------------------------------"

echo "STEP 5: Reconstructing high-resolution DWI signal..."
bash ./05_reconstruct_dwi.sh
echo "✅ STEP 5 complete."
echo "-----------------------------------------"

echo "STEP 6: Fitting tensor and FOD..."
bash ./06_fit_tensor.sh
echo "✅ STEP 6 complete."
echo "-----------------------------------------"

echo "STEP 7: Propagating masks..."
bash ./07_mask_propagation.sh
echo "✅ STEP 7 complete."
echo "-----------------------------------------"

#echo "STEP 9: Tractography..."
#bash ./09_tractography.sh
#echo "✅ STEP 9 complete."
#echo "-----------------------------------------"

echo "========================================="
echo "PIPELINE FINISHED SUCCESSFULLY!"
echo "========================================="