# --------- Directories Parameters ---------
BABOFET_BIDS_DIR=/envau/work/meca/data/BaboFet_BIDS
RAWDATA_DIR=${BABOFET_BIDS_DIR}/sourcedata/raw
DERIVATIVES_DIR=${BABOFET_BIDS_DIR}/derivatives
OUTPUT_TMP_DIR=${DERIVATIVES_DIR}/intermediate/svrtk


# --------- Reconstruction ---------
SVR_B0_RESOLUTION="0.5"      # Isotropic resolution for b0 SVR
SVR_B0_ITERATIONS="6"        # Iterations for b0 SVR

SVR_B1000_RESOLUTION="0.5"      # Isotropic resolution for b0 SVR
SVR_B1000_ITERATIONS="6"        # Iterations for b0 SVR

SVR_DWI_RESOLUTION="0.5"     # Isotropic resolution for the final DWI reconstruction
SVR_DWI_ITERATIONS="10"      # Iterations for dwi SVR
SVR_DWI_SH_ORDER="4"         # Spherical Harmonics order
SVR_DWI_BVAL="1000"          # The b-value shell to reconstruct


# --------- SOFTWARE ---------
export mirtk_path="$PWD/sif_images/mirtk.sif"
export svrtk_path="$PWD/sif_images/svrtk.sif"

C3D_TOOL_PATH="$PWD/tools/c3d_affine_tool"

# --------- Other Parameters ---------
NTHR=64
export ACTIVATE_ENV="eval \"\$(conda shell.bash hook)\" && conda activate babofet_env"

export EXCLUDE_RUNS=("sub-Aziza_ses-01_dir-AP_run-05" "sub-Aziza_ses-01_dir-AP_run-06")