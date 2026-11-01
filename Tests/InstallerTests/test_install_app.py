import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/install-app.py"
SPEC = importlib.util.spec_from_file_location("drafts_installer", SCRIPT)
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


def app(path, marker, identifier=installer.IDENTIFIER):
    (path / "Contents").mkdir(parents=True)
    (path / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}))
    (path / "Contents/version.txt").write_text(marker)
    return path


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.project = self.root / "project"
        self.support = self.root / "support"
        self.applications = self.root / "Applications"
        self.applications.mkdir()
        self.canonical = app(self.applications / "Drafts.app", "old")
        self.source = app(self.root / "stage/Drafts.app", "new")
        notes = self.support / "Notes"
        (notes / ".drafts").mkdir(parents=True)
        (notes / "note.json").write_text('{"text":"Keep original content"}')
        (notes / ".drafts/categories.json").write_text(json.dumps({
            "categories": [{"id": "topic-id", "name": "Mandir", "description": "Original"}],
            "labels": ["note-id", {"included": ["topic-id"], "excluded": []}],
        }))

    def tearDown(self):
        self.temporary.cleanup()

    def test_duplicate_discovery_never_targets_other_apps_or_canonical(self):
        duplicate = app(self.project / "dist/Drafts.app", "duplicate")
        other = app(self.project / "dist/Other.app", "other", "another.product")
        found = installer.duplicate_apps(self.project, self.support, self.canonical, [other, self.canonical])
        self.assertEqual(found, [duplicate])

    def test_snapshot_compares_manual_uuid_dictionary_semantically(self):
        first = {"labels": ["note-id", {"included": ["b", "a"], "excluded": []}]}
        second = {"labels": {"note-id": {"included": ["a", "b"], "excluded": []}}}
        self.assertEqual(installer.manual_labels(first), installer.manual_labels(second))

    def test_changed_notes_stop_verification(self):
        before = installer.data_snapshot(self.support)
        (self.support / "Notes/note.json").write_text("Changed")
        with self.assertRaises(RuntimeError):
            installer.verify_user_data(before, installer.data_snapshot(self.support))

    @patch.object(installer, "quit_drafts")
    @patch.object(installer, "verify_bundle")
    @patch.object(installer.subprocess, "run")
    def test_success_keeps_one_app_and_preserves_user_data(self, run, verify, quit_app):
        duplicate = app(self.project / "dist/Drafts.app", "duplicate")
        backup = app(self.support / "Install Backups/old/Drafts-previous.app", "backup")
        before = installer.data_snapshot(self.support)

        def result(command, **kwargs):
            output = '{"ready":true}' if "--check-runtime" in command else ""
            return subprocess.CompletedProcess(command, 0, stdout=output)

        run.side_effect = result
        installer.install(self.source, self.project, self.support, self.canonical)
        self.assertEqual((self.canonical / "Contents/version.txt").read_text(), "new")
        self.assertFalse(duplicate.exists())
        self.assertFalse(backup.exists())
        self.assertEqual(installer.data_snapshot(self.support), before)
        self.assertEqual(list(self.applications.iterdir()), [self.canonical])

    @patch.object(installer, "quit_drafts")
    @patch.object(installer, "verify_bundle")
    @patch.object(installer.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "runtime"))
    def test_runtime_failure_rolls_back_before_removing_duplicates(self, run, verify, quit_app):
        duplicate = app(self.project / "dist/Drafts.app", "duplicate")
        with self.assertRaises(subprocess.CalledProcessError):
            installer.install(self.source, self.project, self.support, self.canonical)
        self.assertEqual((self.canonical / "Contents/version.txt").read_text(), "old")
        self.assertTrue(duplicate.exists())
        self.assertEqual(list(self.applications.iterdir()), [self.canonical])


if __name__ == "__main__":
    unittest.main()
