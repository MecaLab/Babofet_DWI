import os
import sys
import glob
import argparse
import numpy as np
import pandas as pd
import nibabel as nib
from skimage.metrics import structural_similarity as ssim


def get_nonzero_bval_indices(grad_file_path):
    """
    Reads b-values from an MRtrix .b gradient file (format: x y z b).
    Safely ignores headers, comments, or non-numeric lines.
    Returns the indices of the volumes where b-value > 0.
    """
    bvals = []
    with open(grad_file_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 4:
                try:
                    # Try to convert the 4th column to a float
                    b_val = float(parts[3])
                    bvals.append(b_val)
                except ValueError:
                    # Skip lines that are text/headers (e.g., file paths or commands)
                    continue
                
    return [i for i, b in enumerate(bvals) if int(b) != 0]


def count_edge_voxels(mask_data):
    """
    Counts the number of non-zero voxels on the 6 outer boundaries of the 3D volume.
    """
    edge_counts = 0
    for axis in range(3):
        edge_counts += np.count_nonzero(mask_data.take(indices=0, axis=axis))
        edge_counts += np.count_nonzero(mask_data.take(indices=-1, axis=axis))
    return edge_counts


def compute_ssim(dwi_path, grad_file_path, mask_path=None, use_mask=False):
    vol = nib.load(dwi_path).get_fdata()
    idxs = get_nonzero_bval_indices(grad_file_path)

    if not idxs or len(idxs) < 2:
        return np.nan

    ref_idx = idxs[0]
    target_idxs = idxs[1:]
    num_slices = vol.shape[2]
    ssim_scores = []

    if use_mask:
        if mask_path is None:
            raise ValueError("Mask path must be provided when use_mask=True.")
        mask = nib.load(mask_path).get_fdata().astype(bool)
        if mask.shape != vol.shape[:3]:
            raise ValueError("Mask shape does not match DWI spatial dimensions.")

    for tgt_idx in target_idxs:
        for z in range(num_slices):
            ref_slice = vol[:, :, z, ref_idx]
            tgt_slice = vol[:, :, z, tgt_idx]

            if use_mask:
                mask_slice = mask[:, :, z]
                if np.count_nonzero(mask_slice) < 10:
                    continue

                ref_vals = ref_slice[mask_slice]
                data_range = ref_vals.max() - ref_vals.min()
                if data_range == 0:
                    continue

                _, ssim_map = ssim(ref_slice, tgt_slice, full=True, data_range=data_range)
                masked_ssim = ssim_map[mask_slice]
                ssim_scores.append(masked_ssim.mean())
            else:
                data_range = ref_slice.max() - ref_slice.min()
                if data_range == 0:
                    continue
                score, _ = ssim(ref_slice, tgt_slice, full=True, data_range=data_range)
                ssim_scores.append(score)

    return np.mean(ssim_scores) if ssim_scores else np.nan


def get_best_stack(subject, session, output_dir, mask_dir, use_mask=False):
    results = []
    
    # Locate all preprocessed eddy-corrected DWI files in the output directory
    search_pattern = os.path.join(output_dir, f"{subject}_{session}_*_dwi_eddycorr.nii.gz")
    preprocessed_files = sorted(glob.glob(search_pattern))

    if not preprocessed_files:
        print(f"Error: No preprocessed files found matching pattern {search_pattern}", file=sys.stderr)
        sys.exit(1)

    for dwi_path in preprocessed_files:
        # Extract the basename
        filename = os.path.basename(dwi_path)
        basename = filename.replace('_dwi_eddycorr.nii.gz', '')
        
        # Determine associated files dynamically
        grad_path = os.path.join(output_dir, f"{basename}_gradients_rounded.b")
        mask_path = os.path.join(mask_dir, f"{basename}_desc-brain_mask.nii.gz")

        # Validate existence
        if not os.path.exists(grad_path):
            print(f"Skipping {basename} — Gradients file not found.", file=sys.stderr)
            continue
        if not os.path.exists(mask_path):
            print(f"Skipping {basename} — Mask not found.", file=sys.stderr)
            continue

        # 1. Boundary checking logic
        mask_data = nib.load(mask_path).get_fdata()
        edge_voxels = count_edge_voxels(mask_data)
        touches_border = edge_voxels > 0

        # 2. SSIM Logic
        ssim_score = compute_ssim(dwi_path, grad_path, mask_path if use_mask else None, use_mask=use_mask)

        results.append({
            'stack': basename,
            'ssim': ssim_score,
            'edge_voxels': edge_voxels,
            'touches_border': touches_border
        })

    if not results:
        print("Error: No valid preprocessed stacks were fully evaluated.", file=sys.stderr)
        sys.exit(1)

    df_results = pd.DataFrame(results)
    
    # Save the evaluation metrics to CSV
    csv_path = os.path.join(output_dir, f"{subject}_{session}_ssim_stacks.csv")
    df_results.to_csv(csv_path, index=False)

    # Sort logic: 
    # 1. touches_border=False comes before touches_border=True
    # 2. Highest SSIM comes first
    df_sorted = df_results.sort_values(by=['touches_border', 'ssim'], ascending=[True, False])

    # Return the exact basename of the best stack
    return df_sorted.iloc[0]['stack']


def main():
    parser = argparse.ArgumentParser(description="Find the best reference stack based on SSIM and FOV boundaries on preprocessed data.")
    parser.add_argument("--subject", type=str, required=True, help="Subject ID (e.g., sub-01)")
    parser.add_argument("--session", type=str, required=True, help="Session ID (e.g., ses-01)")
    parser.add_argument("--output-dir", type=str, required=True, help="Directory containing the preprocessed eddy corrected DWI files")
    parser.add_argument("--mask-dir", type=str, required=True, help="Directory containing the nnU-Net brain masks")
    parser.add_argument("--use-mask", action="store_true", help="Use brain mask for SSIM computation")

    args = parser.parse_args()
    
    best_stack = get_best_stack(
        subject=args.subject,
        session=args.session,
        output_dir=args.output_dir,
        mask_dir=args.mask_dir,
        use_mask=args.use_mask
    )
    
    # Strictly print ONLY the stack name so Bash can capture it into a variable
    print(best_stack)


if __name__ == "__main__":
    main()