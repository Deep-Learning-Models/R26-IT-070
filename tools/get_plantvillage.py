#!/usr/bin/env python3
"""Copy the 10 PlantVillage tomato classes into data/raw/plantvillage.

1. Download the PlantVillage dataset from Kaggle
   (https://www.kaggle.com/datasets/abdallahalidev/plantvillage-dataset) and unzip it.
2. From the repo root run:
       python tools/get_plantvillage.py --source "C:\\Users\\you\\Downloads\\plantvillage dataset"

Only the colour images of the 10 tomato classes are copied. The download
itself is never changed. data/ is in .gitignore, so nothing here is committed.
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from doctor import EXPECTED_CLASSES, IMAGE_EXTS  # noqa: E402


def find_class_folders(source: Path, variant: str) -> dict[str, Path]:
    """Walk the download once and pick each tomato class folder, preferring the chosen variant."""
    found: dict[str, list[Path]] = {name: [] for name in EXPECTED_CLASSES}
    for dirpath, dirnames, _ in os.walk(source):
        for d in dirnames:
            if d in found:
                found[d].append(Path(dirpath) / d)
    chosen: dict[str, Path] = {}
    for name, paths in found.items():
        if not paths:
            continue
        preferred = [p for p in paths if variant.lower() in (part.lower() for part in p.parts)]
        chosen[name] = (preferred or paths)[0]
    return chosen


def count_images(folder: Path) -> int:
    return sum(1 for p in folder.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True, help="the unzipped PlantVillage folder")
    ap.add_argument("--dest", default=str(ROOT / "data" / "raw" / "plantvillage"))
    ap.add_argument("--variant", default="color", help="color (default), grayscale or segmented")
    args = ap.parse_args()

    source, dest = Path(args.source).expanduser(), Path(args.dest)
    if not source.is_dir():
        print(f"Source folder not found: {source}")
        return 1

    print(f"Searching {source} for the 10 tomato classes ({args.variant}) ...")
    folders = find_class_folders(source, args.variant)
    missing = [n for n in EXPECTED_CLASSES if n not in folders]
    if missing:
        print("Could not find these class folders:")
        for n in missing:
            print(f"  - {n}")
        print("Check that you unzipped the Kaggle download and pointed --source at it.")
        return 1

    dest.mkdir(parents=True, exist_ok=True)
    print(f"Copying into {dest}\n")
    print(f"{'Class':<48}{'Images':>8}{'Expected':>10}  Status")
    print("-" * 76)
    total, all_match = 0, True
    for name, expected in EXPECTED_CLASSES.items():
        src = folders[name]
        shutil.copytree(src, dest / name, dirs_exist_ok=True)
        n = count_images(dest / name)
        total += n
        ok = n == expected
        all_match &= ok
        print(f"{name:<48}{n:>8}{expected:>10}  {'ok' if ok else 'CHECK'}")
    print("-" * 76)
    print(f"{'TOTAL':<48}{total:>8}{sum(EXPECTED_CLASSES.values()):>10}")
    print("\nDone." if all_match else "\nDone, but some counts differ. Make sure you used the colour images.")
    print("Next: python preprocessing/scripts/split_dataset.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
