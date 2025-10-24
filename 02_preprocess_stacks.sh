#!/bin/bash
# ==============================================================================
# STEP 2: PREPROCESS INDIVIDUAL DWI STACKS
# ==============================================================================
#
# For each DWI stack, this script performs:
#   1. Denoising (dwidenoise)
#   2. Brain Extraction (BET using a custom script)
#   3. Field Map Estimation using TOPUP (if opposite PE fmap exists)
#   4. N4 Bias Field Correction
#   5. Eddy Current, Motion, and Distortion Correction (FSL Eddy with TOPUP)
#   6. Extraction of mean b0 and b1000 images for registration/reconstruction.
#
# ==============================================================================

# --- Configuration ---
PREPARED_DIR="${DERIVATIVES_DIR}/01_prepared_stacks"
PREPROC_DIR="${DERIVATIVES_DIR}/02_preprocessed_stacks"
RAW_FMAP_DIR="${BIDS_ROOT_DIR}/sub-${SUBJECT_ID}/sub-${SUBJECT_ID}_${SESSION_ID}/fmap"

# Paths to external scripts and models
MODEL_PATH="/envau/work/meca/users/cazzolla.m/my_fetal_bet/AttUNet.pth"
BET_SCRIPT="/envau/work/meca/users/cazzolla.m/my_fetal_bet/inference.py"
MASK_POSTPROCESS_SCRIPT="scripts/postprocess_mask.py"

# --- Environment Setup ---

echo "Starting preprocessing of all stacks..."
mkdir -p "${PREPROC_DIR}"

SKIP_IDS=()

