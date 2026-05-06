import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

# ==========================================
#      HARDCODED NNUNET PATHS
# ==========================================
# Modify these if your directory structure changes
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
NNUNET_BASE = str(PROJECT_ROOT / "tools" / "nnunet")

NNUNET_RAW = f"{NNUNET_BASE}/nnUNet_raw"
NNUNET_PREPROCESSED = f"{NNUNET_BASE}/nnUNet_preprocessed"
NNUNET_RESULTS = NNUNET_BASE
# ==========================================

def get_file_extension(filename):
    """Extracts the file extension, handling multi-part extensions like .nii.gz"""
    if filename.endswith(".nii.gz"):
        return ".nii.gz"
    return Path(filename).suffix

def run_command(command, env=None):
    """Helper to run shell commands and stream the output"""
    print(f"Running: {' '.join(command)}")
    result = subprocess.run(command, env=env, text=True)
    if result.returncode != 0:
        print(f"Error: Command failed with return code {result.returncode}")
        exit(1)

def main():
    parser = argparse.ArgumentParser(description="Run nnU-Net v2 prediction on a single image.")
    
    # User Input/Output
    parser.add_argument("-i", "--input_image", required=True, help="Path to the input image file.")
    parser.add_argument("-o", "--output_mask", required=True, help="Path to save the final output mask file.")
    
    # nnU-Net Specific Arguments 
    parser.add_argument("-d", "--dataset", default="Dataset002_BaboonsDiffusion", help="Dataset name or ID")
    parser.add_argument("-tr", "--trainer", default="nnUNetTrainer_100epochs", help="Trainer class")
    parser.add_argument("-c", "--config", default="3d_fullres", help="nnU-Net configuration")
    parser.add_argument("-p", "--plans", default="nnUNetPlans", help="Plans identifier")
    parser.add_argument("-f", "--folds", nargs="+", default=["0", "1", "2", "3", "4"], help="Folds to use")
    parser.add_argument("--device", default="cpu", help="Device to run inference on (cuda, cpu, mps).")

    args = parser.parse_args()

    # 1. Set up Environment Variables locally for this script's subprocesses
    env = os.environ.copy()
    env["nnUNet_raw"] = NNUNET_RAW
    env["nnUNet_preprocessed"] = NNUNET_PREPROCESSED
    env["nnUNet_results"] = NNUNET_RESULTS

    # 2. Construct precise paths based on your tree output
    base_model_dir = Path(NNUNET_RESULTS) / args.dataset / f"{args.trainer}__{args.plans}__{args.config}"
    crossval_dir = base_model_dir / f"crossval_results_folds_{'_'.join(args.folds)}"
    
    # postprocessing.pkl is inside the crossval folder
    pp_pkl_file = crossval_dir / "postprocessing.pkl"
    # plans.json is one level up, inside the base model folder
    plans_json = base_model_dir / "plans.json"

    # Pre-flight check
    if not pp_pkl_file.exists():
        print(f"Error: Could not find postprocessing file at {pp_pkl_file}")
        exit(1)
    if not plans_json.exists():
        print(f"Error: Could not find plans file at {plans_json}")
        exit(1)

    # 3. Create Temporary Directories for nnU-Net
    with tempfile.TemporaryDirectory() as temp_in_dir, \
         tempfile.TemporaryDirectory() as temp_out_dir, \
         tempfile.TemporaryDirectory() as temp_pp_dir:
        
        # 4. Prepare the Input File
        input_path = Path(args.input_image)
        ext = get_file_extension(input_path.name)
        
        # nnU-Net requires the _0000 suffix for the first input modality
        temp_input_filename = f"scan_0000{ext}" 
        temp_input_path = Path(temp_in_dir) / temp_input_filename
        
        print(f"Copying {input_path} to temporary input folder as {temp_input_filename}...")
        shutil.copy(input_path, temp_input_path)

        # 5. Run Prediction
        predict_cmd = [
            "nnUNetv2_predict",
            "-d", args.dataset,
            "-i", temp_in_dir,
            "-o", temp_out_dir,
            "-f", *args.folds,
            "-tr", args.trainer,
            "-c", args.config,
            "-p", args.plans,
            "-device", args.device
        ]
        print("\n--- Starting nnU-Net Prediction ---")
        run_command(predict_cmd, env=env)

        # 6. Run Post-processing
        pp_cmd = [
            "nnUNetv2_apply_postprocessing",
            "-i", temp_out_dir,
            "-o", temp_pp_dir,
            "-pp_pkl_file", str(pp_pkl_file),
            "-np", "8",
            "-plans_json", str(plans_json)
        ]
        print("\n--- Starting nnU-Net Post-processing ---")
        run_command(pp_cmd, env=env)

        # 7. Retrieve Final Output
        expected_output_filename = f"scan{ext}"
        final_temp_mask = Path(temp_pp_dir) / expected_output_filename

        if final_temp_mask.exists():
            output_dest = Path(args.output_mask)
            output_dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(final_temp_mask, output_dest)
            print(f"\nSuccess! Mask saved to: {output_dest}")
        else:
            print(f"\nError: Prediction completed but the expected output file ({expected_output_filename}) was not found in the post-processing folder.")

if __name__ == "__main__":
    main()