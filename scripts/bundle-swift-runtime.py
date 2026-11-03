#!/usr/bin/env python3
"""Bundle Swift compatibility libraries without developer-machine search paths."""
import argparse
from pathlib import Path
import re
import subprocess

BUNDLE_RPATH = "@executable_path/../Frameworks"


def rpaths(binary):
    output = subprocess.check_output(["otool", "-l", str(binary)], text=True)
    return set(re.findall(r"cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+?) \(offset", output))


def make_portable(binary):
    paths = rpaths(binary)
    for path in sorted(paths):
        if path.startswith("/") and path != "/usr/lib/swift":
            subprocess.run(["install_name_tool", "-delete_rpath", path, str(binary)], check=True)
    if BUNDLE_RPATH not in paths:
        subprocess.run(["install_name_tool", "-add_rpath", BUNDLE_RPATH, str(binary)], check=True)


def verify(app):
    frameworks = app / "Contents/Frameworks"
    binaries = [app / "Contents/MacOS" / name for name in ("Drafts", "DraftsTopicModel")]
    for binary in binaries + sorted(frameworks.glob("*.dylib")):
        for path in rpaths(binary):
            if path.startswith("/") and path != "/usr/lib/swift":
                raise RuntimeError(f"Nonportable runtime search path in {binary.name}: {path}")
        output = subprocess.check_output(["otool", "-L", str(binary)], text=True)
        for line in output.splitlines():
            if " (compatibility version" not in line:
                continue
            dependency = line.split(" (compatibility version", 1)[0].strip()
            if dependency.startswith("@rpath/"):
                library = frameworks / dependency.removeprefix("@rpath/")
                if not library.is_file():
                    raise RuntimeError(f"Missing bundled runtime library: {dependency}")
            elif dependency.startswith("/") and not dependency.startswith(("/usr/lib/", "/System/Library/")):
                raise RuntimeError(f"Non-system runtime dependency: {dependency}")


def bundle(app):
    frameworks = app / "Contents/Frameworks"
    frameworks.mkdir(parents=True, exist_ok=True)
    binaries = [app / "Contents/MacOS" / name for name in ("Drafts", "DraftsTopicModel")]
    command = ["xcrun", "swift-stdlib-tool", "--copy", "--platform", "macosx", "--destination", str(frameworks)]
    for binary in binaries:
        command.extend(["--scan-executable", str(binary)])
    subprocess.run(command, check=True)
    for binary in binaries:
        make_portable(binary)
    verify(app)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    (verify if args.verify_only else bundle)(args.app)
