#!/usr/bin/env python3
"""Download independent, Apache-2.0 Arabic neural speech assets for IPA builds.

Source: https://huggingface.co/marwanelamami/nabra-82m-sherpa-onnx
Model: Nabra-82M (Arabic), Kokoro-compatible, weights by marwanelamami.
This script never reads or redistributes the reference Side Screen IPA.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "GameCaption" / "NeuralArabicVoice"
ARCHIVE = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/nabra-82m-arabic-int8.tar.bz2"
FP16 = "https://huggingface.co/marwanelamami/nabra-82m-sherpa-onnx/resolve/main/model.fp16.onnx?download=true"


def download(url: str, out: Path):
    subprocess.run(["curl", "--fail", "--location", "--retry", "5", "--retry-all-errors",
                    "--connect-timeout", "30", "--max-time", "1500",
                    "--silent", "--show-error", "--output", str(out), url], check=True)
    if out.stat().st_size < 100_000:
        raise ValueError(f"Downloaded file looks incomplete: {out.name} ({out.stat().st_size})")


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        tmp = Path(directory)
        archive = tmp / "nabra-int8.tar.bz2"
        print("Downloading Apache-2.0 Nabra Arabic speech model INT8 + speech frontend...")
        download(ARCHIVE, archive)
        with tarfile.open(archive, "r:bz2") as tar:
            members = tar.getmembers()
            if any(x.issym() or x.islnk() or x.name.startswith("/") or ".." in Path(x.name).parts for x in members):
                raise RuntimeError("Unsafe tar archive contents")
            tar.extractall(tmp / "extract", filter="data")

        root = tmp / "extract"
        for filename in ("model.int8.onnx", "tokens.txt", "voices.bin"):
            matches = list(root.rglob(filename))
            if len(matches) != 1:
                raise RuntimeError(f"Expected exactly one {filename}, got {len(matches)}")
            shutil.copy2(matches[0], DEST / filename)

        espeak = list(root.rglob("espeak-ng-data"))
        if len(espeak) != 1 or not espeak[0].is_dir():
            raise RuntimeError("espeak-ng-data missing from official speech model bundle")
        shutil.copytree(espeak[0], DEST / "espeak-ng-data", dirs_exist_ok=True)
        print("Downloading Apache-2.0 FP16 high precision variant...")
        download(FP16, DEST / "model.fp16.onnx")

    required = {
        "model.int8.onnx": 50_000_000,
        "model.fp16.onnx": 120_000_000,
        "tokens.txt": 200,
        "voices.bin": 100_000,
    }
    for filename, minimum in required.items():
        size = (DEST / filename).stat().st_size
        if size < minimum:
            raise RuntimeError(f"Voice model {filename} is too small: {size} bytes")
        print(f"PASS: {filename} — {size:,} bytes")
    assert (DEST / "espeak-ng-data" / "phontab").is_file(), "phonetic tables missing"
    print("PASS: properly sourced local Arabic voice model assets (license Apache-2.0)")


if __name__ == "__main__":
    main()
