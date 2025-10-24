import os
import sys
import nibabel as nib
import numpy as np

mask_dir = sys.argv[1]

results = []

for acq in os.listdir(mask_dir):
    if not acq.startswith("acq-ax"):
        continue  # only axial acquisitions

    acq_path = os.path.join(mask_dir, acq)

    # find nifti
    for f in os.listdir(acq_path):
        if f.endswith(".nii.gz"):
            mask_file = os.path.join(acq_path, f)
            break

    mask_data = nib.load(mask_file).get_fdata()

    # compute edge voxels
    edge_counts = []
    for axis in range(3):
        edge_counts.append(np.count_nonzero(mask_data.take(indices=0, axis=axis)))
        edge_counts.append(np.count_nonzero(mask_data.take(indices=-1, axis=axis)))
    total_edge_voxels = sum(edge_counts)

    results.append((acq, total_edge_voxels))

# pick best (lowest edge voxels)
best_acq = min(results, key=lambda x: x[1])
print(best_acq[0])
