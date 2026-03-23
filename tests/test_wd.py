import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
WD_BIN = REPO_ROOT / "bin" / "wd"


class WriterDeckCliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "projects"
        self.config_path = Path(self.tmp.name) / "config.toml"
        self._write_config()

    def _write_config(self):
        content = textwrap.dedent(
            f"""
            [paths]
            root = \"{self.root}\"
            default_project = \"inbox\"

            [editor]
            command = \"true\"

            [sync]
            folder_id = \"writing\"
            mode = \"single_writer\"
            wait_timeout_sec = 2
            """
        ).strip()
        self.config_path.write_text(content, encoding="utf-8")

    def _run(self, *args):
        env = os.environ.copy()
        env["WD_CONFIG"] = str(self.config_path)
        return subprocess.run(
            [sys.executable, str(WD_BIN), *args],
            env=env,
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_open_latest_creates_initial_inbox_file(self):
        result = self._run("open-latest")
        self.assertEqual(result.returncode, 0, result.stderr)
        drafts = list((self.root / "inbox").glob("*.md"))
        self.assertEqual(len(drafts), 1)

    def test_new_creates_project_draft(self):
        result = self._run("new", "notes", "first-draft")
        self.assertEqual(result.returncode, 0, result.stderr)
        drafts = list((self.root / "notes").glob("*.md"))
        self.assertEqual(len(drafts), 1)
        self.assertTrue(drafts[0].name.endswith("_first-draft.md"))

    def test_projects_lists_directories(self):
        (self.root / "alpha").mkdir(parents=True)
        (self.root / "beta").mkdir(parents=True)
        result = self._run("projects")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip().splitlines(), ["alpha", "beta"])

    def test_sync_doctor_reports_conflicts(self):
        project = self.root / "notes"
        project.mkdir(parents=True)
        (project / "draft.md").write_text("base", encoding="utf-8")
        conflict = project / "draft.md.sync-conflict-20260303-120000-WRITER"
        conflict.write_text("conflict", encoding="utf-8")

        result = self._run("sync", "doctor")
        self.assertEqual(result.returncode, 1)
        self.assertIn("found 1 conflict file(s)", result.stdout)
        self.assertIn("notes/draft.md.sync-conflict", result.stdout)

    def test_sync_resolve_requires_conflict_copy(self):
        project = self.root / "notes"
        project.mkdir(parents=True)
        (project / "draft.md").write_text("base", encoding="utf-8")

        result = self._run("sync", "resolve", "notes/draft.md")
        self.assertEqual(result.returncode, 1)
        self.assertIn("no conflict copies found", result.stderr)


if __name__ == "__main__":
    unittest.main()
