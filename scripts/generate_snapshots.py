import os
import nibabel as nib
import subprocess

reconstruction_path = "/envau/work/meca/data/babofetDiffusion/BIDS/derivatives/reconstruction_08mm/"
output_path = "/envau/work/meca/data/babofetDiffusion/BIDS/derivatives/snapshots/"
os.makedirs(output_path, exist_ok=True)

subs = sorted(os.listdir(reconstruction_path))
for sub in subs:
    sub_path = os.path.join(reconstruction_path, sub)
    sessions = sorted(os.listdir(sub_path))

    for ses in sessions:
        ses_path = os.path.join(sub_path, ses)

        dwi_file = os.path.join(ses_path, "07_tensor_fitting", "mean_dwi_target.nii.gz")
        snapshot_filename = f"{sub}_{ses}_dwi_recon.png"
        snapshot_path = os.path.join(output_path, snapshot_filename)

        if not os.path.exists(dwi_file):
            print(f"❌ File not found: {dwi_file}")
            continue

        img = nib.load(dwi_file)
        shape = img.header.get_data_shape()
        mid_x, mid_y, mid_z = shape[0] // 2, shape[1] // 2, shape[2] // 2

        command = [
            'render',
            '--scene', 'ortho',
            '--layout', 'vertical',
            '-of', snapshot_path,
            '-hl', '-hc',
            '-sz', '600', '1201',
            '-vl', str(mid_x), str(mid_y), str(mid_z),
            dwi_file,
            '-ot', 'volume',
            '-b', '50',
            '-c', '50'
        ]

        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"Snapshot created: {snapshot_path}")

