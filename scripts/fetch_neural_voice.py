#!/usr/bin/env python3
"""Fetch the pinned Nabra INT8 model and phoneme data for local developer builds."""
from hashlib import file_digest
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "GameCaption" / "NeuralArabicVoice"
ARCHIVE = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/nabra-82m-arabic-int8.tar.bz2"
SHA256 = "a8608a504b1db4dd538b821409fe50b2d5cf37650c0a8753fa215bd6445e9964"


def main():
    with tempfile.TemporaryDirectory() as directory:
        tmp = Path(directory)
        archive = tmp / "nabra-int8.tar.bz2"
        subprocess.run(["curl", "--fail", "--location", "--retry", "5", "--retry-all-errors",
                        "--connect-timeout", "30", "--max-time", "1500",
                        "--silent", "--show-error", "--output", str(archive), ARCHIVE], check=True)
        with archive.open("rb") as file:
            if file_digest(file, "sha256").hexdigest() != SHA256:
                raise ValueError("Nabra release archive checksum mismatch")
        extract = tmp / "extract"
        with tarfile.open(archive, "r:bz2") as tar:
            tar.extractall(extract, filter="data")

        DEST.mkdir(parents=True, exist_ok=True)
        for name in ("model.int8.onnx", "tokens.txt", "voices.bin", "espeak-ng-data"):
            (asset,) = extract.rglob(name)
            if asset.is_dir():
                shutil.copytree(asset, DEST / name, dirs_exist_ok=True)
            else:
                shutil.copy2(asset, DEST / name)
        print(f"Verified Nabra INT8 archive and installed assets in {DEST}")


if __name__ == "__main__":
    main()
