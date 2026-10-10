"""Tests for build_cheatsheet.py. Run from the root of the repository:

    python3 -m unittest discover -s tools/cheatsheet -p 'test_*.py' -v

The tests of the build need xelatex and its fonts. Without them they are
skipped, unless CHEATSHEET_REQUIRE_ENGINE is set, as in the workflow, where
a missing engine is a failure.
"""

import functools
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_cheatsheet as B  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]

SMALL = """# Test Card

Intro with `code`.

## First group

### One

| Key | Action |
| --- | --- |
| `a` | alpha |
| `b` | beta |

### Two

| Key | Action |
| --- | --- |
| `c` | gamma |

<!-- newpage -->

## Second group

### Three

| Key | Action |
| --- | --- |
| `d` | delta |

A note under the table.
"""


def tall_source(rows):
    body = "\n".join(f"| `k{i}` | Row number {i} of a table that is taller than a column |" for i in range(rows))
    return f"# Tall\n\n## Group\n\n### Long table\n\n| Key | Action |\n| --- | --- |\n{body}\n"


def engine_present():
    """Return True when the engine and the two fonts of the card are here.
    A build is not tried, so that a broken build fails its tests instead of
    skipping them."""
    if not shutil.which(B.LATEX_ENGINE):
        return False
    gyre = subprocess.run(["kpsewhich", "texgyreheros-regular.otf"], capture_output=True, text=True)
    if not shutil.which("fc-match") or not gyre.stdout.strip():
        return False
    mono = subprocess.run(["fc-match", B.MONO_FONT], capture_output=True, text=True).stdout
    return B.MONO_FONT in mono


def need_engine(test):
    """Run the test only where the engine is here. In the workflow, where
    CHEATSHEET_REQUIRE_ENGINE is set, a missing engine fails the test."""
    @functools.wraps(test)
    def wrapper(self, *args, **kwargs):
        if not engine_present():
            if os.environ.get("CHEATSHEET_REQUIRE_ENGINE"):
                self.fail(f"{B.LATEX_ENGINE} or its fonts are missing")
            self.skipTest(f"{B.LATEX_ENGINE} or its fonts are missing")
        return test(self, *args, **kwargs)
    return wrapper


class InlineTest(unittest.TestCase):
    def test_code_is_monospace_and_escaped(self):
        self.assertEqual(r"\cscode{a\_b <Tab> 50\%}", B.inline_to_latex("`a_b <Tab> 50%`"))

    def test_double_backticks_hold_a_backtick(self):
        self.assertEqual(r"\cscode{a`b}", B.inline_to_latex("``a`b``"))

    def test_an_open_backtick_is_text(self):
        self.assertEqual("a`b", B.inline_to_latex("a`b"))

    def test_bold_and_italic(self):
        self.assertEqual(r"\textbf{x} and \textit{y}", B.inline_to_latex("**x** and *y*"))

    def test_a_lone_asterisk_is_a_character(self):
        self.assertEqual("5 * 3 * 2", B.inline_to_latex("5 * 3 * 2"))

    def test_a_backslash_makes_punctuation_literal(self):
        self.assertEqual("a|b", B.inline_to_latex(r"a\|b"))

    def test_special_characters_are_escaped(self):
        self.assertEqual(r"\& \# \$ \{\} \textasciitilde{}", B.inline_to_latex("& # $ {} ~"))


