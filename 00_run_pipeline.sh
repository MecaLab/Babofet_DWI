#!/bin/bash
set -e -u -o pipefail # Fail on error, undefined variable, or pipe failure

# ==============================================================================
# MASTER SCRIPT FOR FETAL DWI RECONSTRUCTION PIPELINE
# ==============================================================================
#
# USAGE:
#   1. Configure the variables in the "USER CONFIGURATION" section below.
#   2. Run the script from your project's root directory: ./00_run_pipeline.sh
#
# ==============================================================================

# --- USER CONFIGURATION ---

module purge
module load all
module load ANTS mrtrix singularity

FSLDIR=/home/cazzolla.m/fsl
PATH=${FSLDIR}/share/fsl/bin:${PATH}
export FSLDIR PATH
. ${FSLDIR}/etc/fslconf/fsl.sh
export PATH="/home/cazzolla.m/share/fsl/bin:${PATH}"

# --- Input Data ---
# BIDS-compliant root directory containing the raw data (e.g., ./sub-Aziza/)
BIDS_ROOT_DIR="/envau/work/meca/data/babofetDiffusion/BIDS/rawdata"

# These are now passed as arguments instead of being hardcoded
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <SUBJECT_ID> <SESSION_ID>"
    exit 1
fi
SUBJECT_ID="$1"
SESSION_ID="$2"


# --- T2 TEMPLATE SELECTION ---

# Extract numeric session index (e.g., ses-05 → 5)
session_num=${SESSION_ID//ses-/}
session_num=$((10#$session_num))  # force decimal

# Base path to T2s for the subject
T2_BASE_DIR="/envau/work/meca/data/babofetDiffusion/BIDS/derivatives/T2_recon/sub-${SUBJECT_ID}"

# Construct candidate paths
curr_path="${T2_BASE_DIR}/ses-$(printf "%02d" ${session_num})/T2_recon.nii.gz"
prev_path="${T2_BASE_DIR}/ses-$(printf "%02d" $((session_num - 1)))/T2_recon.nii.gz"
next_path="${T2_BASE_DIR}/ses-$(printf "%02d" $((session_num + 1)))/T2_recon.nii.gz"

curr_path_mask="${T2_BASE_DIR}/ses-$(printf "%02d" ${session_num})/T2_recon_mask.nii.gz"
prev_path_mask="${T2_BASE_DIR}/ses-$(printf "%02d" $((session_num - 1)))/T2_recon_mask.nii.gz"
next_path_mask="${T2_BASE_DIR}/ses-$(printf "%02d" $((session_num + 1)))/T2_recon_mask.nii.gz"


# Determine which file to use
if [[ -f "${curr_path}" ]]; then
    T2_TEMPLATE_IMAGE="${curr_path}"
    T2_TEMPLATE_MASK="${curr_path_mask}"
    echo "✅ Using T2 from current session: ${SESSION_ID}"
elif [[ -f "${prev_path}" ]]; then
    T2_TEMPLATE_IMAGE="${prev_path}"
    T2_TEMPLATE_MASK="${prev_path_mask}"
    echo "⚠️  T2 not found for ${SESSION_ID}, using previous session: ses-$(printf "%02d" $((session_num - 1)))"
elif [[ -f "${next_path}" ]]; then
    T2_TEMPLATE_IMAGE="${next_path}"
    T2_TEMPLATE_MASK="${next_path_mask}"
    echo "⚠️  T2 not found for ${SESSION_ID}, using next session: ses-$(printf "%02d" $((session_num + 1)))"
else
    echo "❌ No T2 image found for session ${SESSION_ID} or its neighbors. Aborting."
    exit 1
fi

# Reconstruction parameters
SVR_RESOLUTION="0.5"      # Isotropic resolution for b0/b1000 SVR
SVR_ITERATIONS="6"       # Iterations for b0/b1000 SVR

DWI_RECON_RESOLUTION="0.5" # Isotropic resolution for the final DWI reconstruction
DWI_RECON_ITERATIONS="10"
DWI_RECON_SH_ORDER="4"     # Spherical Harmonics order
DWI_RECON_BVAL="1000"      # The b-value shell to reconstruct

# --- Software Paths (Singularity Images) ---
# Make sure these paths are correct for your system.
SVRTK_SIF_PATH="sif_images/svrtk.sif"
MIRTK_SIF_PATH="sif_images/mirtk.sif"

# --- END OF USER CONFIGURATION ---


# --- Pipeline Setup ---
# Export variables to be used by subscripts
export BIDS_ROOT_DIR SUBJECT_ID SESSION_ID
export T2_TEMPLATE_IMAGE T2_TEMPLATE_MASK REFERENCE_ACQ
export SVR_RESOLUTION SVR_ITERATIONS SVR_SLICE_THICKNESS
export DWI_RECON_RESOLUTION DWI_RECON_ITERATIONS DWI_RECON_SH_ORDER DWI_RECON_BVAL
export SVRTK_SIF_PATH MIRTK_SIF_PATH

# Construct derivative paths
export DERIVATIVES_DIR="/envau/work/meca/data/babofetDiffusion/BIDS/derivatives/reconstruction_05mm/sub-${SUBJECT_ID}/${SESSION_ID}"

# --- Execute Pipeline Steps ---

echo "========================================="
echo "🚀 STARTING FETAL DWI PIPELINE"
echo "========================================="
echo "Subject: ${SUBJECT_ID}"
echo "Session: ${SESSION_ID}"
echo "Derivatives will be saved in: ${DERIVATIVES_DIR}"
echo "-----------------------------------------"

echo "STEP 1: Preparing and organizing data..."
bash ./01_prepare_data.sh
echo "✅ STEP 1 complete."
echo "-----------------------------------------"

echo "STEP 2: Preprocessing individual DWI stacks..."
bash ./02_preprocess_stacks.sh
echo "✅ STEP 2 complete."
echo "-----------------------------------------"

echo "STEP 3: Registering stacks to reference..."
bash ./03_register_stacks.sh
echo "✅ STEP 3 complete."
echo "-----------------------------------------"

echo "STEP 4a: Reconstructing high-resolution b0 volume..."
bash ./04a_reconstruct_b0.sh
echo "✅ STEP 4a complete."
echo "-----------------------------------------"

echo "STEP 4b: Reconstructing high-resolution b1000 volume..."
bash ./04b_reconstruct_b1000.sh
echo "✅ STEP 4b complete."
echo "-----------------------------------------"

echo "STEP 5: Aligning reconstructed volumes to T2 template..."
bash ./05_align_to_t2.sh
echo "✅ STEP 5 complete."
echo "-----------------------------------------"

echo "STEP 6: Reconstructing high-resolution DWI signal..."
bash ./06_reconstruct_dwi.sh
echo "✅ STEP 6 complete."
echo "-----------------------------------------"

echo "STEP 7: Fitting tensor and FOD..."
bash ./07_fit_tensor.sh
echo "✅ STEP 7 complete."
echo "-----------------------------------------"

echo "STEP 8: Propagating masks..."
bash ./08_mask_propagation.sh
echo "✅ STEP 8 complete."
echo "-----------------------------------------"

module purge
module load all
module load FSL

echo "STEP 99: QC plots..."
bash ./99_quality_control.sh
echo "✅ STEP 99 complete."
echo "-----------------------------------------"

echo "STEP 999: snapshots..."
bash ./999_snapshots.sh
echo "✅ STEP 99 complete."
echo "-----------------------------------------"

echo "========================================="
echo "🎉 PIPELINE FINISHED SUCCESSFULLY!"
echo "========================================="