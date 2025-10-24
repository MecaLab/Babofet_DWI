#!/usr/bin/env python3
import os
import sys
import nibabel as nib
import numpy as np

def crop_nifti_slices(input_path, output_path, target_slices):
    """
    Crops a 3D or 4D NIfTI image to a target number of slices (z-dim).

    The cropping is applied symmetrically from the top and bottom edges.
    If the image is already at or smaller than the target size, it is
    simply copied to the output location.

    Args:
        input_path (str): Path to the input NIfTI file.
        output_path (str): Path where the cropped NIfTI file will be saved.
        target_slices (int): The desired final number of slices.
    """
    try:

        folder_name = os.path.basename(os.path.dirname(input_path))

        img = nib.load(input_path)
        data = img.get_fdata()
        header = img.header.copy()

        current_slices = data.shape[2]

        if current_slices <= target_slices:
            print(f"Image '{folder_name}' has {current_slices} slices. No cropping needed. Copying.")
            nib.save(img, output_path)
            return

        crop_total = current_slices - target_slices
        crop_top = crop_total // 2
        crop_bottom = crop_total - crop_top

        start_slice = crop_top
        end_slice = current_slices - crop_bottom

        print(f"Cropping '{folder_name}' from {current_slices} to {target_slices} slices (removing {crop_top} from top, {crop_bottom} from bottom)...")
        
        # Use slicing to extract the central portion. Works for 3D and 4D.
        cropped_data = data[:, :, start_slice:end_slice, ...]
        
        # Create and save the new NIfTI image
        cropped_img = nib.Nifti1Image(cropped_data, img.affine, header)
        nib.save(cropped_img, output_path)
        print(f"Saved cropped image to '{output_path}'")

    except Exception as e:
        print(f"Error processing {folder_name}: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python crop_nifti_slices.py <input.nii.gz> <output.nii.gz> <target_slices>", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    target = int(sys.argv[3])

    crop_nifti_slices(input_file, output_file, target)