class ParseTest(unittest.TestCase):
    def test_a_document_has_a_title_an_intro_and_flows(self):
        document = B.parse_markdown(SMALL)
        self.assertEqual("Test Card", document.title)
        self.assertEqual([r"Intro with \cscode{code}."], document.intro)
        self.assertEqual([2, 2], [len(flow) for flow in document.flows])

    def test_a_heading_is_the_title_of_its_table(self):
        table = B.parse_markdown(SMALL).flows[0][0]
        self.assertEqual("One", table.title)
        self.assertEqual([(r"\cscode{a}", "alpha"), (r"\cscode{b}", "beta")], table.rows)

    def test_the_header_row_of_the_markdown_table_is_left_out(self):
        rows = B.parse_markdown(SMALL).flows[0][0].rows
        self.assertNotIn("Key", " ".join(key for key, _ in rows))

    def test_a_note_belongs_to_its_flow(self):
        last = B.parse_markdown(SMALL).flows[1][-1]
        self.assertIsInstance(last, B.Note)
        self.assertEqual("A note under the table.", last.text)

    def test_tables_and_notes_are_numbered_over_all_flows(self):
        document = B.parse_markdown(SMALL)
        self.assertEqual([0, 1, 2], [t.ident for flow in document.flows for t in flow if isinstance(t, B.Table)])

    def test_an_empty_flow_is_dropped(self):
        text = SMALL.replace("<!-- newpage -->", "<!-- newpage -->\n\n<!-- newpage -->")
        self.assertEqual(2, len(B.parse_markdown(text).flows))

    def test_an_escaped_pipe_stays_in_its_cell(self):
        text = "# T\n\n## G\n\n### X\n\n| a | b |\n| --- | --- |\n| `a\\|b` | c |\n"
        self.assertEqual([(r"\cscode{a|b}", "c")], B.parse_markdown(text).flows[0][0].rows)

    def test_a_comment_over_several_lines_is_skipped(self):
        text = "<!--\n a\n b\n-->\n" + SMALL
        self.assertEqual("Test Card", B.parse_markdown(text).title)

    def assertFails(self, text, message):
        with self.assertRaises(B.ConverterError) as caught:
            B.parse_markdown(text, "x.md")
        self.assertIn(message, str(caught.exception))
        self.assertTrue(str(caught.exception).startswith("x.md:"))

    def test_errors_name_the_line(self):
        self.assertFails("# T\n\n## G\n\n| a | b |\n| --- | --- |\n| c | d |\n", "needs a ### heading")
        self.assertFails("# T\n\n### X\n\n| a | b | c |\n| --- | --- | --- |\n| 1 | 2 | 3 |\n", "exactly two columns")
        self.assertFails("# T\n\n### X\n\n| a | b |\n| --- | --- |\n| 1 |\n", "exactly two columns")
        self.assertFails("# T\n\n### X\n\n| a | b |\n| 1 | 2 |\n", "dashes")
        self.assertFails("# T\n\n### X\n\n| a | b |\n| --- | --- |\n", "at least one row")
        self.assertFails("# T\n\n### X\n\nText.\n", "followed by its table")
        self.assertFails("# T\n\n### X\n", "followed by its table")
        self.assertFails("# T\n\n### X\n\n<!-- newpage -->\n", "followed by its table")
        self.assertFails("## G\n", "must come first")
        self.assertFails("# T\n\n# U\n", "only one")
        self.assertFails("# T\n\n#### X\n", "level 4")
        self.assertFails("# T\n\n- a list\n", "not supported")
        self.assertFails("# T\n\n```\ncode\n```\n", "not supported")
        self.assertFails("# T\n\nOnly text.\n", "no tables")
        self.assertFails("Text first.\n", "must come first")


