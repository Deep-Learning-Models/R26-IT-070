# R26-IT-070 · Environment setup, A to Z

Windows first. Every command runs from the repo root in PowerShell unless it says otherwise.
Tools added for this: `tools/setup_env.ps1`, `tools/doctor.py`, `tools/get_plantvillage.py`,
`tools/cleanup.ps1` and `notebooks/03_train_colab.ipynb`.

## Tools (A–E)
- **A · Accounts** – a GitHub account with access to `Deep-Learning-Models/R26-IT-070`, and a Kaggle account for the dataset.
- **B · Base tools** – install Git and GitHub Desktop, then sign in (File → Options → Accounts).
- **C · Code editor** – VS Code with the *Python* and *Jupyter* extensions.
- **D · Driver** – the latest NVIDIA driver. Check it with `nvidia-smi`.
- **E · Exact Python** – Python **3.10** from python.org (tick *Add python.exe to PATH*). Check it with `py -3.10 --version`.

## Repo (F–J)
- **F · Fetch** – GitHub Desktop → *Fetch origin*, then *Pull origin* on `main`.
- **G · Git identity + branch** – File → Options → Git (name + GitHub email). Then Current branch → New branch → `<YourName>-<feature>` → *Publish branch*.
- **H · Hand PowerShell permission** (once): `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`
- **I · Inspect and tidy** – `.\tools\cleanup.ps1`. Review the changes in GitHub Desktop, then commit *"Tidy repo: remove empty placeholders, move figures to docs/figures"*.
- **J · Jot team questions** – agree on `src/` placeholders, `notebooks/04_inference_demo.ipynb` and `preprocessing/scripts/download_dataset.py` before running `.\tools\cleanup.ps1 -TeamApproved`.

## Python (K–N)
- **K · Kick off setup** – `.\tools\setup_env.ps1` (add `-Cpu` if you have no NVIDIA GPU, or `-Fresh` to rebuild).
- **L · Link VS Code** – Ctrl+Shift+P → *Python: Select Interpreter* → `.venv`.
- **M · Make sure CUDA works** – `.\.venv\Scripts\Activate.ps1`, then `python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"`
- **N · Notebook kernel** – in any notebook, pick the kernel **R26-IT-070 (.venv)**.

## Data (O–R)
- **O · Obtain PlantVillage** – download from https://www.kaggle.com/datasets/abdallahalidev/plantvillage-dataset and unzip it.
- **P · Place the tomato folders** – `python tools/get_plantvillage.py --source "<unzipped folder>"` copies the 10 tomato classes into `data/raw/plantvillage/`.
- **Q · Quantity check** – the copier and the doctor expect 18,160 images (Yellow Leaf Curl 5,357 … Mosaic 373).
- **R · Run the split** – `python preprocessing/scripts/split_dataset.py` → `data/split/train|val|test`.

## Prove it (S–V)
- **S · Sanity tests** – `python -m pytest -v`
- **T · Test a batch** – `python preprocessing/scripts/build_dataloader.py` should print `torch.Size([32, 3, 256, 256])`.
- **U · Understand the size** – `python calculate_params.py`
- **V · Verify** – `python tools/doctor.py` (no `[FAIL]` lines means you're ready).

## Ship (W–Z)
- **W · Write the logbook** – record the date, the tool versions, the GPU and any problems you hit.
- **X · eXtra GPU** – open `notebooks/03_train_colab.ipynb` in Colab when you need a bigger GPU.
- **Y · Your first commit** – commit the setup tools on your branch, push, and open a pull request to `main`.
- **Z · Zero to training** – the environment is done. Start your model work.

`data/`, `checkpoints/`, `.venv/`, `*.csv` and `*.json` are git-ignored, so datasets and weights never reach GitHub.
