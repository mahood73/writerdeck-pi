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

    def _create_fake_wordgrinder(self, docs):
        """
        Create a fake wordgrinder script that handles --lua export calls.
        docs: list of (name, content) tuples, one per document.
        Returns the bin directory Path — prepend to PATH when calling _run.
        """
        import json as _json
        fake_bin = Path(self.tmp.name) / "wg-bin"
        fake_bin.mkdir(exist_ok=True)

        data_file = fake_bin / "docs.json"
        data_file.write_text(_json.dumps(docs), encoding="utf-8")

        fake_wg = fake_bin / "wordgrinder"
        data_path_repr = repr(str(data_file))
        script = (
            "#!/usr/bin/env python3\n"
            "import sys, pathlib, json\n"
            "if len(sys.argv) >= 2 and sys.argv[1] == '--lua':\n"
            f"    data_file = pathlib.Path({data_path_repr})\n"
            "    wg_path = sys.argv[3]\n"
            "    tmpdir = sys.argv[4]\n"
            "    docs = json.loads(data_file.read_text(encoding='utf-8'))\n"
            "    for i, (name, content) in enumerate(docs, 1):\n"
            "        idx = f'{i:03d}'\n"
            "        out = pathlib.Path(tmpdir, idx + '.txt')\n"
            "        out.write_text(content, encoding='utf-8')\n"
            "        print(name + '\\t' + str(out))\n"
            "    sys.exit(0)\n"
            "sys.exit(0)\n"
        )
        fake_wg.write_text(script, encoding="utf-8")
        fake_wg.chmod(fake_wg.stat().st_mode | stat.S_IXUSR)
        return fake_bin

    def _run_export(self, fake_wg_bin, *args):
        env = os.environ.copy()
        env["WD_CONFIG"] = str(self.config_path)
        env["PATH"] = str(fake_wg_bin) + os.pathsep + env.get("PATH", "")
        return subprocess.run(
            [sys.executable, str(WD_BIN), "export", *args],
            env=env,
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_export_latest_creates_combined_txt(self):
        # Create a .wg file in the writing root
        draft_dir = self.root / "inbox"
        draft_dir.mkdir(parents=True)
        draft = draft_dir / "2026-05-11_1200_draft.wg"
        draft.write_text("", encoding="utf-8")

        fake_wg_bin = self._create_fake_wordgrinder([("My Draft", "Hello world.")])
        result = self._run_export(fake_wg_bin)

        self.assertEqual(result.returncode, 0, result.stderr)
        out_file = draft_dir / "exports" / "2026-05-11_1200_draft.txt"
        self.assertTrue(out_file.exists())
        content = out_file.read_text(encoding="utf-8")
        self.assertIn("# My Draft", content)
        self.assertIn("Hello world.", content)

    def test_export_multi_doc_combined(self):
        draft_dir = self.root / "longform"
        draft_dir.mkdir(parents=True)
        draft = draft_dir / "novel.wg"
        draft.write_text("", encoding="utf-8")

        fake_wg_bin = self._create_fake_wordgrinder([
            ("Chapter One", "Text of chapter one."),
            ("Chapter Two", "Text of chapter two."),
        ])
        result = self._run_export(fake_wg_bin, str(draft))

        self.assertEqual(result.returncode, 0, result.stderr)
        out_file = draft_dir / "exports" / "novel.txt"
        content = out_file.read_text(encoding="utf-8")
        self.assertIn("# Chapter One", content)
        self.assertIn("Text of chapter one.", content)
        self.assertIn("# Chapter Two", content)
        self.assertIn("Text of chapter two.", content)
        # Chapters must appear in order
        self.assertLess(content.index("# Chapter One"), content.index("# Chapter Two"))

    def test_export_explicit_path(self):
        draft_dir = self.root / "inbox"
        draft_dir.mkdir(parents=True)
        draft = draft_dir / "specific.wg"
        draft.write_text("", encoding="utf-8")

        fake_wg_bin = self._create_fake_wordgrinder([("Doc", "Content here.")])
        result = self._run_export(fake_wg_bin, str(draft))

        self.assertEqual(result.returncode, 0, result.stderr)
        out_file = draft_dir / "exports" / "specific.txt"
        self.assertTrue(out_file.exists())

    def test_export_all(self):
        for name in ("alpha.wg", "beta.wg"):
            d = self.root / "inbox"
            d.mkdir(parents=True, exist_ok=True)
            (d / name).write_text("", encoding="utf-8")

        fake_wg_bin = self._create_fake_wordgrinder([("Doc", "Some text.")])
        result = self._run_export(fake_wg_bin, "--all")

        self.assertEqual(result.returncode, 0, result.stderr)
        exports = list((self.root / "inbox" / "exports").glob("*.txt"))
        self.assertEqual(len(exports), 2)

    def test_export_no_drafts_error(self):
        fake_wg_bin = self._create_fake_wordgrinder([])
        result = self._run_export(fake_wg_bin)

        self.assertEqual(result.returncode, 1)
        self.assertIn("no .wg files found", result.stderr)

    def test_export_path_and_all_error(self):
        draft_dir = self.root / "inbox"
        draft_dir.mkdir(parents=True)
        draft = draft_dir / "draft.wg"
        draft.write_text("", encoding="utf-8")

        fake_wg_bin = self._create_fake_wordgrinder([("Doc", "Text.")])
        result = self._run_export(fake_wg_bin, str(draft), "--all")

        self.assertEqual(result.returncode, 1)
        self.assertIn("mutually exclusive", result.stderr)

    def test_export_prints_hint_on_default(self):
        draft_dir = self.root / "inbox"
        draft_dir.mkdir(parents=True)
        draft = draft_dir / "2026-05-11_1200_draft.wg"
        draft.write_text("", encoding="utf-8")

        fake_wg_bin = self._create_fake_wordgrinder([("Doc", "Text.")])

        # Default invocation: hint should appear
        result = self._run_export(fake_wg_bin)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Tip:", result.stdout)

        # Explicit path: no hint
        result2 = self._run_export(fake_wg_bin, str(draft))
        self.assertEqual(result2.returncode, 0, result2.stderr)
        self.assertNotIn("Tip:", result2.stdout)


    def test_export_wordgrinder_failure_returns_error(self):
        draft_dir = self.root / "inbox"
        draft_dir.mkdir(parents=True)
        draft = draft_dir / "draft.wg"
        draft.write_text("", encoding="utf-8")

        # Create a fake wordgrinder that exits non-zero
        fake_bin = Path(self.tmp.name) / "wg-bin"
        fake_bin.mkdir(exist_ok=True)
        fake_wg = fake_bin / "wordgrinder"
        fake_wg.write_text(
            "#!/usr/bin/env python3\nimport sys\nsys.stderr.write('export failed\\n')\nsys.exit(1)\n",
            encoding="utf-8",
        )
        fake_wg.chmod(fake_wg.stat().st_mode | stat.S_IXUSR)

        result = self._run_export(fake_bin, str(draft))
        self.assertEqual(result.returncode, 1)
        self.assertIn("error", result.stderr)


if __name__ == "__main__":
    unittest.main()