class LayoutTest(unittest.TestCase):
    def table(self, rows, head=10.0, height=10.0):
        return ("table", head, [height] * rows)

    def rows_of(self, columns):
        return [(p.ident, p.first, p.last) for column in columns for p in column if p.kind == "table"]

    def test_tables_fill_a_column_in_order(self):
        columns = B.fill([self.table(2), self.table(2)], [200.0], 200.0)
        self.assertEqual(1, len(columns))
        self.assertEqual([(0, 0, 2), (1, 0, 2)], self.rows_of(columns))

    def test_a_table_that_does_not_fit_moves_whole_to_the_next_column(self):
        columns = B.fill([self.table(5), self.table(5)], [100.0], 100.0)
        self.assertEqual([[(0, 0, 5)], [(1, 0, 5)]], [self.rows_of([c]) for c in columns])
        self.assertTrue(all(not p.continued for c in columns for p in c))

    def test_the_gap_between_tables_counts(self):
        # 40 + 7 + 40 fits 90, and 40 + 7 + 50 does not.
        self.assertEqual(1, len(B.fill([self.table(3), self.table(3)], [90.0], 90.0, gap=7.0)))
        self.assertEqual(2, len(B.fill([self.table(3), self.table(4)], [90.0], 90.0, gap=7.0)))

    def test_a_table_taller_than_a_column_is_split_and_continued(self):
        columns = B.fill([self.table(30)], [100.0], 100.0)
        pieces = [p for c in columns for p in c]
        self.assertEqual([False, True, True, True], [p.continued for p in pieces])
        self.assertEqual(list(range(30)), [r for p in pieces for r in range(p.first, p.last)])
        self.assertTrue(all(p.height <= 100.0 + B.EPSILON for p in pieces))

    def test_a_split_never_leaves_a_single_row_alone(self):
        pieces = [p for c in B.fill([self.table(28)], [100.0], 100.0) for p in c]
        self.assertEqual(28, sum(p.last - p.first for p in pieces))
        self.assertGreaterEqual(pieces[-1].last - pieces[-1].first, 2)

    def test_a_split_starts_in_the_current_column_when_it_has_room(self):
        columns = B.fill([self.table(3), self.table(30)], [100.0], 100.0, gap=7.0)
        self.assertEqual(2, len(columns[0]))
        self.assertEqual((0, 4), (columns[0][1].first, columns[0][1].last))
        self.assertFalse(columns[0][1].continued)

    def test_a_split_moves_on_when_too_few_rows_would_fit(self):
        columns = B.fill([self.table(7), self.table(30)], [100.0], 100.0, gap=7.0)
        self.assertEqual([1], [len(c) for c in columns[:1]])
        self.assertEqual(0, columns[1][0].first)
        self.assertFalse(columns[1][0].continued)

    def test_a_note_is_whole(self):
        columns = B.fill([("note", 30.0), ("note", 30.0), ("note", 30.0)], [70.0], 70.0)
        self.assertEqual([2, 1], [len(c) for c in columns])

    def test_too_many_columns_give_none(self):
        self.assertIsNone(B.fill([self.table(30)], [100.0], 100.0, max_columns=2))

    def test_the_first_page_can_be_shorter(self):
        items = [self.table(5)] * 6
        pages = B.layout_flow(items, 60.0, 200.0, balance=False)
        self.assertEqual(2, len(pages))
        self.assertEqual([1, 1, 1], [len(c) for c in pages[0]])
        self.assertTrue(all(len(c) <= 3 for c in pages[1]))

    def test_the_last_page_is_balanced(self):
        items = [self.table(5)] * 6
        plain = B.layout_flow(items, 60.0, 200.0, balance=False)
        balanced = B.layout_flow(items, 60.0, 200.0, balance=True)
        self.assertEqual(len(plain), len(balanced))
        self.assertEqual([1, 1, 1], [len(c) for c in balanced[-1]])
        self.assertGreater(len(plain[-1][0]), len(balanced[-1][0]))

    def test_every_page_has_three_columns_and_nothing_is_lost(self):
        items = [self.table(8)] * 7 + [self.table(60)]
        pages = B.layout_flow(items, 120.0, 150.0)
        self.assertTrue(all(len(page) == 3 for page in pages))
        rows = sum(p.last - p.first for page in pages for c in page for p in c)
        self.assertEqual(7 * 8 + 60, rows)

    def test_balancing_never_adds_a_page(self):
        for count in range(1, 12):
            items = [self.table(6)] * count
            self.assertEqual(len(B.layout_flow(items, 90.0, 120.0, balance=False)),
                             len(B.layout_flow(items, 90.0, 120.0, balance=True)), count)