# --- Loop over each prepared acquisition ---
for acq_dir in "${PREPARED_DIR}"/*/; do

    ACQ_ID=$(basename "${acq_dir}")
    echo "🔄 Processing Acquisition: ${ACQ_ID}"

    # Check if ACQ_ID is in the skip list
    if [[ " ${SKIP_IDS[@]} " =~ " ${ACQ_ID} " ]]; then
        echo "⏩ Skipping Acquisition: ${ACQ_ID}"
        continue
    fi

    # --- Path Definitions ---
    RAW_PATH="${PREPARED_DIR}/${ACQ_ID}"
    OUT_PATH="${PREPROC_DIR}/${ACQ_ID}"
    mkdir -p "${OUT_PATH}"

    NII="${RAW_PATH}/dwi.nii.gz"
    BVEC="${RAW_PATH}/dwi.bvec"
    BVAL="${RAW_PATH}/dwi.bval"
    JSON="${RAW_PATH}/dwi.json"

    # --- Step 0: Data Conversion ---
    CLEAN_JSON="${OUT_PATH}/dwi_cleaned.json"
    jq 'del(.DeidentificationMethodCodeSequence)' "$JSON" > "$CLEAN_JSON"
    mrconvert "$NII" "$OUT_PATH/dwi.mif" -fslgrad "$BVEC" "$BVAL" -json_import "$CLEAN_JSON" \
        -export_pe_eddy "$OUT_PATH/eddy_acqp.txt" "$OUT_PATH/eddy_index.txt" -force

    # check if number of slices is even
    SLICES=$(python3 -c "import nibabel as nib; print(nib.load('$NII').shape[2])")
    echo "Number of slices in DWI: $SLICES"

    EVEN=1
    if (( SLICES % 2 != 0 )); then
        EVEN=0
    fi 

    # --- Step 1: Denoising ---
    dwidenoise "$OUT_PATH/dwi.mif" "$OUT_PATH/dwi_denoised.mif" -noise "$OUT_PATH/noise.nii.gz" -force
    mrconvert "$OUT_PATH/dwi_denoised.mif" "$OUT_PATH/dwi_denoised.nii.gz" -force

    mrdegibbs "$OUT_PATH/dwi_denoised.mif" "$OUT_PATH/dwi_degibbsed.mif" -force
    mrconvert "$OUT_PATH/dwi_degibbsed.mif" "$OUT_PATH/dwi_degibbsed.nii.gz" -force

    # --- Check for manual brain mask ---
    MANUAL_MASKS_ROOT="/envau/work/meca/data/babofetDiffusion/BIDS/derivatives/manual_masks"
    MANUAL_MASK_DIR="${MANUAL_MASKS_ROOT}/sub-${SUBJECT_ID}/${SESSION_ID}/${ACQ_ID}"

    MANUAL_MASK_FILE=$(find "$MANUAL_MASK_DIR" -type f -name '*.nii.gz' | head -n 1)
    cp "$MANUAL_MASK_FILE" "$OUT_PATH/brain_mask.nii.gz"
    BRAIN_MASK="$OUT_PATH/brain_mask.nii.gz"

    # --- Step 2: Extract b0, b1000 and brain mask ---
    dwiextract "$OUT_PATH/dwi_degibbsed.mif" -bzero - | mrmath - mean -axis 3 "$OUT_PATH/b0_denoised.nii.gz" -force
    dwiextract "$OUT_PATH/dwi_degibbsed.mif" -no_bzero - | mrmath - mean -axis 3 "$OUT_PATH/b1000_denoised.nii.gz" -force

    # necessary to ensure brain mask and dwi have same transform matrix (problems when manually segmented with Slicer)
    flirt -in "$BRAIN_MASK" -ref "$OUT_PATH/b0_denoised.nii.gz" -out "$BRAIN_MASK" -interp nearestneighbour -applyxfm -usesqform

    fslmaths "${BRAIN_MASK}" -kernel 3D -dilM "${BRAIN_MASK}"

    cp "$BRAIN_MASK" "$OUT_PATH/brain_mask_for_T2.nii.gz"
    BRAIN_MASK_FOR_T2="$OUT_PATH/brain_mask_for_T2.nii.gz"

    fslmaths "${BRAIN_MASK}" -kernel 2D -dilM "${BRAIN_MASK}"

    # --- Step 3: Field Map Estimation with TOPUP ---
    TOPUP_OUTPUT_BASENAME="${OUT_PATH}/topup_results"
    
    # Extract acq and run tags to find the matching fmap file
    ACQ_TAG=$(echo "$ACQ_ID" | sed -n 's/.*\(acq-[^_]*\).*/\1/p')
    RUN_TAG=$(echo "$ACQ_ID" | sed -n 's/.*\(run-[0-9]*\).*/\1/p')
    
    # Find the corresponding fmap file (opposite PE direction)
    FMAP_JSON=$(find "${RAW_FMAP_DIR}" -maxdepth 1 -type f -name "*${ACQ_TAG}*${RUN_TAG}*.json" | head -n 1)

    DWI_PE_DIR=$(jq -r '.PhaseEncodingDirection' "$CLEAN_JSON")
    DWI_READOUT=$(jq -r '.TotalReadoutTime' "$CLEAN_JSON")
    
    TOPUP_ENABLED=false
    if [[ -n "$FMAP_JSON" && -f "$FMAP_JSON" ]]; then
        echo "Found corresponding fmap: $(basename "$FMAP_JSON")"

        FMAP_NII="${FMAP_JSON%.json}.nii.gz"
        
        if [[ -f "$FMAP_NII" ]]; then
            TOPUP_ENABLED=true

            # b. Merge the main b0 and the fmap b0
            dwiextract "$OUT_PATH/dwi.mif" -bzero "$OUT_PATH/topup_B0_RPE_1.nii.gz" -force

            mrdegibbs "$OUT_PATH/topup_B0_RPE_1.nii.gz" "$OUT_PATH/topup_B0_RPE_1.nii.gz" -force
            mrdegibbs "$FMAP_NII" "$OUT_PATH/topup_B0_RPE_2.nii.gz" -force

            mrcat "$OUT_PATH/topup_B0_RPE_1.nii.gz" "$OUT_PATH/topup_B0_RPE_2.nii.gz" "$OUT_PATH/b0_pair.nii.gz" -force
            
            # c. Create the acqp file for topup
            FMAP_PE_DIR=$(jq -r '.PhaseEncodingDirection' "$FMAP_JSON")
            FMAP_READOUT=$(jq -r '.TotalReadoutTime' "$FMAP_JSON")

            # Convert i,j,k to FSL format
            declare -A pe_vectors=( ["i"]="1 0 0" ["i-"]="-1 0 0" ["j"]="0 1 0" ["j-"]="0 -1 0" ["k"]="0 0 1" ["k-"]="0 0 -1" )
            
            echo "${pe_vectors[$DWI_PE_DIR]} ${DWI_READOUT}" > "${OUT_PATH}/topup_acqp.txt"
            echo "${pe_vectors[$FMAP_PE_DIR]} ${FMAP_READOUT}" >> "${OUT_PATH}/topup_acqp.txt"

            if [ "$EVEN" -eq 0 ]; then
                config_file="b02b0_1.cnf"
            else
                config_file="b02b0.cnf"
            fi

            # e. Run topup
            echo "Running topup..."
            topup --imain="$OUT_PATH/b0_pair.nii.gz" --datain="$OUT_PATH/topup_acqp.txt" \
                  --config="$config_file" --out="${TOPUP_OUTPUT_BASENAME}" --iout="$OUT_PATH/b0_pair_unwarped.nii.gz" \
                  --fout="$OUT_PATH/topup_field.nii.gz" --nthr=64 
        fi
    else
        echo "WARNING: No corresponding fmap found for ${ACQ_ID}. Skipping topup."
    fi

    # --- Step 4: N4 Bias Field Correction ---
    echo "Running N4 Bias Field Correction..."
    DWI_DENOISED_NII="$OUT_PATH/dwi_degibbsed.nii.gz"
    B0_FOR_N4="$OUT_PATH/b0_denoised.nii.gz"
    DWI_BIASCORR_NII="$OUT_PATH/dwi_biascorr.nii.gz"
    
    # Define intermediate files for clarity
    N4_INPUT_B0_STD="${OUT_PATH}/n4_input_b0_std.nii.gz"
    N4_INPUT_MASK_STD="${OUT_PATH}/n4_input_mask_std.nii.gz"
    N4_CORRECTED_B0="${OUT_PATH}/n4_corrected_b0.nii.gz"
    N4_INITIAL_BIAS_FIELD="${OUT_PATH}/n4_initial_bias_field.nii.gz"
    N4_FINAL_BIAS_FIELD="${OUT_PATH}/n4_final_scaled_bias_field.nii.gz"


    # Convert images to a standard stride representation for N4
    mrconvert "$B0_FOR_N4" "$N4_INPUT_B0_STD" -strides +1,+2,+3 -force
    mrconvert "$BRAIN_MASK" "$N4_INPUT_MASK_STD" -strides +1,+2,+3 -force
    fslcpgeom "$N4_INPUT_B0_STD" "$N4_INPUT_MASK_STD" # Ensure geometry headers match
    
    # Apply N4BiasFieldCorrection on the b0 to estimate the field
    N4BiasFieldCorrection -d 3 -i "$N4_INPUT_B0_STD" -w "$N4_INPUT_MASK_STD" \
        -o "[$N4_CORRECTED_B0,$N4_INITIAL_BIAS_FIELD]" -s 1 -b [100,3] -c [1000,0.0]

     # Compute the sum of intensities inside the mask before and after N4
    S_ORIG=$(mrcalc "$N4_INPUT_B0_STD" "$N4_INPUT_MASK_STD" -mult - | mrmath - sum - -axis 0 | mrmath - sum - -axis 1 | mrmath - sum - -axis 2 | mrdump - | awk '{print $1}')
    S_CORR=$(mrcalc "$N4_CORRECTED_B0" "$N4_INPUT_MASK_STD" -mult - | mrmath - sum - -axis 0 | mrmath - sum - -axis 1 | mrmath - sum - -axis 2 | mrdump - | awk '{print $1}')

    # Calculate the global intensity scaling factor
    SCALE=$(LC_NUMERIC=C awk "BEGIN {printf \"%.6f\", $S_ORIG == 0 ? 1.0 : $S_CORR / $S_ORIG}")

    echo "Original intensity sum: $S_ORIG"
    echo "Corrected intensity sum: $S_CORR"
    echo "Global intensity scale factor: $SCALE"

    # Scale the initial bias field to create the final, intensity-preserving field
    mrcalc "$N4_INITIAL_BIAS_FIELD" "$SCALE" -mult "$N4_FINAL_BIAS_FIELD" -force
    
    # Apply the final scaled bias field to the full denoised DWI series
    mrcalc "$OUT_PATH/dwi_degibbsed.mif" "$N4_FINAL_BIAS_FIELD" -div "$OUT_PATH/dwi_biascorr.mif" -force
    mrconvert "$OUT_PATH/dwi_biascorr.mif" "$DWI_BIASCORR_NII" -force

    echo "✅ Bias correction completed."
    
    # --- Step 5: Eddy Correction ---
    MPORDER=$(python3 -c "import nibabel as nib; print(nib.load('$DWI_BIASCORR_NII').shape[2] - 1)")
    echo "Using mporder = $MPORDER"
    EDDY_CMD="eddy diffusion --imain=\"$DWI_BIASCORR_NII\" --mask=\"$BRAIN_MASK\" --index=\"$OUT_PATH/eddy_index.txt\" \
        --acqp=\"$OUT_PATH/eddy_acqp.txt\" --bvecs=\"$BVEC\" --bvals=\"$BVAL\" --json=\"$CLEAN_JSON\" \
        --out=\"$OUT_PATH/dwi_eddycorr\" --repol --ol_nstd=4 --nvoxhp=5000 --niter=8 \
        --fwhm=10,8,4,2,0,0,0,0 --ol_type=sw --mporder=${MPORDER} --s2v_niter=8 --s2v_lambda=1 --s2v_interp=spline \
        --data_is_shelled --nthr=64 --cnr_maps --residuals --verbose"

    if [[ "$TOPUP_ENABLED" == true ]]; then
        echo "Running eddy with topup correction..."
        EDDY_CMD+=" --topup=\"${TOPUP_OUTPUT_BASENAME}\" --estimate_move_by_susceptibility --mbs_niter=20 --mbs_ksp=10 --mbs_lambda=10"
    else
        echo "Estimating distortion field with T2..."

        # extract the b0
        dwiextract "$OUT_PATH/dwi_biascorr.mif" -bzero - | mrmath - mean -axis 3 "$OUT_PATH/b0_for_T2.nii.gz" -force
        fslmaths "$OUT_PATH/b0_for_T2.nii.gz" -mul "${BRAIN_MASK_FOR_T2}" "$OUT_PATH/b0_for_T2_masked.nii.gz"

        # flirt T2 to b0
        flirt \
            -in $T2_TEMPLATE_IMAGE \
            -ref "$OUT_PATH/b0_for_T2_masked.nii.gz" \
            -out "$OUT_PATH/T2_to_b0_flirt.nii.gz" \
            -omat "$OUT_PATH/T2_to_b0_flirt.mat" \
            -dof 6 \
            -bins 64 \
            -interp spline \
            -searchrx -180 180 -searchry -180 180 -searchrz -180 180 \

        flirt -in $T2_TEMPLATE_MASK -ref "$OUT_PATH/b0_for_T2_masked.nii.gz" -out "$OUT_PATH/T2_in_b0_mask.nii.gz" -init "$OUT_PATH/T2_to_b0_flirt.mat" -applyxfm -interp nearestneighbour

        # fnirt b0 to registered T2
        fnirt \
            --ref="$OUT_PATH/T2_to_b0_flirt.nii.gz" \
            --in="$OUT_PATH/b0_for_T2_masked.nii.gz" \
            --refmask="$OUT_PATH/T2_in_b0_mask.nii.gz" \
            --inmask="${BRAIN_MASK_FOR_T2}" \
            --iout="$OUT_PATH/fnirt_non_linear_Image.nii.gz" \
            --cout="$OUT_PATH/fnirt_non_linear_warpcoef.nii.gz" \
            --fout="$OUT_PATH/fnirt_non_linear_field.nii.gz" \
            --subsamp=4,2,2,1 \
            --miter=5,5,5,10 \
            --infwhm=2,1,0,0 \
            --reffwhm=2,1,0,0 \
            --warpres=10,10,10 \
            --splineorder=3 \
            --intmod=global_linear \
            --regmod=bending_energy \
            --lambda=100,80,70,50 \
            --verbose

        # extact warp field in the PE direction

        fslsplit "$OUT_PATH/fnirt_non_linear_field.nii.gz" "$OUT_PATH/fnirt_non_linear_field_comp" -t
        fslmaths "$OUT_PATH/fnirt_non_linear_field_comp0000.nii.gz" -mul 0 "$OUT_PATH/zero.nii.gz"

        if [ "${DWI_PE_DIR}" == "i" ] || [ "${DWI_PE_DIR}" == "i-" ]; then
            DISP_FIELD_COMPONENT="$OUT_PATH/fnirt_non_linear_field_comp0000.nii.gz"
            fslmerge -t "$OUT_PATH/fnirt_non_linear_field_PE.nii.gz" $DISP_FIELD_COMPONENT "$OUT_PATH/zero.nii.gz" "$OUT_PATH/zero.nii.gz"
        elif [ "${DWI_PE_DIR}" == "j" ] || [ "${DWI_PE_DIR}" == "j-" ]; then
            DISP_FIELD_COMPONENT="$OUT_PATH/fnirt_non_linear_field_comp0001.nii.gz"
            fslmerge -t "$OUT_PATH/fnirt_non_linear_field_PE.nii.gz" "$OUT_PATH/zero.nii.gz" $DISP_FIELD_COMPONENT "$OUT_PATH/zero.nii.gz"
        elif [ "${DWI_PE_DIR}" == "k" ] || [ "${DWI_PE_DIR}" == "k-" ]; then
            DISP_FIELD_COMPONENT="$OUT_PATH/fnirt_non_linear_field_comp0002.nii.gz"
            fslmerge -t "$OUT_PATH/fnirt_non_linear_field_PE.nii.gz" "$OUT_PATH/zero.nii.gz" "$OUT_PATH/zero.nii.gz" $DISP_FIELD_COMPONENT
        fi

        # convert field in hz
        OFF_RESONANCE_FIELD="$OUT_PATH/off_resonance_field_hz.nii.gz"
        if [[ $DWI_PE_DIR == *"-"* ]]; then
            # For negative PE directions (e.g., 'j-'), the sign is typically correct as is.
            fslmaths "${DISP_FIELD_COMPONENT}" -div "${DWI_READOUT}" -mul -1 "${OFF_RESONANCE_FIELD}"
        else
            # For positive PE directions (e.g., 'j'), you often need to invert the sign.
            fslmaths "${DISP_FIELD_COMPONENT}" -div "${DWI_READOUT}" "${OFF_RESONANCE_FIELD}"
        fi

        # apply warp field to data for QC
        applywarp \
            -i "$OUT_PATH/b0_for_T2.nii.gz" \
            -r "$OUT_PATH/T2_to_b0_flirt.nii.gz" \
            -w "$OUT_PATH/fnirt_non_linear_field_PE.nii.gz" \
            -o "$OUT_PATH/b0_for_T2_distorted_PE.nii.gz"  \
            --interp=spline

        # call eddy with field
        EDDY_CMD+=" --field="${OUT_PATH}/off_resonance_field_hz" --estimate_move_by_susceptibility --mbs_niter=20 --mbs_ksp=10 --mbs_lambda=10"


    fi
    
    # Execute the constructed eddy command
    eval $EDDY_CMD

    # --- Step 6: Final Image and Gradient Extraction ---
    EDDY_ROTATED_BVECS="$OUT_PATH/dwi_eddycorr.eddy_rotated_bvecs"
    mrconvert "$OUT_PATH/dwi_eddycorr.nii.gz" "$OUT_PATH/dwi_final.mif" \
                -fslgrad "$EDDY_ROTATED_BVECS" "$BVAL" -json_import "$CLEAN_JSON" \
                -export_grad_mrtrix "$OUT_PATH/gradients.b" -force

    awk 'NR==1{print}; NR>1{$4=sprintf("%.0f", $4); print}' "$OUT_PATH/gradients.b" > "$OUT_PATH/gradients_rounded.b"

    # Run eddy QC
    echo "Running eddy QC..."
    rm -rf "$OUT_PATH/dwi_eddycorr.qc"
    eddy_quad "$OUT_PATH/dwi_eddycorr" -idx "$OUT_PATH/eddy_index.txt" -par "$OUT_PATH/eddy_acqp.txt" \
    -m "$BRAIN_MASK" -b "$BVAL" -g "$EDDY_ROTATED_BVECS" -j "$CLEAN_JSON"

    # extract b0
    dwiextract "$OUT_PATH/dwi_final.mif" -bzero - | mrmath - mean -axis 3 "$OUT_PATH/final_b0.nii.gz" -force
    dwiextract "$OUT_PATH/dwi_final.mif" -no_bzero - | mrmath - mean -axis 3 "$OUT_PATH/final_b1000.nii.gz" -force 

    fslmaths "$OUT_PATH/final_b0.nii.gz" -mul "${BRAIN_MASK}" "$OUT_PATH/final_b0_masked.nii.gz"
    fslmaths "$OUT_PATH/final_b1000.nii.gz" -mul "${BRAIN_MASK}" "$OUT_PATH/final_b1000_masked.nii.gz"

    echo "✅ Finished preprocessing: ${ACQ_ID}"

done