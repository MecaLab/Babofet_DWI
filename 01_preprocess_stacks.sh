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

detected_stacks=( $(ls "${SESSION_RAW_DATA_DIR}"/${SUBJECT_ID}_${SESSION_ID}_*run-*_dwi.nii.gz 2>/dev/null | sort) )

for file_path in "${detected_stacks[@]}"; do

    filename=$(basename "$file_path" .nii.gz)  # e.g., sub-01_ses-01_dir-AP_run-01_dwi
    basename=${filename%_dwi}                  # e.g., sub-01_ses-01_dir-AP_run-01
    basename_fmap=${basename//dir-AP/dir-PA}   # e.g., sub-01_ses-01_dir-PA_run-01

    if [[ " ${EXCLUDE_RUNS[*]} " == *" ${basename} "* ]]; then
        echo "Skipping excluded run: ${basename}"
        continue
    fi

    echo "Processing Acquisition: ${basename}"

    RAW_NII="${SESSION_RAW_DATA_DIR}/${basename}_dwi.nii.gz"
    RAW_BVEC="${SESSION_RAW_DATA_DIR}/${basename}_dwi.bvec"
    RAW_BVAL="${SESSION_RAW_DATA_DIR}/${basename}_dwi.bval"
    RAW_JSON="${SESSION_RAW_DATA_DIR}/${basename}_dwi.json"

    RAW_FMAP_NII="${SESSION_FMAP_DATA_DIR}/${basename_fmap}_epi.nii.gz"
    RAW_FMAP_JSON="${SESSION_FMAP_DATA_DIR}/${basename_fmap}_epi.json"

    SLICES=$(python3 -c "import nibabel as nib; print(nib.load('$RAW_NII').shape[2])")
    EVEN=1
    if (( SLICES % 2 != 0 )); then
        EVEN=0
    fi 

    mrconvert \
        "$RAW_NII" \
        "$OUTPUT_DIR/${basename}.mif" \
        -fslgrad "$RAW_BVEC" "$RAW_BVAL" \
        -json_import "$RAW_JSON" \
        -export_pe_eddy "$OUTPUT_DIR/${basename}_eddy_acqp.txt" "$OUTPUT_DIR/${basename}_eddy_index.txt" \
        -force

    # --- DENOISING AND DEGIBBSING AP ---
    dwidenoise \
        "$OUTPUT_DIR/${basename}.mif" \
        "$OUTPUT_DIR/${basename}_denoised.mif" \
        -noise "$OUTPUT_DIR/${basename}_noise.nii.gz" \
        -force

    mrconvert \
        "$OUTPUT_DIR/${basename}_denoised.mif" \
        "$OUTPUT_DIR/${basename}_denoised.nii.gz" \
        -force

    mrdegibbs \
        "$OUTPUT_DIR/${basename}_denoised.mif" \
        "$OUTPUT_DIR/${basename}_degibbsed.mif" \
        -force

    mrconvert \
        "$OUTPUT_DIR/${basename}_degibbsed.mif" \
        "$OUTPUT_DIR/${basename}_degibbsed.nii.gz" \
        -force


    # --- EXTRACT B0 and B1000 MEAN IMAGES ---
    dwiextract \
        "$OUTPUT_DIR/${basename}_degibbsed.mif"  -bzero - | \
        mrmath - mean -axis 3 "$OUTPUT_DIR/${basename}_b0_denoised.nii.gz" -force


    dwiextract \
        "$OUTPUT_DIR/${basename}_degibbsed.mif" -no_bzero - | \
        mrmath - mean -axis 3 "$OUTPUT_DIR/${basename}_b1000_denoised.nii.gz" -force


    # if brain mask exists, use it, otherwise create one with nnunet
    BRAIN_MASK="${DERIVATIVES_DIR}/svrtk/${SUBJECT_ID}/${SESSION_ID}/dwi/${basename}_desc-brain_mask.nii.gz"

    if [[ -f "$BRAIN_MASK" ]]; then
        echo "Using existing brain mask: $BRAIN_MASK"
    else
        echo "No brain mask found for ${basename}. Generating with nnU-Net..."

        eval "$ACTIVATE_ENV"

        python3 scripts/nnunet_brainmask.py \
            -i "$OUTPUT_DIR/${basename}_b0_denoised.nii.gz" \
            -o "$BRAIN_MASK" \
            --device "cpu"
            
        eval "$ACTIVATE_ENV"
    fi


    # --- DILATE BRAIN MASK ---
    DILATED_BRAIN_MASK="$OUTPUT_DIR/${basename}_dilated_brain_mask.nii.gz"
    DILATED2_BRAIN_MASK="$OUTPUT_DIR/${basename}_dilated2_brain_mask.nii.gz"
    fslmaths "${BRAIN_MASK}" -kernel 3D -dilM "${DILATED_BRAIN_MASK}"
    fslmaths "${DILATED_BRAIN_MASK}" -kernel 2D -dilM "${DILATED2_BRAIN_MASK}"


    # --- TOPUP (if fmap exists) ---
    TOPUP_OUTPUT_BASENAME="$OUTPUT_DIR/${basename}_topup_results"

    DWI_AP_DIR=$(jq -r '.PhaseEncodingDirection' "$RAW_JSON")
    DWI_AP_READOUT=$(jq -r '.TotalReadoutTime' "$RAW_JSON")

    if [[ -n "$RAW_FMAP_JSON" && -f "$RAW_FMAP_JSON" ]]; then

        # extact original b0 from both AP and PA (no preprocessing)
        dwiextract \
            "$OUTPUT_DIR/${basename}.mif" -bzero - | \
             mrmath - mean -axis 3 "$OUTPUT_DIR/${basename}_b0_original.nii.gz" -force

        # merge AP bo and PA b0
        mrcat \
            "$OUTPUT_DIR/${basename}_b0_original.nii.gz" \
            "$RAW_FMAP_NII" \
            "$OUTPUT_DIR/${basename}_b0_pair.nii.gz" \
            -force

        # creat acqp file for topup
        DWI_PA_DIR=$(jq -r '.PhaseEncodingDirection' "$RAW_FMAP_JSON")
        DWI_PA_READOUT=$(jq -r '.TotalReadoutTime' "$RAW_FMAP_JSON")

        # Convert i,j,k to FSL format
        declare -A pe_vectors=( ["i"]="1 0 0" ["i-"]="-1 0 0" ["j"]="0 1 0" ["j-"]="0 -1 0" ["k"]="0 0 1" ["k-"]="0 0 -1" )
        
        echo "${pe_vectors[$DWI_AP_DIR]} ${DWI_AP_READOUT}" > "$OUTPUT_DIR/${basename}_topup_acqp.txt"
        echo "${pe_vectors[$DWI_PA_DIR]} ${DWI_PA_READOUT}" >> "$OUTPUT_DIR/${basename}_topup_acqp.txt"

        if [ "$EVEN" -eq 0 ]; then
            config_file="b02b0_1.cnf"
        else
            config_file="b02b0.cnf"
        fi

        # run topup
        echo "Running topup..."
        topup \
            --imain="$OUTPUT_DIR/${basename}_b0_pair.nii.gz" \
            --datain="$OUTPUT_DIR/${basename}_topup_acqp.txt" \
            --config="$config_file" \
            --out="${TOPUP_OUTPUT_BASENAME}" \
            --iout="$OUTPUT_DIR/${basename}_b0_pair_unwarped.nii.gz" \
            --fout="$OUTPUT_DIR/${basename}_topup_field.nii.gz" \
            --nthr=64

        TOPUP_ENABLED=true
    else
        echo "WARNING: No corresponding fmap found for ${basename}. Skipping topup."
        TOPUP_ENABLED=false
    fi

    # --- BIAS FIELD CORRECTION ---

    N4_CORRECTED_B0="$OUTPUT_DIR/${basename}_b0_n4corrected.nii.gz"
    N4_INITIAL_BIAS_FIELD="$OUTPUT_DIR/${basename}_b0_initial_bias_field.nii.gz"
    N4_FINAL_BIAS_FIELD="$OUTPUT_DIR/${basename}_b0_final_bias_field.nii.gz"

    N4BiasFieldCorrection \
        -d 3 \
        -i "$OUTPUT_DIR/${basename}_b0_denoised.nii.gz" \
        -w "$BRAIN_MASK" \
        -o "[$N4_CORRECTED_B0,$N4_INITIAL_BIAS_FIELD]" \
        -s 2 -b [100,3] -c [1000,0.0]

     # Compute the sum of intensities inside the mask before and after N4
    S_ORIG=$(mrcalc "$OUTPUT_DIR/${basename}_b0_denoised.nii.gz" "$BRAIN_MASK" -mult - | mrmath - sum - -axis 0 | mrmath - sum - -axis 1 | mrmath - sum - -axis 2 | mrdump - | awk '{print $1}')
    S_CORR=$(mrcalc "$N4_CORRECTED_B0" "$BRAIN_MASK" -mult - | mrmath - sum - -axis 0 | mrmath - sum - -axis 1 | mrmath - sum - -axis 2 | mrdump - | awk '{print $1}')

    # Calculate the global intensity scaling factor
    SCALE=$(LC_NUMERIC=C awk "BEGIN {printf \"%.6f\", $S_ORIG == 0 ? 1.0 : $S_CORR / $S_ORIG}")

    echo "Original intensity sum: $S_ORIG"
    echo "Corrected intensity sum: $S_CORR"
    echo "Global intensity scale factor: $SCALE"

    # Scale the initial bias field to create the final, intensity-preserving field
    mrcalc "$N4_INITIAL_BIAS_FIELD" "$SCALE" -mult "$N4_FINAL_BIAS_FIELD" -force
    
    # Apply the final scaled bias field to the full denoised DWI series
    mrcalc "$OUTPUT_DIR/${basename}_degibbsed.mif" "$N4_FINAL_BIAS_FIELD" -div "$OUTPUT_DIR/${basename}_biascorr.mif" -force

    mrconvert \
        "$OUTPUT_DIR/${basename}_biascorr.mif" \
        "$OUTPUT_DIR/${basename}_biascorr.nii.gz" \
        -force


    # --- EDDY CORRECTION ---
    MPORDER=$(python3 -c "import nibabel as nib; print(nib.load('$OUTPUT_DIR/${basename}_biascorr.nii.gz').shape[2] - 1)")
    echo "Using mporder = $MPORDER"

    EDDY_CMD="eddy diffusion \
                --imain=\"$OUTPUT_DIR/${basename}_biascorr.nii.gz\" \
                --mask=\"$DILATED2_BRAIN_MASK\" \
                --index=\"$OUTPUT_DIR/${basename}_eddy_index.txt\" \
                --acqp=\"$OUTPUT_DIR/${basename}_topup_acqp.txt\" \
                --bvecs=\"$RAW_BVEC\" \
                --bvals=\"$RAW_BVAL\" \
                --json=\"$RAW_JSON\" \
                --out=\"$OUTPUT_DIR/${basename}_dwi_eddycorr\" \
                --repol \
                --ol_nstd=4 \
                --nvoxhp=5000 \
                --niter=8 \
                --fwhm=10,8,4,2,0,0,0,0 \
                --ol_type=sw \
                --mporder=${MPORDER} \
                --s2v_niter=8 \
                --s2v_lambda=1 \
                --s2v_interp=spline \
                --data_is_shelled \
                --nthr=64 \
                --cnr_maps \
                --residuals \
                --verbose"

    if [[ "$TOPUP_ENABLED" == true ]]; then
        echo "Running eddy with topup correction..."
        EDDY_CMD+=" --topup=\"${TOPUP_OUTPUT_BASENAME}\" \
                    --estimate_move_by_susceptibility \
                    --mbs_niter=20 \
                    --mbs_ksp=10 \
                    --mbs_lambda=10"
    else          
   
        echo "Estimating distortion field with T2..."

        # extract the b0
        dwiextract \
            "$OUTPUT_DIR/${basename}_biascorr.mif" -bzero - | \
             mrmath - mean -axis 3 "$OUTPUT_DIR/${basename}_b0_for_T2.nii.gz" -force

        fslmaths "$OUTPUT_DIR/${basename}_b0_for_T2.nii.gz" -mul "${BRAIN_MASK}" "$OUTPUT_DIR/${basename}_b0_for_T2_masked.nii.gz"

        # flirt T2 to b0
        flirt \
            -in $T2W_RECONSTRUCTED \
            -ref "$OUTPUT_DIR/${basename}_b0_for_T2_masked.nii.gz" \
            -out "$OUTPUT_DIR/${basename}_T2_to_b0_flirt.nii.gz" \
            -omat "$OUTPUT_DIR/${basename}_T2_to_b0_flirt.mat" \
            -dof 6 \
            -bins 64 \
            -interp spline \
            -searchrx -180 180 -searchry -180 180 -searchrz -180 180 \

        flirt \
            -in $T2W_RECONSTRUCTED_MASK \
            -ref "$OUTPUT_DIR/${basename}_b0_for_T2_masked.nii.gz" \
            -out "$OUTPUT_DIR/${basename}_T2_in_b0_mask.nii.gz" \
            -init "$OUTPUT_DIR/${basename}_T2_to_b0_flirt.mat" \
            -applyxfm \
            -interp nearestneighbour

        # fnirt b0 to registered T2
        fnirt \
            --ref="$OUTPUT_DIR/${basename}_T2_to_b0_flirt.nii.gz" \
            --in="$OUTPUT_DIR/${basename}_b0_for_T2_masked.nii.gz" \
            --refmask="$OUTPUT_DIR/${basename}_T2_in_b0_mask.nii.gz" \
            --inmask="${BRAIN_MASK}" \
            --iout="$OUTPUT_DIR/${basename}_fnirt_non_linear_Image.nii.gz" \
            --cout="$OUTPUT_DIR/${basename}_fnirt_non_linear_warpcoef.nii.gz" \
            --fout="$OUTPUT_DIR/${basename}_fnirt_non_linear_field.nii.gz" \
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

        fslsplit "$OUTPUT_DIR/${basename}_fnirt_non_linear_field.nii.gz" "$OUTPUT_DIR/${basename}_fnirt_non_linear_field_comp" -t
        fslmaths "$OUTPUT_DIR/${basename}_fnirt_non_linear_field_comp0000.nii.gz" -mul 0 "$OUTPUT_DIR/${basename}_zero.nii.gz"

        if [ "${DWI_AP_DIR}" == "i" ] || [ "${DWI_AP_DIR}" == "i-" ]; then
            DISP_FIELD_COMPONENT="$OUTPUT_DIR/${basename}_fnirt_non_linear_field_comp0000.nii.gz"
            fslmerge \
                -t "$OUTPUT_DIR/${basename}_fnirt_non_linear_field_PE.nii.gz" \
                $DISP_FIELD_COMPONENT \
                "$OUTPUT_DIR/${basename}_zero.nii.gz" \
                "$OUTPUT_DIR/${basename}_zero.nii.gz"

        elif [ "${DWI_AP_DIR}" == "j" ] || [ "${DWI_AP_DIR}" == "j-" ]; then
            DISP_FIELD_COMPONENT="$OUTPUT_DIR/${basename}_fnirt_non_linear_field_comp0001.nii.gz"
            fslmerge \
                -t "$OUTPUT_DIR/${basename}_fnirt_non_linear_field_PE.nii.gz" \
                "$OUTPUT_DIR/${basename}_zero.nii.gz" \
                $DISP_FIELD_COMPONENT \
                "$OUTPUT_DIR/${basename}_zero.nii.gz"

        elif [ "${DWI_AP_DIR}" == "k" ] || [ "${DWI_AP_DIR}" == "k-" ]; then
            DISP_FIELD_COMPONENT="$OUTPUT_DIR/${basename}_fnirt_non_linear_field_comp0002.nii.gz"
            fslmerge \
                -t "$OUTPUT_DIR/${basename}_fnirt_non_linear_field_PE.nii.gz" \
                "$OUTPUT_DIR/${basename}_zero.nii.gz" \
                "$OUTPUT_DIR/${basename}_zero.nii.gz" \
                $DISP_FIELD_COMPONENT
        fi

        # convert field in hz
        OFF_RESONANCE_FIELD="$OUTPUT_DIR/${basename}_off_resonance_field_hz.nii.gz"
        if [[ $DWI_AP_DIR == *"-"* ]]; then
            # For negative PE directions (e.g., 'j-'), the sign is typically correct as is.
            fslmaths "${DISP_FIELD_COMPONENT}" -div "${DWI_AP_READOUT}" -mul -1 "${OFF_RESONANCE_FIELD}"
        else
            # For positive PE directions (e.g., 'j'), you often need to invert the sign.
            fslmaths "${DISP_FIELD_COMPONENT}" -div "${DWI_AP_READOUT}" "${OFF_RESONANCE_FIELD}"
        fi

        # apply warp field to data for QC
        applywarp \
            -i "$OUTPUT_DIR/${basename}_b0_for_T2.nii.gz" \
            -r "$OUTPUT_DIR/${basename}_T2_to_b0_flirt.nii.gz" \
            -w "$OUTPUT_DIR/${basename}_fnirt_non_linear_field_PE.nii.gz" \
            -o "$OUTPUT_DIR/${basename}_b0_for_T2_distorted_PE.nii.gz"  \
            --interp=spline

        # call eddy with field
        EDDY_CMD+=" --field=${OUTPUT_DIR}/${basename}_off_resonance_field_hz \
                    --estimate_move_by_susceptibility \
                    --mbs_niter=20 \
                    --mbs_ksp=10 \
                    --mbs_lambda=10"
    fi
    
    # Execute the constructed eddy command
    eval $EDDY_CMD

    # the interpolation with eddy uses spline, negative number can appear, set them to zero
    fslmaths "$OUTPUT_DIR/${basename}_dwi_eddycorr.nii.gz" -thr 0 "$OUTPUT_DIR/${basename}_dwi_eddycorr.nii.gz"

    # --- Final Image and Gradient Extraction ---
    EDDY_ROTATED_BVECS="$OUTPUT_DIR/${basename}_dwi_eddycorr.eddy_rotated_bvecs"
    mrconvert "$OUTPUT_DIR/${basename}_dwi_eddycorr.nii.gz" \
              "$OUTPUT_DIR/${basename}_dwi_final.mif" \
              -fslgrad "$EDDY_ROTATED_BVECS" "$RAW_BVAL" \
              -json_import "$RAW_JSON" \
              -export_grad_mrtrix "$OUTPUT_DIR/${basename}_gradients.b" \
              -force

    awk 'NR==1{print}; NR>1{$4=sprintf("%.0f", $4); print}' "$OUTPUT_DIR/${basename}_gradients.b" > "$OUTPUT_DIR/${basename}_gradients_rounded.b"

    # Run eddy QC
    echo "Running eddy QC..."
    rm -rf "$OUTPUT_DIR/${basename}_dwi_eddycorr.qc"
    eddy_quad \
        "$OUTPUT_DIR/${basename}_dwi_eddycorr" \
        -idx "$OUTPUT_DIR/${basename}_eddy_index.txt" \
        -par "$OUTPUT_DIR/${basename}_eddy_acqp.txt" \
        -m "$BRAIN_MASK" \
        -b "$RAW_BVAL" \
        -g "$EDDY_ROTATED_BVECS" \
        -j "$RAW_JSON"

    # extract b0
    dwiextract "$OUTPUT_DIR/${basename}_dwi_final.mif" -bzero - | mrmath - mean -axis 3 "$OUTPUT_DIR/${basename}_final_b0.nii.gz" -force
    dwiextract "$OUTPUT_DIR/${basename}_dwi_final.mif" -no_bzero - | mrmath - mean -axis 3 "$OUTPUT_DIR/${basename}_final_b1000.nii.gz" -force 

    echo "✅ Finished preprocessing: ${basename}"

done