class LatexTest(unittest.TestCase):
    def source(self):
        text = tall_source(12)
        document = B.parse_markdown(text)
        items = [("table", 10.0, [10.0] * 12)]
        # Five rows fit a column, so that the parts of 5, 5, and 2 rows show
        # whether the colors go on from one part to the next.
        pages = B.layout_flow_items(document.flows[0], items, 66.0 + B.EPSILON, 66.0 + B.EPSILON, balance=False)
        return B.final_source(document, [pages], 30.0), pages

    def test_a_table_taller_than_a_column_continues_with_its_header(self):
        tex, pages = self.source()
        pieces = [p for page in pages for c in page for p in c]
        self.assertGreater(len(pieces), 1)
        self.assertEqual(1, tex.count(r"\cstable{Long table}"))
        self.assertEqual(len(pieces) - 1, tex.count(r"\cstable{Long table (Cont'd)}"))

    def test_the_rows_alternate_over_the_parts_of_a_table(self):
        tex, _ = self.source()
        colors = re.findall(r"\\rowcolor\{(csrow[ab])\}", tex)
        self.assertEqual(12, len(colors))
        self.assertEqual(["csrowa", "csrowb"] * 6, colors)

    def test_the_colors_are_those_of_the_card(self):
        tex = B.preamble()
        self.assertIn(r"\definecolor{csheadbg}{HTML}{000000}", tex)
        self.assertIn(r"\definecolor{csheadfg}{HTML}{FFFFFF}", tex)
        self.assertIn(r"\definecolor{csrowa}{HTML}{FFFFFF}", tex)
        self.assertIn(r"\definecolor{csrowb}{HTML}{D6EAF5}", tex)

    def test_the_header_is_white_on_black_and_spans_both_columns(self):
        header = re.search(r"\\newcommand\{\\cshead\}.*", B.preamble()).group(0)
        self.assertIn(r"\rowcolor{csheadbg}", header)
        self.assertIn(r"\multicolumn{2}{l}{\color{csheadfg}", header)

    def test_the_rules_are_horizontal_only_and_the_cells_left_aligned(self):
        spec = B.key_spec()
        self.assertNotIn("|", spec)
        self.assertEqual(2, spec.count(r"\raggedright"))
        self.assertTrue(B.row_tex("k", "d", 0).endswith(r"\\\hline"))

    def test_the_measures_are_read_from_a_log(self):
        log = "x\nCSM T 40.5pt\nCSM G 553.9pt 236.4pt\nCSM H 0 15.2pt\nCSM R 0 3 11.9pt\nCSM N 2 22.0pt\ny\n"
        measures = B.parse_measures(log)
        self.assertEqual((40.5, None), measures[("T",)])
        self.assertEqual((553.9, 236.4), measures[("G",)])
        self.assertEqual(15.2, measures[("H", 0)][0])
        self.assertEqual(11.9, measures[("R", 0, 3)][0])
        self.assertEqual(22.0, measures[("N", 2)][0])


