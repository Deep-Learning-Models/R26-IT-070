#!/usr/bin/env python3
"""R26-IT-070 environment doctor.

Checks Python, the virtual environment, pinned packages, GPU, config,
dataset and git branch, then prints a short report.

    python tools/doctor.py
"""
from __future__ import annotations

import os
import subprocess
import sys
from importlib import metadata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# PlantVillage tomato subset, colour images (18,160 in total)
EXPECTED_CLASSES = {
    "Tomato___Bacterial_spot": 2127,
    "Tomato___Early_blight": 1000,
    "Tomato___Late_blight": 1909,
    "Tomato___Leaf_Mold": 952,
    "Tomato___Septoria_leaf_spot": 1771,
    "Tomato___Spider_mites Two-spotted_spider_mite": 1676,
    "Tomato___Target_Spot": 1404,
    "Tomato___Tomato_Yellow_Leaf_Curl_Virus": 5357,
    "Tomato___Tomato_mosaic_virus": 373,
    "Tomato___healthy": 1591,
}
IMAGE_EXTS = {".jpg", ".jpeg", ".png"}

results: list[tuple[str, str]] = []


def report(status: str, name: str, detail: str = "", fix: str = "") -> None:
    """status: OK, WARN or FAIL."""
    results.append((status, name))
    tag = {"OK": "[ OK ]", "WARN": "[WARN]", "FAIL": "[FAIL]"}[status]
    line = f"{tag} {name}"
    if detail:
        line += f"  ({detail})"
    print(line)
    if fix and status != "OK":
        print(f"       fix: {fix}")


def section(title: str) -> None:
    print(f"\n== {title} " + "=" * max(0, 56 - len(title)))


def check_python() -> None:
    section("Python")
    v = sys.version_info
    ver = f"{v.major}.{v.minor}.{v.micro}"
    if (v.major, v.minor) == (3, 10):
        report("OK", "Python 3.10", ver)
    elif (3, 9) <= (v.major, v.minor) <= (3, 11):
        report("WARN", "Python version", f"{ver}; the team standard is 3.10",
               "install Python 3.10 and re-run tools/setup_env.ps1")
    else:
        report("FAIL", "Python version", f"{ver} is not supported by torch 2.2.1 here",
               "install Python 3.10 and re-run tools/setup_env.ps1")

    in_venv = sys.prefix != getattr(sys, "base_prefix", sys.prefix)
    if in_venv and Path(sys.prefix).name == ".venv":
        report("OK", "Running inside the repo's .venv")
    elif in_venv:
        report("WARN", "Running inside a virtual environment", sys.prefix,
               "use the repo's .venv so everyone has the same packages")
    else:
        report("FAIL", "Not inside a virtual environment", sys.executable,
               r"activate it first:  .\.venv\Scripts\Activate.ps1")


def read_pins() -> dict[str, str]:
    pins: dict[str, str] = {}
    req = ROOT / "requirements.txt"
    if not req.exists():
        return pins
    for raw in req.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if "==" in line:
            name, ver = line.split("==", 1)
            pins[name.strip()] = ver.strip()
    return pins


def check_packages() -> None:
    section("Packages (requirements.txt)")
    pins = read_pins()
    if not pins:
        report("FAIL", "requirements.txt not found or has no pins", fix="run from inside the repo")
        return
    for name, wanted in pins.items():
        try:
            have = metadata.version(name)
        except metadata.PackageNotFoundError:
            report("FAIL", name, "not installed", "pip install -r requirements.txt")
            continue
        base = have.split("+", 1)[0]
        if base == wanted:
            report("OK", name, have)
        else:
            report("WARN", name, f"have {have}, team pins {wanted}",
                   f"pip install {name}=={wanted}")
    try:
        metadata.version("ipykernel")
        report("OK", "ipykernel (for notebooks)")
    except metadata.PackageNotFoundError:
        report("WARN", "ipykernel missing", "notebooks can't use this .venv", "pip install ipykernel")


