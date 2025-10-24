#!/bin/bash
set -e -u -o pipefail

TENSOR_DIR="${DERIVATIVES_DIR}/07_tensor_fitting"
PARCELLATION_DIR="${DERIVATIVES_DIR}/08_mask_propagation"

QC_DIR="${DERIVATIVES_DIR}/99_qc"
mkdir -p "$QC_DIR"

FA="${TENSOR_DIR}/tensor_fa.nii.gz"
ADC="${TENSOR_DIR}/tensor_adc.nii.gz"
VEC="${TENSOR_DIR}/tensor_v1.nii.gz"

PARCELLATIONS="${PARCELLATION_DIR}/tissue_segmentation_in_dwi.nii.gz"


# mask lightbox
LABEL_MASK_TMP=$(mktemp -p "$QC_DIR" --suffix=.nii.gz)
fslmaths "$PARCELLATIONS" -thr 3 -uthr 3 -bin "$LABEL_MASK_TMP"

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/cortex_axial.png" \
    -sz 2400 1200  -hc -hl -zx z \
    -zr 0.2 0.8 \
    "$ADC" -ot volume -cm greyscale \
    -dr 0 0.003 \
    "$LABEL_MASK_TMP" -ot mask --maskColour 1 0 0 -a 30

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/cortex_coronal.png" \
    -sz 2400 1200  -hc -hl -zx y \
    -zr 0.2 0.8 \
    "$ADC" -ot volume -cm greyscale \
    -dr 0 0.003 \
    "$LABEL_MASK_TMP" -ot mask --maskColour 1 0 0 -a 30

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/cortex_sagittal.png" \
    -sz 2400 1200  -hc -hl -zx x \
    -zr 0.2 0.8 \
    "$ADC" -ot volume -cm greyscale \
    -dr 0 0.003 \
    "$LABEL_MASK_TMP" -ot mask --maskColour 1 0 0 -a 30

rm "$LABEL_MASK_TMP"



# fa lightbox
PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_fa_axial.png" \
    -sz 2400 1200  -hc -hl -zx z \
    -zr 0.2 0.8 \
    "$FA" -ot volume -cm greyscale \
    -dr 0 1 

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_fa_coronal.png" \
    -sz 2400 1200  -hc -hl -zx y \
    -zr 0.2 0.8 \
    "$FA" -ot volume -cm greyscale \
    -dr 0 1 

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_fa_sagittal.png" \
    -sz 2400 1200  -hc -hl -zx x \
    -zr 0.2 0.8 \
    "$FA" -ot volume -cm greyscale \
    -dr 0 1 




# md lightbox
PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_adc_axial.png" \
    -sz 2400 1200  -hc -hl -zx z \
    -zr 0.2 0.8 \
    "$ADC" -ot volume -cm greyscale \
    -dr 0 0.003

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_adc_coronal.png" \
    -sz 2400 1200  -hc -hl -zx y \
    -zr 0.2 0.8 \
    "$ADC" -ot volume -cm greyscale \
    -dr 0 0.003

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_adc_sagittal.png" \
    -sz 2400 1200  -hc -hl -zx x \
    -zr 0.2 0.8 \
    "$ADC" -ot volume -cm greyscale \
    -dr 0 0.003




# vec lightbox
PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_vec_axial.png" \
    -sz 2400 1200  -hc -hl -zx z \
    -zr 0.2 0.8 \
    "$VEC" -ot rgbvector \
    -b 60 -c 70 

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_vec_coronal.png" \
    -sz 2400 1200  -hc -hl -zx y \
    -zr 0.2 0.8 \
    "$VEC" -ot rgbvector \
    -b 60 -c 70 

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_vec_sagittal.png" \
    -sz 2400 1200  -hc -hl -zx x \
    -zr 0.2 0.8 \
    "$VEC" -ot rgbvector \
    -b 60 -c 70 





# cfa lighbox
PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_cfa_axial.png" \
    -sz 2400 1200  -hc -hl -zx z \
    -zr 0.2 0.8 \
    "$FA" -ot volume \
    "$VEC" -ot rgbvector -b 80 -c 85 -mo "$FA"

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_cfa_coronal.png" \
    -sz 2400 1200  -hc -hl -zx y \
    -zr 0.2 0.8 \
    "$FA" -ot volume \
    "$VEC" -ot rgbvector -b 80 -c 85 -mo "$FA"

PYTHONWARNINGS=ignore MPLBACKEND=Agg render \
    --scene lightbox -of "$QC_DIR/snapshot_lightbox_cfa_sagittal.png" \
    -sz 2400 1200  -hc -hl -zx x \
    -zr 0.2 0.8 \
    "$FA" -ot volume \
    "$VEC" -ot rgbvector -b 80 -c 85 -mo "$FA"

