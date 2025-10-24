import os
import argparse
import numpy as np
import pandas as pd
import nibabel as nib
from tqdm import tqdm
from skimage.metrics import structural_similarity as ssim


def get_nonzero_bval_indices(bvals_path):
    with open(bvals_path, 'r') as f:
        bvals = list(map(int, f.read().strip().split()))
    return [i for i, b in enumerate(bvals) if b != 0]


def compute_ssim(dwi_path, bvals_path, mask_path=None, use_mask=False):
    vol = nib.load(dwi_path).get_fdata()
    idxs = get_nonzero_bval_indices(bvals_path)

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


def get_least_motion_corrupted_stack(base_path, use_mask=False):
    results = []

    for stack in os.listdir(base_path):
        bval = os.path.join(base_path.replace('02_preprocessed_stacks', '01_prepared_stacks'), stack, 'dwi.bval')
        raw = os.path.join(base_path, stack, 'dwi_eddycorr.nii.gz')
        mask = os.path.join(base_path, stack, 'brain_mask.nii.gz')

        if use_mask and not os.path.exists(mask):
            print(f"Skipping {stack} — mask not found.")
            continue

        ssim_score = compute_ssim(raw, bval, mask if use_mask else None, use_mask=use_mask)

        results.append({
            'stack': stack,
            'ssim': ssim_score
        })

    df_results = pd.DataFrame(results)
    df_results.to_csv(os.path.join(base_path.replace('02_preprocessed_stacks', '03_registration'), 'ssim_stacks.csv'), index=False)

    # Filter only axial acquisitions
    df_ax = df_results[df_results['stack'].str.contains('acq-ax')]

    # Return the stack with the highest SSIM among axial acquisitions
    return df_ax.sort_values('ssim', ascending=False)['stack'].iloc[0]


def main():
    parser = argparse.ArgumentParser(description="Find the stack with the highest SSIM among DWI volumes.")
    parser.add_argument("base_path", type=str, help="Path to the folder containing preprocessed stacks")
    parser.add_argument("--use-mask", action="store_true", help="Use brain mask for SSIM computation")

    args = parser.parse_args()
    best_stack = get_least_motion_corrupted_stack(args.base_path, use_mask=args.use_mask)
    print(best_stack)


if __name__ == "__main__":
    main()
