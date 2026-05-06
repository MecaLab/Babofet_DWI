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

3.  **Diffusion Modelling:** The final high-resolution 4D DWI volume is used to:
    *   Fit a diffusion tensor model to derive metrics like Fractional Anisotropy (FA) and Mean Diffusivity (MD).
    *   Estimate Fiber Orientation Distributions (FODs) using Constrained Spherical Deconvolution (CSD) to resolve complex fiber crossings.

## Prerequisites & Dependencies

This pipeline relies on several external software packages. You must have them installed and available in your system's `PATH`.

*   **FSL** (v6.0 or later): For `flirt`, `eddy`, `topup`, `fnirt`, and other utilities.
*   **MRtrix3**: For denoising, Gibbs correction, tensor and FOD modeling (`dwidenoise`, `mrdegibbs`, `dwi2tensor`, `dwi2fod`, etc.).
*   **ANTs**: For N4 bias field correction and mask propagation (`N4BiasFieldCorrection`, `antsApplyTransforms`).
*   **Singularity / Apptainer**: Required to run containerized versions of MIRTK and SVRTK.
    *   **MIRTK** (`mirtk.sif`): Used for converting transformation formats.
    *   **SVRTK** (`svrtk.sif`): The core toolkit for slice-to-volume reconstruction (`mirtk reconstruct`, `mirtk reconstructDWI`).
*   **Python 3**: With libraries such as `nibabel` and `numpy`.

The pipeline assumes that brain masks have been generated beforehand.
You can find the weights for our nnU-Net model [here](https://amubox.univ-amu.fr/s/rMAanGjdFEiegAs).

## Data Structure

The pipeline is designed to work with data organized in a BIDS-like structure.
```
git clone https://github.com/MecaLab/Babofet_DWI.git
cd Babofet_DWI
```

**2. Download Singularity Images and Models**

The pipeline requires pre-compiled MIRTK/SVRTK Singularity .sif images and pre-trained nnU-Net model weights. Run the provided script to download them:

```
bash scripts/download_dependencies.sh
```

**3. Set up the Python Environment**

All required Python packages are listed in requirements.txt

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

If you use a module system on an HPC cluster, create a file named config/env_setup.sh and add your module load commands there. The pipeline will automatically load them:
```
# config/env_setup.sh
module purge
module load ANTS/0.2.6.4
module load mrtrix/3.0.8
module load singularity
module load FSL/0.6.0.7.18
```
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
sbatch sbatch_run.sh
```
