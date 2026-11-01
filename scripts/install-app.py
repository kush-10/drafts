#!/usr/bin/env python3
"""Install one verified Drafts app without retaining duplicate app bundles."""
import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

IDENTIFIER = "app.drafts.scratchpad"


def is_drafts(path):
    try:
        info = plistlib.loads((path / "Contents/Info.plist").read_bytes())
        return info.get("CFBundleIdentifier") == IDENTIFIER
    except (OSError, ValueError):
        return False


def duplicate_apps(project, support, canonical, extra_paths=()):
    candidates = {project / "dist/Drafts.app"}
    candidates.update((support / "Install Backups").glob("*/Drafts-previous.app"))
    candidates.update(extra_paths)
    return sorted(p for p in candidates if p.exists() and p.resolve() != canonical.resolve() and is_drafts(p))


def manual_labels(document):
    labels = document.get("labels", {})
    if isinstance(labels, list):
        labels = dict(zip(labels[::2], labels[1::2]))
    return {key: {field: sorted(value.get(field, [])) for field in ("included", "excluded")}
            for key, value in labels.items()}


def data_snapshot(support):
    notes = support / "Notes"
    metadata = notes / ".drafts/categories.json"
    document = json.loads(metadata.read_text()) if metadata.exists() else {}
    models = support / "Models"
    return {
        "notes": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in notes.glob("*.json") if p.is_file()},
        "manual": manual_labels(document),
        "topic_ids": {c["name"].casefold(): c["id"] for c in document.get("categories", [])},
        "models": {str(p.relative_to(models)): (p.stat().st_size, p.stat().st_mtime_ns)
                   for p in models.rglob("*") if p.is_file()} if models.exists() else {},
    }


def verify_user_data(before, after):
    for field in ("notes", "manual", "models"):
        if before[field] != after[field]:
            raise RuntimeError(f"Installation stopped: {field} changed unexpectedly. No old app copies were deleted.")
    for name, identifier in before["topic_ids"].items():
        if after["topic_ids"].get(name) != identifier:
            raise RuntimeError("An existing topic ID changed unexpectedly. No old app copies were deleted.")


def quit_drafts():
    code = r'''
import AppKit
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "app.drafts.scratchpad")
for app in apps { if !app.terminate() { fputs("Drafts could not quit safely. Save your work and quit it first.\n", stderr); exit(1) } }
let deadline = Date().addingTimeInterval(45)
while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
if apps.contains(where: { !$0.isTerminated }) {
    fputs("Drafts is still open, possibly waiting for a save-error dialog. Installation cancelled.\n", stderr); exit(1)
}
'''
    subprocess.run(["/usr/bin/swift", "-e", code], check=True)


def verify_bundle(path):
    if not is_drafts(path):
        raise RuntimeError(f"Not a Drafts app: {path}")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(path)], check=True)


def install(source, project, support, canonical):
    verify_bundle(source)
    if canonical.exists() and not is_drafts(canonical):
        raise RuntimeError(f"Refusing to replace a different app at {canonical}")
    quit_drafts()
    before = data_snapshot(support)
    work = Path(tempfile.mkdtemp(prefix=".Drafts-install-", dir=canonical.parent))
    candidate, previous = work / "Drafts.app", work / "previous.app"
    safe_to_clean = False
    try:
        try:
            os.replace(source, candidate)
        except OSError as error:
            if error.errno != errno.EXDEV:
                raise
            subprocess.run(["/usr/bin/ditto", str(source), str(candidate)], check=True)
        verify_bundle(candidate)
        if canonical.exists():
            os.replace(canonical, previous)
        try:
            os.replace(candidate, canonical)
            verify_bundle(canonical)
            helper = canonical / "Contents/MacOS/DraftsTopicModel"
            result = subprocess.run([str(helper), "--check-runtime"], check=True, capture_output=True, text=True, timeout=30)
            if not json.loads(result.stdout).get("ready"):
                raise RuntimeError("The installed MLX runtime did not pass its check.")
            subprocess.run([str(canonical / "Contents/MacOS/Drafts"), "--configure-topics"], check=True, timeout=30)
            verify_user_data(before, data_snapshot(support))
        except Exception:
            if canonical.exists():
                os.replace(canonical, work / "failed.app")
            if previous.exists():
                os.replace(previous, canonical)
            raise
        indexed = subprocess.run(["/usr/bin/mdfind", f'kMDItemCFBundleIdentifier == "{IDENTIFIER}"'],
                                 capture_output=True, text=True, check=True)
        home = Path.home()
        extras = [Path(line) for line in indexed.stdout.splitlines()
                  if Path(line).is_relative_to(home) or Path(line).parent == canonical.parent]
        extras = [p for p in extras if not p.is_relative_to(work) and not p.is_relative_to(source.parent)]
        duplicates = duplicate_apps(project, support, canonical, extras)
        for path in duplicates:
            if path.is_symlink():
                path.unlink()
            else:
                shutil.rmtree(path)
            print(f"Removed duplicate app: {path}")
        safe_to_clean = True
        print(f"Installed {canonical}. Notes, manual assignments and downloaded models were preserved.")
    finally:
        if safe_to_clean or not previous.exists():
            shutil.rmtree(work)
        else:
            print(f"Recovery app retained at {previous}; installation did not complete.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    support = Path.home() / "Library/Application Support/Drafts"
    canonical = Path("/Applications/Drafts.app")
    if args.dry_run:
        print(f"Would verify and install {args.source} at {canonical}")
        for path in duplicate_apps(project, support, canonical):
            print(f"Would remove: {path}")
        return
    install(args.source.resolve(), project, support, canonical)


if __name__ == "__main__":
    main()
