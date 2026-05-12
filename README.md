# Babofet DWI Pipeline

An automated, end-to-end Slice-to-Volume Reconstruction (SVR) and preprocessing pipeline for Fetal and Baboon Diffusion-Weighted MRI (DWI).

## 🚀 Features
- **Preprocessing:** Denoising, unringing, topup, N4 bias correction, and FSL Eddy (motion/distortion correction).
- **Brain Extraction:** Automated masking using custom-trained nnU-Net models.
- **Reconstruction:** Slice-to-volume reconstruction of high-resolution b0, b1000, and full DWI signals using MIRTK and SVRTK.
- **Microstructure:** Tensor fitting (FA, MD, AD, RD) and CSD-based FOD estimation via MRtrix3.
- **Alignment:** Registration of reconstructed DWI to high-resolution T2 structural templates.

---

## 🛠️ Prerequisites

Before installing the Python dependencies, ensure you have the following neuroimaging software installed and accessible in your `$PATH`:
* [FSL](https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FslInstallation) (v6.0+)
* [MRtrix3](https://www.mrtrix.org/download/) (v3.0.8+)
* [ANTs](https://github.com/ANTsX/ANTs) (v2.3+)
* [Singularity](https://docs.sylabs.io/guides/2.6/user-guide/installation.html) (for SVR tools)

---

## ⚙️ Installation

**1. Clone the repository**

```
git clone https://github.com/MecaLab/Babofet_DWI.git
cd Babofet_DWI
```

**2. Download Singularity Images and Models**

The pipeline requires pre-compiled MIRTK/SVRTK Singularity ```.sif``` images and pre-trained nnU-Net model weights. Run the provided script to download them:

```
bash scripts/download_dependencies.sh
```

**3. Set up the Python Environment**

All required Python packages are listed in ```requirements.txt```

```
conda create -n babofet_env python=3.12
conda activate babofet_env
pip install -r requirements.txt
```

**4. Install nnUNet**

The following commands will install nnUNet in the envirorment

```
pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cpu
pip install nnunetv2
```


## 📂 Configuration

**1. Configure Paths**

Before running, update ```config/config.sh``` to match your directory structure:

```
# config/config.sh variables
export RAWDATA_DIR="/path/to/your/bids/rawdata"
export DERIVATIVES_DIR="/path/to/your/bids/derivatives"
export OUTPUT_TMP_DIR="/path/to/working/scratch"  # intermediary files
```
**3. HPC Cluster Users (SLURM)**

If you use a module system on an HPC cluster, create a file named ```config/env_setup.sh``` and add your module load commands there. The pipeline will automatically load them:
```
# config/env_setup.sh
module purge
module load ANTS/0.2.6.4
module load mrtrix/3.0.8
module load singularity
module load FSL/0.6.0.7.18
```
otherwise delete the ```config/env_setup.sh``` file.

## 🏃 Usage
### Running Locally

To run the pipeline locally or on interactive nodeon a single subject and session, execute the master script:
```
bash 00_run_pipeline.sh <SUBJECT_ID> <SESSION_ID>

# Example:
bash 00_run_pipeline.sh sub-Aziza ses-01
```

### Running on a SLURM Cluster

An example SLURM submission script is provided (sbatch_run.sh). You can edit the arrays inside the script to define your subjects/sessions, and submit it:
```
sbatch sbatch_run.sh <SUBJECT_ID> <SESSION_ID>

# Example:
sbatch sbatch_run.sh sub-Aziza ses-01
```
### Run specific steps

To run specific steps of the pipeline is necessary to comment out the steps to skip in the ```./00_run_pipeline.sh``` file:

```bash
# Example: skip the preprocessing

#echo "STEP 1: Preprocessing individual DWI stacks..."
#bash ./01_preprocess_stacks.sh
#echo "✅ STEP 1 complete."
#echo "-----------------------------------------"

#echo "STEP 1a: Extracting brain mask..."
#bash ./01a_brain_extraction.sh
#echo "✅ STEP 1a complete."
#echo "-----------------------------------------"

echo "STEP 2: Registering stacks to reference..."
bash ./02_register_stacks.sh
echo "✅ STEP 2 complete."
echo "-----------------------------------------"

echo "STEP 3a: Reconstructing high-resolution b0 volume..."
bash ./03a_reconstruct_b0.sh
echo "✅ STEP 3a complete."
echo "-----------------------------------------"

...

```
