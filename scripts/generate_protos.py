#!/usr/bin/env python3
"""Generate Dart bindings from the vendored, pinned Meshtastic definitions."""
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "lib/generated"
OUT.mkdir(parents=True, exist_ok=True)
compiler = shutil.which("protoc")
if not compiler:
    raise SystemExit("Install protoc first (Ubuntu: apt install protobuf-compiler).")
subprocess.run(["dart", "pub", "global", "activate", "protoc_plugin", "25.0.0"], check=True)
cache = Path(os.environ.get("PUB_CACHE", str(Path.home() / ".pub-cache")))
plugin = cache / "bin/protoc-gen-dart"
sources = sorted(str(path.relative_to(ROOT / "protos"))
                 for path in (ROOT / "protos").rglob("*.proto"))
subprocess.run([compiler, "--proto_path=" + str(ROOT / "protos"),
                "--proto_path=/usr/include",
                "--plugin=protoc-gen-dart=" + str(plugin),
                "--dart_out=" + str(OUT), *sources, "google/protobuf/descriptor.proto"], cwd=ROOT, check=True)
print("Generated pinned Meshtastic Dart bindings.")