def check_gpu() -> None:
    section("GPU")
    try:
        import torch
    except Exception as exc:  # noqa: BLE001
        report("FAIL", "import torch", str(exc), "re-run tools/setup_env.ps1")
        return
    if torch.cuda.is_available():
        props = torch.cuda.get_device_properties(0)
        vram = props.total_memory / 1024 ** 3
        report("OK", "CUDA available", f"{props.name}, {vram:.1f} GB VRAM, CUDA {torch.version.cuda}")
        try:
            x = torch.randn(256, 256, device="cuda")
            float((x @ x).sum())
            report("OK", "A test calculation ran on the GPU")
        except Exception as exc:  # noqa: BLE001
            report("FAIL", "GPU test calculation", str(exc), "update the NVIDIA driver")
        if vram < 8:
            report("WARN", "Less than 8 GB VRAM", fix="use batch_size 16 in configs/default.yaml, or Colab")
    else:
        build = "CPU-only build" if torch.version.cuda is None else f"CUDA {torch.version.cuda} build, no GPU visible"
        report("WARN", "No CUDA GPU", build,
               "install the NVIDIA driver, then: .\\tools\\setup_env.ps1 -Fresh  (or train on Colab)")


def check_config() -> None:
    section("Config")
    cfg_path = ROOT / "configs" / "default.yaml"
    if not cfg_path.exists():
        report("FAIL", "configs/default.yaml missing")
        return
    try:
        import yaml
        cfg = yaml.safe_load(cfg_path.read_text(encoding="utf-8")) or {}
    except Exception as exc:  # noqa: BLE001
        report("FAIL", "configs/default.yaml could not be read", str(exc))
        return
    out_ch = cfg.get("backbone", {}).get("out_channels")
    in_ch = cfg.get("lada", {}).get("in_channels")
    name = cfg.get("backbone", {}).get("name")
    if out_ch == in_ch:
        report("OK", "Backbone and LADA channels match", f"{name}: {out_ch}")
    else:
        report("FAIL", "Channel mismatch", f"backbone {out_ch} vs lada {in_ch}",
               "make lada.in_channels equal backbone.out_channels")
    size = cfg.get("data", {}).get("image_size")
    report("OK" if size == 256 else "WARN", "Image size", str(size))


def count_images(folder: Path) -> int:
    return sum(1 for p in folder.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS)


def check_data() -> None:
    section("Dataset")
    raw = ROOT / "data" / "raw" / "plantvillage"
    if not raw.exists():
        report("WARN", "data/raw/plantvillage not found", fix="python tools/get_plantvillage.py --source <unzipped PlantVillage folder>")
        return
    total = 0
    for cls, expected in EXPECTED_CLASSES.items():
        folder = raw / cls
        if not folder.is_dir():
            report("FAIL", cls, "folder missing", "re-run tools/get_plantvillage.py")
            continue
        n = count_images(folder)
        total += n
        report("OK" if n == expected else "WARN", cls, f"{n} images, expected {expected}")
    extra = sorted(p.name for p in raw.iterdir() if p.is_dir() and p.name not in EXPECTED_CLASSES)
    if extra:
        report("WARN", "Extra folders in data/raw/plantvillage", ", ".join(extra[:5]),
               "keep only the 10 tomato classes")
    report("OK" if total == sum(EXPECTED_CLASSES.values()) else "WARN", "Total raw images", f"{total} of 18,160")

    split = ROOT / "data" / "split"
    if all((split / part).is_dir() for part in ("train", "val", "test")):
        counts = {part: sum(count_images(d) for d in (split / part).iterdir() if d.is_dir())
                  for part in ("train", "val", "test")}
        report("OK", "data/split exists", ", ".join(f"{k} {v}" for k, v in counts.items()))
    else:
        report("WARN", "data/split not created yet", fix="python preprocessing/scripts/split_dataset.py")


def check_git() -> None:
    section("Git")
    try:
        branch = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=ROOT,
                                capture_output=True, text=True, check=True).stdout.strip()
    except Exception:  # noqa: BLE001
        report("WARN", "git not available here", fix="install Git or use GitHub Desktop")
        return
    if branch == "main":
        report("WARN", "You are on main", fix="switch to your branch in GitHub Desktop (e.g. Maduwantha-classification-head)")
    else:
        report("OK", "Working on your own branch", branch)


def main() -> int:
    os.chdir(ROOT)
    print("R26-IT-070 environment doctor")
    print(f"repo: {ROOT}")
    check_python()
    check_packages()
    check_gpu()
    check_config()
    check_data()
    check_git()
    ok = sum(s == "OK" for s, _ in results)
    warn = sum(s == "WARN" for s, _ in results)
    fail = sum(s == "FAIL" for s, _ in results)
    print("\n" + "=" * 60)
    print(f"{ok} OK   {warn} warnings   {fail} failures")
    if fail == 0 and warn == 0:
        print("All green. Your environment is ready.")
    elif fail == 0:
        print("Usable. Read the warnings above when you have a minute.")
    else:
        print("Fix the [FAIL] lines first, then run this again.")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
