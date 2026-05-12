import csv
from pathlib import Path
from collections import defaultdict


def generate_raw_summary(bids_root_path, output_csv_path):
    """
    Scans a BIDS dataset to count .nii.gz files across anat, dwi, and func folders.
    Writes the summary directly to a CSV file using original folder names.
    """
    bids_root = Path(bids_root_path)
    raw_data_path = bids_root / 'sourcedata' / 'raw'

    if not raw_data_path.is_dir():
        print(f"Error: The path {raw_data_path} does not exist.")
        return

    modalities_to_check = ['anat', 'dwi', 'func']
    found_modalities = set()
    records = defaultdict(dict)

    for subject_dir in raw_data_path.glob('sub-*'):
        if not subject_dir.is_dir():
            continue
        subject_id = subject_dir.name

        for session_dir in subject_dir.glob('ses-*'):
            if not session_dir.is_dir():
                continue
            session_id = session_dir.name

            # Check each modality folder
            for modality in modalities_to_check:
                modality_dir = session_dir / modality

                if modality_dir.is_dir():
                    found_modalities.add(modality)
                    # Count all files ending with .nii.gz
                    file_count = sum(1 for _ in modality_dir.glob('*.nii.gz'))
                    records[(subject_id, session_id)][modality] = file_count

    if not records:
        print("No .nii.gz files were found in the specified raw structure.")
        return

    # Order raw columns properly
    ordered_cols = [m for m in modalities_to_check if m in found_modalities]

    # Write as a pivot table to CSV
    with open(output_csv_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['Subject', 'Session'] + ordered_cols)
        for (sub, ses) in sorted(records.keys()):
            row = [sub, ses] + [records[(sub, ses)].get(col, 0) for col in ordered_cols]
            writer.writerow(row)


def generate_derivatives_summary(bids_root_path, output_csv_path):
    """
    Scans the derivatives folder and checks specific file patterns.
    Writes the summary directly to a CSV file using original folder names.
    """
    bids_root = Path(bids_root_path)
    derivatives_path = bids_root / 'derivatives'

    if not derivatives_path.is_dir():
        print(f"Error: Derivatives folder not found at {derivatives_path}")
        return

    # Format: pipeline_name: (subfolder_type, file_pattern)
    pipeline_rules = {
        'niftymic': ('anat', '*niftymic_desc-brainbg_T2w.nii.gz'),
        'longiseg': ('anat', '*.nii.gz'),
        'surf-slam': ('anat', '*.gii'),
        'mrtrix': ('dwi', '*_tensor.nii.gz')
    }

    desired_order = ['niftymic', 'longiseg', 'surf-slam', 'mrtrix']
    found_pipelines = set()
    records = defaultdict(dict)

    for pipeline, (modality, pattern) in pipeline_rules.items():
        pipeline_dir = derivatives_path / pipeline

        if not pipeline_dir.is_dir():
            continue

        found_pipelines.add(pipeline)

        for subject_dir in pipeline_dir.glob('sub-*'):
            if not subject_dir.is_dir():
                continue
            subject_id = subject_dir.name

            for session_dir in subject_dir.glob('ses-*'):
                if not session_dir.is_dir():
                    continue
                session_id = session_dir.name

                target_dir = session_dir / modality
                count = 0
                if target_dir.is_dir():
                    count = sum(1 for _ in target_dir.glob(pattern))

                records[(subject_id, session_id)][pipeline] = count

    if not records:
        print("No derivative files found matching the criteria.")
        return

    # Keep only columns that exist, mapped to the desired order
    ordered_columns = [col for col in desired_order if col in found_pipelines]

    # Write as a pivot table to CSV
    with open(output_csv_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['Subject', 'Session'] + ordered_columns)
        for (sub, ses) in sorted(records.keys()):
            row = [sub, ses] + [records[(sub, ses)].get(col, 0) for col in ordered_columns]
            writer.writerow(row)


