#!/usr/bin/env python3

import os
import sys
import nibabel as nib
import numpy as np

def pad_nifti_slices(input_path, output_path, target_slices, mode):
    """
    Pads or crops a 3D or 4D NIfTI image to a target number of slices,
    correctly adjusting the NIfTI affine matrix to maintain spatial registration.

    The padding/cropping is applied symmetrically to the 3rd dimension (z-axis).

    Args:
        input_path (str): Path to the input NIfTI file.
        output_path (str): Path where the modified NIfTI file will be saved.
        target_slices (int): The desired number of slices in the z-dimension.
        mode (str): The padding mode. Can be 'edge' or 'zero'.
                    - 'edge': Pads by replicating the edge slices.
                    - 'zero': Pads with constant zero values.
    """
    try:
        img = nib.load(input_path)
        data = img.get_fdata()
        header = img.header.copy()
        affine = img.affine.copy()

        folder_name = os.path.basename(os.path.dirname(input_path))
        
        current_slices = data.shape[2]
        
        if current_slices == target_slices:
            print(f"Image '{folder_name}' already has {current_slices} slices. No changes needed. Copying to output.")
            nib.save(img, output_path)
            return

        # --- Calculate padding or cropping amounts ---
        delta = target_slices - current_slices
        pad_before = delta // 2
        pad_after = delta - pad_before
        
        # This single calculation works for both padding (delta > 0) and cropping (delta < 0)
        # For cropping, pad_before/pad_after will be negative.

        if delta > 0: # Padding
            print(f"Padding '{folder_name}' from {current_slices} to {target_slices} slices using '{mode}' mode...")
            pad_width = [(0, 0)] * data.ndim
            pad_width[2] = (pad_before, pad_after)
            
            if mode == 'edge':
                modified_data = np.pad(data, pad_width, mode='edge')
            elif mode == 'zero':
                modified_data = np.pad(data, pad_width, mode='constant', constant_values=0)
            else:
                raise ValueError(f"Unknown padding mode: '{mode}'. Must be 'edge' or 'zero'.")
        
        else: # Cropping
            crop_before = -pad_before
            crop_after = -pad_after
            print(f"Cropping '{folder_name}' from {current_slices} to {target_slices} slices...")
            modified_data = data[:, :, crop_before : current_slices - crop_after, ...]

        # --- KEY STEP: Adjust the affine matrix for the shift in the z-origin ---
        # The new origin is shifted by `pad_before` slices along the z-axis vector.
        # For cropping, `pad_before` is negative, correctly shifting the origin forward.
        z_direction_vector = affine[:3, 2]
        origin_offset = z_direction_vector * pad_before
        
        new_affine = affine.copy()
        new_affine[:3, 3] -= origin_offset

        # Create and save the new NIfTI image with the corrected data and affine
        new_img = nib.Nifti1Image(modified_data, new_affine, header)
        nib.save(new_img, output_path)
        print(f"Saved modified image to '{output_path}'")

    except Exception as e:
        print(f"Error processing {folder_name}: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: python pad_nifti_slices.py <input.nii.gz> <output.nii.gz> <target_slices> <mode>", file=sys.stderr)
        print("  mode: 'edge' or 'zero'")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    target = int(sys.argv[3])
    padding_mode = sys.argv[4]
    
    pad_nifti_slices(input_file, output_file, target, padding_mode)