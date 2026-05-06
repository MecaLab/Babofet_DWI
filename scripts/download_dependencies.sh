#!/bin/bash
set -e

echo "========================================="
echo "Downloading Babofet Dependencies..."
echo "========================================="

mkdir -p sif_images
mkdir -p tools/nnunet

# URLs (REPLACE THESE WITH YOUR ACTUAL HOSTED URLs)
MIRTK_URL="https://amubox.univ-amu.fr/public.php/dav/files/X8BE6Y4b2xngaKD/?accept=zip"
SVRTK_URL="https://amubox.univ-amu.fr/public.php/dav/files/Fce9zjkqBQXTaik/?accept=zip"
NNUNET_MODEL_URL="https://amubox.univ-amu.fr/public.php/dav/files/LBQ9d2LakiPqC5w/?accept=zip"

# Function to check and download
download_if_missing() {
    local file_path=$1
    local url=$2
    if [ ! -f "$file_path" ]; then
        echo "Downloading $(basename "$file_path")..."
        wget -O "$file_path" "$url"
    else
        echo "✅ $(basename "$file_path") already exists. Skipping."
    fi
}

download_if_missing "sif_images/mirtk.sif" "$MIRTK_URL"
download_if_missing "sif_images/svrtk.sif" "$SVRTK_URL"
download_if_missing "tools/nnunet/BaboonsDiffusion_nnunet.zip" "$NNUNET_MODEL_URL"

# Extract nnU-Net model if needed
if [ ! -d "tools/nnunet/Dataset002_BaboonsDiffusion" ]; then
    echo "Extracting nnU-Net model..."
    unzip -q tools/nnunet/BaboonsDiffusion_nnunet.zip -d tools/nnunet/
fi

chmod +x tools/c3d_affine_tool

echo "========================================="
echo "All dependencies downloaded successfully!"
echo "========================================="