import os
import stat
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
        self.editor_log_path = Path(self.tmp.name) / "editor.log"
        self.fake_editor = self._create_fake_editor("editor")
        self._write_config(str(self.fake_editor))

    def _create_fake_editor(self, name):
        fake_bin = Path(self.tmp.name) / "bin"
        fake_bin.mkdir(exist_ok=True)
        fake_editor = fake_bin / name
        fake_editor.write_text(
            textwrap.dedent(
                f"""\
                #!/bin/sh
                printf '%s|%s\\n' "$(pwd)" "$*" >> "{self.editor_log_path}"
                if [ "$#" -gt 0 ]; then
                  : > "$1"
                fi
                """
            ),
            encoding="utf-8",
        )
        fake_editor.chmod(fake_editor.stat().st_mode | stat.S_IXUSR)
        return fake_editor

    def _write_config(self, editor_command):
        content = textwrap.dedent(
            f"""
            [paths]
            root = \"{self.root}\"
            default_project = \"inbox\"

            [editor]
            command = \"{editor_command}\"

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
        drafts = list((self.root / "inbox").glob("*.wg"))
        self.assertEqual(len(drafts), 1)

    def test_new_creates_project_draft(self):
        result = self._run("new", "notes")
        self.assertEqual(result.returncode, 0, result.stderr)
        drafts = list((self.root / "notes").glob("*.wg"))
        self.assertEqual(len(drafts), 1)
        self.assertTrue(drafts[0].name.endswith("_draft.wg"))

    def test_new_opens_blank_wordgrinder_without_creating_invalid_draft(self):
        fake_wordgrinder = Path(self.tmp.name) / "bin" / "wordgrinder"
        fake_wordgrinder.write_text(
            textwrap.dedent(
                f"""\
                #!/bin/sh
                printf '%s|%s\\n' "$(pwd)" "$*" >> "{self.editor_log_path}"
                """
            ),
            encoding="utf-8",
        )
        fake_wordgrinder.chmod(fake_wordgrinder.stat().st_mode | stat.S_IXUSR)
        self._write_config(str(fake_wordgrinder))

        result = self._run("new", "notes")
        self.assertEqual(result.returncode, 0, result.stderr)

        drafts = list((self.root / "notes").glob("*.wg"))
        self.assertEqual(drafts, [])
        self.assertTrue((self.root / "notes").is_dir())
        calls = self.editor_log_path.read_text(encoding="utf-8").splitlines()
        self.assertEqual(calls, [f"{(self.root / 'notes').resolve()}|"])
        self.assertIn("Save it under:", result.stdout)

    def test_new_without_folder_uses_default_project_for_wordgrinder(self):
        fake_wordgrinder = Path(self.tmp.name) / "bin" / "wordgrinder"
        fake_wordgrinder.write_text(
            textwrap.dedent(
                f"""\
                #!/bin/sh
                printf '%s|%s\\n' "$(pwd)" "$*" >> "{self.editor_log_path}"
                """
            ),
            encoding="utf-8",
        )
        fake_wordgrinder.chmod(fake_wordgrinder.stat().st_mode | stat.S_IXUSR)
        self._write_config(str(fake_wordgrinder))

        result = self._run("new")
        self.assertEqual(result.returncode, 0, result.stderr)

        self.assertTrue((self.root / "inbox").is_dir())
        calls = self.editor_log_path.read_text(encoding="utf-8").splitlines()
        self.assertEqual(calls, [f"{(self.root / 'inbox').resolve()}|"])
        self.assertIn("Save it under:", result.stdout)

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
