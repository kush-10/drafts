import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import call, patch

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/bundle-swift-runtime.py"
SPEC = importlib.util.spec_from_file_location("drafts_swift_runtime", SCRIPT)
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)


class SwiftRuntimeTests(unittest.TestCase):
    @patch.object(runtime.subprocess, "run")
    @patch.object(runtime, "rpaths")
    def test_removes_developer_paths_and_adds_bundle_path(self, rpaths, run):
        binary = Path("Drafts.app/Contents/MacOS/DraftsTopicModel")
        developer = "/Applications/Xcode.app/Contents/Developer/lib/swift"
        rpaths.return_value = {"/usr/lib/swift", "@loader_path", developer}
        runtime.make_portable(binary)
        self.assertEqual(run.call_args_list, [
            call(["install_name_tool", "-delete_rpath", developer, str(binary)], check=True),
            call(["install_name_tool", "-add_rpath", runtime.BUNDLE_RPATH, str(binary)], check=True),
        ])

    @patch.object(runtime.subprocess, "run")
    @patch.object(runtime, "rpaths", return_value={runtime.BUNDLE_RPATH, "/usr/lib/swift"})
    def test_portable_paths_are_not_added_twice(self, rpaths, run):
        runtime.make_portable(Path("Drafts"))
        run.assert_not_called()

    @patch.object(runtime.subprocess, "check_output")
    def test_universal_rpaths_are_deduplicated(self, output):
        output.return_value = ("          cmd LC_RPATH\n      cmdsize 32\n"
                               "         path /usr/lib/swift (offset 12)\n") * 2
        self.assertEqual(runtime.rpaths(Path("Drafts")), {"/usr/lib/swift"})

    @patch.object(runtime.subprocess, "check_output")
    @patch.object(runtime, "rpaths", return_value={runtime.BUNDLE_RPATH})
    def test_missing_compatibility_library_is_rejected(self, rpaths, output):
        output.return_value = "\t@rpath/libswiftCompatibilitySpan.dylib (compatibility version 0.0.0, current version 0.0.0)\n"
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Drafts.app"
            with self.assertRaisesRegex(RuntimeError, "Missing bundled runtime"):
                runtime.verify(app)
            frameworks = app / "Contents/Frameworks"
            frameworks.mkdir(parents=True)
            (frameworks / "libswiftCompatibilitySpan.dylib").touch()
            runtime.verify(app)

    @patch.object(runtime, "rpaths", return_value={"/Applications/Xcode.app/Contents/Developer/lib/swift"})
    def test_verification_rejects_developer_search_paths(self, rpaths):
        with self.assertRaisesRegex(RuntimeError, "Nonportable runtime search path"):
            runtime.verify(Path("Drafts.app"))


if __name__ == "__main__":
    unittest.main()
