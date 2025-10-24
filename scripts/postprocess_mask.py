import nibabel as nib
import numpy as np
from scipy.ndimage import binary_dilation, label
import sys

# --- Arguments ---
input_path = sys.argv[1]  # Input binary mask
iterations = sys.argv[2]
output_path = sys.argv[3]  # Output processed mask

# --- Load binary mask ---
img = nib.load(input_path)
mask = img.get_fdata() > 0


# --- Dilate the mask by 1 voxel in 3D ---
dilated = binary_dilation(mask, iterations=int(iterations))

# --- Label connected components ---
labeled, num_labels = label(dilated)

# --- Keep only the largest connected component ---
if num_labels == 0:
    print("Warning: no connected components found!")
    largest_cc = np.zeros_like(mask)
else:
    counts = np.bincount(labeled.flat)
    counts[0] = 0  # Background
    largest_label = counts.argmax()
    largest_cc = (labeled == largest_label)

# --- Save final mask ---
out_img = nib.Nifti2Image(largest_cc.astype(np.uint8), affine=img.affine, header=img.header)
nib.save(out_img, output_path)