def generate_bids_reports(derivatives_file, sourcedata_file):
    merged_data = defaultdict(lambda: defaultdict(dict))
    found_columns = []

    # 1. Load and parse source data
    if Path(sourcedata_file).exists():
        with open(sourcedata_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            source_cols = [c for c in reader.fieldnames if c not in ('Subject', 'Session')]
            found_columns.extend(source_cols)
            for row in reader:
                sub, ses = row['Subject'], row['Session']
                for col in source_cols:
                    merged_data[sub][ses][col] = int(row[col] or 0)

    # 2. Load and parse derivatives data
    if Path(derivatives_file).exists():
        with open(derivatives_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            deriv_cols = [c for c in reader.fieldnames if c not in ('Subject', 'Session')]
            found_columns.extend([c for c in deriv_cols if c not in found_columns])
            for row in reader:
                sub, ses = row['Subject'], row['Session']
                for col in deriv_cols:
                    merged_data[sub][ses][col] = int(row[col] or 0)

    if not merged_data:
        print("No data available to generate reports.")
        return

    # Define the mapping for the Markdown display names
    display_names = {
        'anat': 'anat-stacks',
        'dwi': 'dwi-stacks',
        'func': 'func',
        'niftymic': 'anat-recon',
        'longiseg': 'anat-seg',
        'surf-slam': 'anat-surf',
        'mrtrix': 'dwi-recon'
    }

    # Define the exact master order for columns (using original names)
    master_order = [
        'anat',
        'dwi',
        'func',
        'niftymic',
        'longiseg',
        'surf-slam',
        'mrtrix'
    ]
    
    # Filter the master list to only include columns we actually have data for
    final_columns = [col for col in master_order if col in found_columns]

    # Initialize markdown content
    markdown_content = "# 🚀 BIDS Summary Report 🚀\n\n"

    # Loop through each subject to create separated sections
    for subject in sorted(merged_data.keys()):
        markdown_content += f"## 👤 {subject} ✨\n\n"

        # Construct Markdown Table Header using the new display names
        headers = ['Session'] + [display_names.get(col, col) for col in final_columns]
        markdown_content += "| " + " | ".join(headers) + " |\n"
        markdown_content += "|" + "|".join(["---" for _ in headers]) + "|\n"

        # Add data rows sorted by session
        for session in sorted(merged_data[subject].keys()):
            row_data = merged_data[subject][session]
            formatted_row = [f"📅 {session}"]

            for col in final_columns:
                val = row_data.get(col, 0) # Fill missing values with 0
                
                # Apply validation rules based on the original column names
                if col == 'longiseg':           
                    fmt = '✅' if val > 0 else ('❌' if val == 0 else str(val))
                elif col == 'surf-slam':        
                    fmt = '✅' if val == 2 else ('❌' if val == 0 else '1/2 ⚠️')
                elif col in ['niftymic', 'mrtrix']:  
                    fmt = '✅' if val == 1 else '❌'
                else:                           
                    fmt = '❌' if val == 0 else str(val)

                formatted_row.append(fmt)

            markdown_content += "| " + " | ".join(formatted_row) + " |\n"

        # Add a visual separator
        markdown_content += "\n\n---\n\n"

    # Save the report to a file
    report_path = Path('bids_summary.md')
    with open(report_path, 'w', encoding='utf-8') as file:
        file.write(markdown_content)
    
    print(f"Report successfully saved to: {report_path.resolve()}")


# --- Execution ---
if __name__ == "__main__":
    DATABASE_PATH = "/envau/work/meca/data/BaboFet_BIDS/"

    raw_csv_path = "bids_summary_sourcedata.csv"
    derivatives_csv_path = "bids_summary_derivatives.csv"

    # Always generate/update the CSVs and the Report
    generate_raw_summary(DATABASE_PATH, raw_csv_path)
    generate_derivatives_summary(DATABASE_PATH, derivatives_csv_path)

    generate_bids_reports(
        derivatives_file=derivatives_csv_path,
        sourcedata_file=raw_csv_path
    )