class BuildTest(unittest.TestCase):
    def build(self, text, name="card"):
        folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, folder, True)
        source = folder / f"{name}.md"
        source.write_text(text, encoding="utf-8")
        pages = B.build(source, folder / f"{name}.pdf")
        return pages, folder / f"{name}.pdf"

    def text_of(self, pdf):
        if not shutil.which("pdftotext"):
            self.skipTest("pdftotext is missing")
        text = subprocess.run(["pdftotext", "-layout", str(pdf), "-"], capture_output=True, text=True).stdout
        # The font sets the apostrophe as a typographic one.
        return text.replace("\u2019", "'")

    @need_engine
    def test_a_flow_starts_a_new_page(self):
        pages, pdf = self.build(SMALL)
        self.assertEqual(2, pages)
        self.assertTrue(pdf.read_bytes().startswith(b"%PDF"))

    @need_engine
    def test_a_table_taller_than_a_column_is_continued_in_the_pdf(self):
        _, pdf = self.build(tall_source(150))
        text = self.text_of(pdf)
        self.assertIn("Long table", text)
        self.assertIn("(Cont'd)", text)
        for number in (0, 75, 149):
            self.assertIn(f"Row number {number} ", text)

    @need_engine
    def test_a_short_table_is_not_continued(self):
        _, pdf = self.build(SMALL)
        self.assertNotIn("Cont'd", self.text_of(pdf))

    @need_engine
    def test_the_text_of_the_card_is_in_the_pdf(self):
        _, pdf = self.build(SMALL)
        text = self.text_of(pdf)
        for word in ("Test Card", "Intro with", "alpha", "delta", "A note under the table."):
            self.assertIn(word, text)

    @need_engine
    def test_a_build_is_the_same_every_time(self):
        os.environ["SOURCE_DATE_EPOCH"] = "1700000000"
        self.addCleanup(os.environ.pop, "SOURCE_DATE_EPOCH", None)
        _, first = self.build(SMALL, "first")
        _, second = self.build(SMALL, "second")
        self.assertEqual(first.read_bytes(), second.read_bytes())

    @need_engine
    def test_a_key_too_wide_for_its_column_fails_the_build(self):
        text = "# T\n\n## G\n\n### X\n\n| a | b |\n| --- | --- |\n| `" + "W" * 70 + "` | text |\n"
        with self.assertRaises(B.ConverterError) as caught:
            self.build(text)
        self.assertIn("too wide", str(caught.exception))

    @need_engine
    def test_a_character_the_font_lacks_fails_the_build(self):
        text = "# T\n\n## G\n\n### X\n\n| a | b |\n| --- | --- |\n| `k` | \u2603\U0001F600 |\n"
        with self.assertRaises(B.ConverterError) as caught:
            self.build(text)
        self.assertIn("missing", str(caught.exception))


class SheetTest(unittest.TestCase):
    """The cheat sheet of the repository is valid, complete, and builds."""

    def source(self):
        return (ROOT / B.DEFAULT_SOURCE).read_text(encoding="utf-8")

    def plugin_text(self):
        """Return the plugin with each continuation line joined to its line,
        so that a command defined over more than one line is seen."""
        text = (ROOT / "plugin" / "bartleby.vim").read_text(encoding="utf-8")
        return re.sub(r"\n\s*\\", " ", text)

    def test_the_sheet_is_valid(self):
        document = B.parse_markdown(self.source(), B.DEFAULT_SOURCE)
        self.assertGreaterEqual(len(document.flows), 2)

    def test_every_command_of_the_plugin_is_on_the_sheet(self):
        commands = set(re.findall(r"^command!.*?\b(Bartleby\w+)", self.plugin_text(), re.M))
        self.assertGreater(len(commands), 20)
        # Defined over two lines in the plugin.
        self.assertIn("BartlebyOpen", commands)
        missing = sorted(c for c in commands if f":{c}" not in self.source())
        self.assertEqual([], missing, "add these commands to doc/cheatsheet.md")

    def test_every_leader_mapping_of_the_plugin_is_on_the_sheet(self):
        mappings = set(re.findall(r"[nx]noremap <silent> (<leader>b\S+)", self.plugin_text()))
        self.assertGreater(len(mappings), 5)
        missing = sorted(m for m in mappings if f"`{m}`" not in self.source())
        self.assertEqual([], missing, "add these mappings to doc/cheatsheet.md")

    @need_engine
    def test_the_sheet_builds_with_the_user_commands_on_the_first_page(self):
        with tempfile.TemporaryDirectory() as folder:
            pdf = Path(folder) / "sheet.pdf"
            pages = B.build(ROOT / B.DEFAULT_SOURCE, pdf)
            self.assertGreaterEqual(pages, 2)
            if shutil.which("pdftotext"):
                first = subprocess.run(["pdftotext", "-f", "1", "-l", "1", "-layout", str(pdf), "-"],
                                       capture_output=True, text=True).stdout
                self.assertIn(":BartlebyCommands", first)
                self.assertNotIn("<leader>bi", first)


if __name__ == "__main__":
    unittest.main()
