#!/usr/bin/env python3
"""Tests for build_wiki.py, on small documents written for each rule.

Run: python3 -m unittest discover -s tools/wiki -p 'test_*.py'
"""

import os
import tempfile
import unittest
from unittest import mock

import build_wiki as B

REPO = "owner/repo"
WIKI = f"/{REPO}/wiki"
RAW = f"https://raw.githubusercontent.com/{REPO}/main"

README = """# Bartleby
![Bartleby Banner](images/bartleby.png)
An intro with a [license](LICENSE) and a ![badge](images/badge.png).

**Contents**

- [Binder](#binder)
- [Setup](#setup)

See [the guide](Users_Guide.md) and [its binder](Users_Guide.md#binder).

## Binder

Keys are in [Setup](#setup), and options in [Options](#options).

```vim
# A comment in code, not a heading
var x = '](#binder)'
```

Text with `](images/code.png)` in a code span.

### Options

<img src="images/shot.png" alt="shot" width="300">

## Setup

[![CI](https://example.com/badge.svg)](images/nested.png)
"""

GUIDE = """# Bartleby User's Guide
![Bartleby Logo](images/bartleby-logo.png)

The guide.

## Contents

- [Binder](#binder)

## Binder

See [Requirements](README.md#setup) in the README.
"""

LOCALIZATION = """# Localization

About languages.

## Messages

### Rules for code
"""


class BuildWikiTest(unittest.TestCase):

    def build(self, readme=README, guide=GUIDE, localization=LOCALIZATION):
        with tempfile.TemporaryDirectory() as source:
            for name, text in [("README.md", readme), ("Users_Guide.md", guide),
                               ("Localization_README.md", localization)]:
                with open(os.path.join(source, name), "w", encoding="utf-8") as handle:
                    handle.write(text)
            return B.build(source, REPO, "main")

    def test_each_section_is_a_page_named_with_its_document(self):
        files = self.build()
        for name in ["Bartleby.md", "Bartleby-Binder.md", "Bartleby-Setup.md",
                     "Bartleby-User's-Guide.md", "User's-Guide-Binder.md",
                     "Localization.md", "Localization-Messages.md", "_Sidebar.md"]:
            self.assertIn(name, files)

    def test_the_h1_its_image_and_the_contents_are_left_out(self):
        files = self.build()
        overview = files["Bartleby.md"]
        self.assertNotIn("# Bartleby", overview)
        self.assertNotIn("bartleby.png", overview)
        self.assertNotIn("**Contents**", overview)
        self.assertNotIn("](#setup)", overview)
        self.assertIn("An intro", overview)
        self.assertNotIn("User's-Guide-Contents.md", files)
        self.assertNotIn("bartleby-logo.png)", files["Bartleby-User's-Guide.md"])

    def test_every_page_starts_with_the_mark_and_the_logo(self):
        for name, text in self.build().items():
            self.assertTrue(text.startswith(B.GENERATED_MARK), name)
            if name != B.SIDEBAR:
                self.assertIn(f'<img src="{RAW}/{B.LOGO}"', text.splitlines()[1], name)

    def test_a_hash_line_in_code_is_not_a_heading(self):
        page = self.build()["Bartleby-Binder.md"]
        self.assertIn("# A comment in code, not a heading", page)
        self.assertIn("var x = '](#binder)'", page)

    def test_links_to_sections_and_subsections_lead_to_their_pages(self):
        page = self.build()["Bartleby-Binder.md"]
        self.assertIn(f"[Setup]({WIKI}/Bartleby-Setup)", page)
        self.assertIn(f"[Options]({WIKI}/Bartleby-Binder#options)", page)

    def test_links_to_other_documents_lead_to_their_pages(self):
        files = self.build()
        self.assertIn(f"[the guide]({WIKI}/Bartleby-User%27s-Guide)", files["Bartleby.md"])
        self.assertIn(f"[its binder]({WIKI}/User%27s-Guide-Binder)", files["Bartleby.md"])
        self.assertIn(f"[Requirements]({WIKI}/Bartleby-Setup)", files["User's-Guide-Binder.md"])

    def test_relative_files_and_images_load_from_the_repository(self):
        files = self.build()
        self.assertIn(f"[license](https://github.com/{REPO}/blob/main/LICENSE)", files["Bartleby.md"])
        self.assertIn(f"![badge]({RAW}/images/badge.png)", files["Bartleby.md"])
        self.assertIn(f'<img src="{RAW}/images/shot.png"', files["Bartleby-Binder.md"])
        # The outer link of a nested image is a link, not an image.
        self.assertIn(f"(https://github.com/{REPO}/blob/main/images/nested.png)", files["Bartleby-Setup.md"])

    def test_code_spans_are_not_changed(self):
        self.assertIn("`](images/code.png)`", self.build()["Bartleby-Binder.md"])

    def test_the_sidebar_is_a_tree_rooted_at_each_h1(self):
        sidebar = self.build()["_Sidebar.md"]
        self.assertIn(f'<summary><a href="{WIKI}/Bartleby">Bartleby</a></summary>', sidebar)
        self.assertIn(f'<a href="{WIKI}/Bartleby-User%27s-Guide">Bartleby User&#x27;s Guide</a>', sidebar)
        self.assertIn(f'<a href="{WIKI}/Localization-Messages#rules-for-code">Rules for code</a>', sidebar)
        self.assertLess(sidebar.index(">Bartleby<"), sidebar.index(">Localization<"))

    def test_pages_link_to_the_previous_and_next_section(self):
        files = self.build()
        self.assertIn(f"[Setup →]({WIKI}/Bartleby-Setup)", files["Bartleby-Binder.md"])
        self.assertIn(f"[← Binder]({WIKI}/Bartleby-Binder)", files["Bartleby-Setup.md"])

    def test_repeated_page_names_fail(self):
        readme = README + "\n## Binder\n\nAgain.\n"
        with mock.patch.object(B, "DOCUMENTS", [("README.md", "Bartleby"), ("Users_Guide.md", "Bartleby"),
                                                ("Localization_README.md", "Localization")]):
            with self.assertRaises(ValueError):
                self.build(readme=readme, guide="# Other\n\n## Binder\n")

    def test_a_document_without_an_h1_fails(self):
        with self.assertRaises(ValueError):
            self.build(localization="No title.\n")

    def test_old_generated_pages_go_and_hand_written_pages_stay(self):
        with tempfile.TemporaryDirectory() as wiki:
            for name, text in [("Home.md", "Welcome\n"),
                               ("Bartleby-Gone.md", f"{B.GENERATED_MARK} README.md. -->\nOld\n")]:
                with open(os.path.join(wiki, name), "w", encoding="utf-8") as handle:
                    handle.write(text)
            written, deleted = B.write(wiki, self.build())
            self.assertEqual(["Bartleby-Gone.md"], deleted)
            self.assertTrue(os.path.exists(os.path.join(wiki, "Home.md")))
            self.assertIn("Bartleby-Binder.md", written)
            # A second run changes nothing.
            self.assertEqual(([], []), B.write(wiki, self.build()))


if __name__ == "__main__":
    unittest.main()
