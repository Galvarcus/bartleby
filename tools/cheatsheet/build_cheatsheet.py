#!/usr/bin/env python3
"""Build the cheat sheet PDF from its Markdown source, with xelatex.

The source is doc/cheatsheet.md. Its layout rules are:

  # Title             The title of the card, with the paragraphs after it.
  ## Group            Structure for the reader of the Markdown. Not printed.
  ### Table title     The black header row of the table that follows.
  | Key | Action |    A table of two columns. Its first row is for readers
  | --- | --- |      of the Markdown and is left out of the PDF.
  | `x` | text |
  <!-- newpage -->    Everything after it starts on a new page.
  A paragraph in a group is printed as a note, in a column.

A page has three columns. A table goes into a column whole, or moves to the
next column when it does not fit. Only a table that is taller than a column
is split, and each part after the first has (Cont'd) in its header.

LaTeX cannot place the tables this way by itself, so the build runs xelatex
twice. The first pass measures each row. This script places the tables by
those measures. The second pass sets the result in columns of fixed height.

Python 3, standard library only, and xelatex with the packages that
preamble() loads.
"""

import argparse
import dataclasses
import hashlib
import math
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# The files, relative to the working directory. The workflow uses these.
DEFAULT_SOURCE = "doc/cheatsheet.md"
DEFAULT_OUTPUT = "cheatsheet.pdf"

LATEX_ENGINE = "xelatex"
# The time in the PDF when no other is known, so that a build is the same
# every time. It is the time of the last commit of the source when git
# knows it, or SOURCE_DATE_EPOCH when that is set.
FALLBACK_EPOCH = 1767225600

# The page. Lengths are TeX lengths.
PAPER = "letterpaper"
MARGIN = "0.4in"
COLUMNS = 3
COLUMN_SEP = "14pt"
MAIN_FONT = "TeX Gyre Heros"
MONO_FONT = "DejaVu Sans Mono"
MONO_SCALE = 0.80
FONT_SIZE = 8.5
LEADING = 10.5
TITLE_SIZE = 17.0
ARRAY_STRETCH = 1.35
TAB_COL_SEP = "4pt"
RULE_WIDTH = "0.4pt"
RULE_COLOR = "7A7A7A"
KEY_FRACTION = 0.50

# The colors, as hex. Rows alternate in order, starting with the first.
HEADER_BACKGROUND = "000000"
HEADER_TEXT = "FFFFFF"
ROW_COLORS = ("FFFFFF", "D6EAF5")
CONTINUED = "(Cont'd)"

# The space between tables, and under the title, in points. EPSILON is
# the room that the placement leaves, because the measures and the typeset
# page differ by rounding.
TABLE_GAP = 7.0
TITLE_GAP = 8.0
EPSILON = 0.6
# A split table leaves at least this many rows in each part.
MIN_ROWS = 3
# The most columns that a layout may use, as a guard against a loop.
MAX_COLUMNS = 300

NEWPAGE = re.compile(r"^<!--\s*newpage\s*-->\s*$", re.IGNORECASE)
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
SEPARATOR_CELL = re.compile(r"^:?-{3,}:?$")
UNSUPPORTED = re.compile(r"^([-*+]|\d+[.)])\s|^>|^```|^~~~")
PUNCTUATION = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"


class ConverterError(Exception):
    """A problem in the source or in the build, with where it is."""


##############################################################################
# Markdown
##############################################################################

LATEX_SPECIAL = {
    "\\": r"\textbackslash{}", "{": r"\{", "}": r"\}", "$": r"\$",
    "&": r"\&", "#": r"\#", "^": r"\^{}", "_": r"\_", "%": r"\%",
    "~": r"\textasciitilde{}",
}


def latex_escape(text):
    """Return text with the characters that LaTeX reads as commands escaped."""
    return "".join(LATEX_SPECIAL.get(c, c) for c in text)


def emphasis_end(text, start, size):
    """Return where the emphasis that opens at start with size asterisks
    closes, or -1. As in Markdown, no space follows the opening or comes
    before the closing, so that a lone * stays a character."""
    mark = "*" * size
    if not text.startswith(mark, start) or text[start + size:start + size + 1] in ("", " ", "*"):
        return -1
    end = text.find(mark, start + size + 1)
    while end > 0 and text[end - 1] == " ":
        end = text.find(mark, end + 1)
    return end


def inline_to_latex(text):
    """Return text with its inline Markdown as LaTeX.

    Supported: `code`, **bold**, *italic*, and a backslash before
    punctuation, as in \\|, which makes the character literal.
    """
    out = []
    i = 0
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text) and text[i + 1] in PUNCTUATION:
            out.append(latex_escape(text[i + 1]))
            i += 2
        elif c == "`":
            run = len(re.match(r"`+", text[i:]).group())
            close = re.search(r"(?<!`)" + "`" * run + r"(?!`)", text[i + run:])
            if close is None:
                out.append(latex_escape("`" * run))
                i += run
                continue
            # As on GitHub, \| in a table cell is a pipe, also in code.
            code = text[i + run:i + run + close.start()].replace("\\|", "|")
            if len(code) > 1 and code[0] == " " and code[-1] == " ":
                code = code[1:-1]
            out.append(r"\cscode{" + latex_escape(code) + "}")
            i += run + close.end()
        elif emphasis_end(text, i, 2) > 0:
            end = emphasis_end(text, i, 2)
            out.append(r"\textbf{" + inline_to_latex(text[i + 2:end]) + "}")
            i = end + 2
        elif emphasis_end(text, i, 1) > 0:
            end = emphasis_end(text, i, 1)
            out.append(r"\textit{" + inline_to_latex(text[i + 1:end]) + "}")
            i = end + 1
        else:
            out.append(latex_escape(c))
            i += 1
    return "".join(out)


@dataclasses.dataclass
class Table:
    title: str            # LaTeX
    rows: list            # of (key, description), LaTeX
    line: int = 0
    ident: int = 0


@dataclasses.dataclass
class Note:
    text: str             # LaTeX
    ident: int = 0


@dataclasses.dataclass
class Document:
    title: str
    intro: list           # of paragraphs, LaTeX
    flows: list           # of lists of Table and Note. A flow starts a page.


def split_row(line):
    """Return the cells of a table line, split at the pipes that are not
    escaped."""
    inner = line.strip()
    if inner.startswith("|"):
        inner = inner[1:]
    if inner.endswith("|") and not inner.endswith("\\|"):
        inner = inner[:-1]
    return [cell.strip() for cell in re.split(r"(?<!\\)\|", inner)]


def parse_markdown(text, name="cheatsheet.md"):
    """Return the Document that the Markdown text describes."""
    lines = text.splitlines()

    def fail(number, message):
        raise ConverterError(f"{name}:{number}: {message}")

    title = None
    intro = []
    flows = [[]]
    pending = None            # the title of the table that is expected
    in_groups = False
    i = 0
    while i < len(lines):
        number = i + 1
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith("<!--"):
            if NEWPAGE.match(line):
                if pending:
                    fail(number, "a ### heading must be followed by its table")
                if flows[-1]:
                    flows.append([])
                i += 1
                continue
            while i < len(lines) and "-->" not in lines[i]:
                i += 1
            i += 1
            continue
        heading = HEADING.match(line)
        if heading:
            level, words = len(heading.group(1)), heading.group(2)
            if pending:
                fail(number, "a ### heading must be followed by its table")
            if level == 1:
                if title is not None:
                    fail(number, "only one # heading is allowed")
                title = inline_to_latex(words)
            elif title is None:
                fail(number, "the # heading must come first")
            elif level == 2:
                in_groups = True
            elif level == 3:
                pending = (inline_to_latex(words), number)
            else:
                fail(number, f"a heading of level {level} is not supported")
            i += 1
            continue
        if line.startswith("|"):
            if pending is None:
                fail(number, "a table needs a ### heading before it")
            header = split_row(line)
            if len(header) != 2:
                fail(number, "a table has exactly two columns")
            if i + 1 >= len(lines) or not all(
                    SEPARATOR_CELL.match(c) for c in split_row(lines[i + 1])):
                fail(number + 1, "the row of dashes under the table header is missing")
            i += 2
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = split_row(lines[i])
                if len(cells) != 2:
                    fail(i + 1, "a table has exactly two columns")
                rows.append((inline_to_latex(cells[0]), inline_to_latex(cells[1])))
                i += 1
            if not rows:
                fail(number, "a table needs at least one row")
            flows[-1].append(Table(pending[0], rows, pending[1]))
            pending = None
            continue
        if UNSUPPORTED.match(line):
            fail(number, "lists, quotes, and code blocks are not supported")
        if title is None:
            fail(number, "the # heading must come first")
        if pending:
            fail(number, "a ### heading must be followed by its table")
        paragraph = [line]
        i += 1
        while (i < len(lines) and lines[i].strip() and not lines[i].strip().startswith(("|", "#", "<!--"))
               and not UNSUPPORTED.match(lines[i].strip())):
            paragraph.append(lines[i].strip())
            i += 1
        converted = inline_to_latex(" ".join(paragraph))
        if in_groups:
            flows[-1].append(Note(converted))
        else:
            intro.append(converted)
    if pending:
        fail(pending[1], "a ### heading must be followed by its table")
    if title is None:
        fail(1, "the # heading is missing")
    flows = [flow for flow in flows if flow]
    if not any(isinstance(item, Table) for flow in flows for item in flow):
        fail(1, "the cheat sheet has no tables")
    document = Document(title, intro, flows)
    number_items(document)
    return document


def number_items(document):
    """Give each table and each note a number, over all the flows."""
    tables = notes = 0
    for flow in document.flows:
        for item in flow:
            if isinstance(item, Table):
                item.ident = tables
                tables += 1
            else:
                item.ident = notes
                notes += 1


##############################################################################
# Layout. Pure functions of the measured heights, in points.
##############################################################################

@dataclasses.dataclass
class Piece:
    """A part of a table, or a note, in a column."""
    kind: str             # "table" or "note"
    ident: int
    first: int = 0        # the rows [first, last) of a table
    last: int = 0
    continued: bool = False
    height: float = 0.0


def item_height(item):
    """Return the height of the whole item: ("note", height) or
    ("table", head, rows)."""
    if item[0] == "note":
        return item[1]
    return item[1] + sum(item[2])


def fill(items, caps, hmax, gap=TABLE_GAP, min_rows=MIN_ROWS, max_columns=MAX_COLUMNS):
    """Place the items in columns, and return the columns, each a list of
    Pieces, or None when more than max_columns are needed.

    caps gives the height of each column in turn, and its last value goes
    on for the columns after it. An item goes in whole, or moves to the next
    column when it does not fit. An item taller than hmax, the full height of
    a column, is split into parts that each fit a column.
    """
    columns = [[]]
    used = 0.0

    def cap():
        index = len(columns) - 1
        return caps[index] if index < len(caps) else caps[-1]

    def next_column():
        nonlocal used
        columns.append([])
        used = 0.0
        return len(columns) <= max_columns

    for ident, item in enumerate(items):
        total = item_height(item)
        if total <= hmax + EPSILON:
            while True:
                need = total + (gap if columns[-1] else 0.0)
                if used + need <= cap() + EPSILON:
                    break
                if not next_column():
                    return None
            kind = item[0]
            rows = len(item[2]) if kind == "table" else 0
            columns[-1].append(Piece(kind, ident, 0, rows, False, total))
            used += need
            continue
        head, rows = item[1], item[2]
        first = 0
        part = 0
        while first < len(rows):
            gap_here = gap if columns[-1] else 0.0
            space = cap() - used - gap_here
            fits, height = 0, head
            while first + fits < len(rows) and height + rows[first + fits] <= space + EPSILON:
                height += rows[first + fits]
                fits += 1
            remaining = len(rows) - first
            if fits >= min(min_rows, remaining) and fits > 0:
                if remaining - fits == 1 and fits > min_rows:
                    fits -= 1
                    height -= rows[first + fits]
                columns[-1].append(Piece("table", ident, first, first + fits, part > 0, height))
                used += gap_here + height
                first += fits
                part += 1
                if first < len(rows) and not next_column():
                    return None
            elif not columns[-1]:
                fits = 1
                height = head + rows[first]
                columns[-1].append(Piece("table", ident, first, first + 1, part > 0, height))
                used += height
                first += 1
                part += 1
                if first < len(rows) and not next_column():
                    return None
            elif not next_column():
                return None
    return columns


def layout_flow(items, first_cap, full_cap, balance=True):
    """Return the pages of one flow: a list of pages, each a list of three
    columns, each a list of Pieces. The first page has columns of first_cap,
    the others of full_cap. With balance, the last page gets columns of
    about equal height."""
    caps = [first_cap] * COLUMNS + [full_cap]
    columns = fill(items, caps, full_cap)
    if columns is None:
        raise ConverterError("the cheat sheet needs too many columns")
    pages = math.ceil(len(columns) / COLUMNS)
    if balance:
        before = [first_cap if p == 0 else full_cap for p in range(pages - 1)]
        base = [c for cap in before for c in [cap] * COLUMNS]
        top = first_cap if pages == 1 else full_cap
        low, high = 0.0, top
        best = columns
        while high - low > 0.5:
            middle = (low + high) / 2
            trial = fill(items, base + [middle] * COLUMNS, full_cap, max_columns=COLUMNS * pages)
            if trial is not None and len(trial) <= COLUMNS * pages:
                best, high = trial, middle
            else:
                low = middle
        columns = best
    columns = columns + [[] for _ in range(-len(columns) % COLUMNS)]
    return [columns[p * COLUMNS:(p + 1) * COLUMNS] for p in range(len(columns) // COLUMNS)]


##############################################################################
# LaTeX
##############################################################################

def key_spec():
    return (r">{\raggedright\arraybackslash}p{\cskey}"
            r">{\raggedright\arraybackslash}p{\csdesc}")


def preamble():
    row_a, row_b = ROW_COLORS
    return rf"""\documentclass[10pt]{{article}}
\usepackage[landscape,{PAPER},margin={MARGIN}]{{geometry}}
\usepackage{{fontspec}}
\setmainfont{{{MAIN_FONT}}}
\setmonofont{{{MONO_FONT}}}[Scale={MONO_SCALE}]
\usepackage[table]{{xcolor}}
\usepackage{{array}}
\definecolor{{csheadbg}}{{HTML}}{{{HEADER_BACKGROUND}}}
\definecolor{{csheadfg}}{{HTML}}{{{HEADER_TEXT}}}
\definecolor{{csrowa}}{{HTML}}{{{row_a}}}
\definecolor{{csrowb}}{{HTML}}{{{row_b}}}
\pagestyle{{empty}}
\setlength{{\parindent}}{{0pt}}
\setlength{{\parskip}}{{0pt}}
\setlength{{\topskip}}{{0pt}}
\setlength{{\boxmaxdepth}}{{\maxdimen}}
\setlength{{\columnsep}}{{{COLUMN_SEP}}}
\setlength{{\tabcolsep}}{{{TAB_COL_SEP}}}
\setlength{{\arrayrulewidth}}{{{RULE_WIDTH}}}
\arrayrulecolor[HTML]{{{RULE_COLOR}}}
\renewcommand{{\arraystretch}}{{{ARRAY_STRETCH}}}
\hfuzz=0.5pt
\newlength{{\csw}}
\newlength{{\cskey}}
\newlength{{\csdesc}}
\newlength{{\csgap}}
\newsavebox{{\csbox}}
\newcommand{{\cscode}}[1]{{\texttt{{#1}}}}
\newcommand{{\cssize}}{{\fontsize{{{FONT_SIZE}}}{{{LEADING}}}\selectfont}}
\AtBeginDocument{{%
  \setlength{{\csw}}{{\dimexpr(\textwidth-{COLUMNS - 1}\columnsep)/{COLUMNS}\relax}}%
  \setlength{{\cskey}}{{\dimexpr{KEY_FRACTION}\dimexpr\csw-4\tabcolsep\relax\relax}}%
  \setlength{{\csdesc}}{{\dimexpr{1 - KEY_FRACTION:.4f}\dimexpr\csw-4\tabcolsep\relax\relax}}%
  \setlength{{\csgap}}{{{TABLE_GAP}pt}}%
  \cssize}}
\newcommand{{\cshead}}[1]{{\hline\rowcolor{{csheadbg}}\multicolumn{{2}}{{l}}{{\color{{csheadfg}}\bfseries\strut #1}}\\\hline}}
\newcommand{{\csrows}}[2]{{\begin{{tabular}}{{{key_spec()}}}#1#2\end{{tabular}}}}
\newcommand{{\cstable}}[2]{{\sbox{{\csbox}}{{\csrows{{\cshead{{#1}}}}{{#2}}}}\nointerlineskip\leavevmode\usebox{{\csbox}}\par}}
\newcommand{{\csnote}}[1]{{\sbox{{\csbox}}{{\parbox{{\csw}}{{\raggedright\cssize #1}}}}\nointerlineskip\leavevmode\usebox{{\csbox}}\par}}
\newcommand{{\csmeasure}}[1]{{\typeout{{CSM #1 \the\dimexpr\ht\csbox+\dp\csbox\relax}}}}
"""


def row_tex(key, description, index):
    color = "csrowa" if index % 2 == 0 else "csrowb"
    return rf"\rowcolor{{{color}}}{key} & {description}\\\hline"


def title_block(document):
    intro = "".join(rf"\par\vspace{{2pt}}{p}" for p in document.intro)
    return (rf"\parbox{{\textwidth}}{{\raggedright{{\fontsize{{{TITLE_SIZE}}}{{{TITLE_SIZE + 3}}}"
            rf"\selectfont\bfseries {document.title}}}{intro}}}")


def measure_source(document):
    """Return the LaTeX of the first pass, which writes the height of the
    title, of each table header, row, and note, and the size of a column."""
    out = [preamble(), r"\begin{document}"]
    out.append(rf"\sbox{{\csbox}}{{{title_block(document)}}}\csmeasure{{T}}")
    out.append(r"\typeout{CSM G \the\textheight\space\the\csw}")
    for flow in document.flows:
        for item in flow:
            if isinstance(item, Note):
                out.append(rf"\csnote{{{item.text}}}\csmeasure{{N {item.ident}}}")
                continue
            out.append(rf"\sbox{{\csbox}}{{\csrows{{\cshead{{{item.title}}}}}{{}}}}\csmeasure{{H {item.ident}}}")
            for r, (key, description) in enumerate(item.rows):
                body = rf"{key} & {description}\\\hline"
                out.append(rf"\sbox{{\csbox}}{{\csrows{{}}{{{body}}}}}\csmeasure{{R {item.ident} {r}}}")
    out.append(r"\end{document}")
    return "\n".join(out) + "\n"


def parse_measures(log):
    """Return the measures that the first pass wrote in its log."""
    measures = {}
    for match in re.finditer(r"^CSM (\w) ?([\d ]*?) ?(-?[\d.]+)pt(?: (-?[\d.]+)pt)?\s*$", log, re.M):
        kind, numbers, value, second = match.groups()
        key = (kind, *map(int, numbers.split()))
        measures[key] = (float(value), float(second) if second else None)
    return measures


def final_source(document, pages_by_flow, title_height):
    """Return the LaTeX of the second pass: each page as three columns."""
    tables = {t.ident: t for flow in document.flows for t in flow if isinstance(t, Table)}
    notes = {n.ident: n for flow in document.flows for n in flow if isinstance(n, Note)}
    out = [preamble(), r"\begin{document}"]
    first_page = True
    for flow_index, pages in enumerate(pages_by_flow):
        for page in pages:
            if not first_page:
                out.append(r"\newpage")
            if first_page:
                out.append(rf"\noindent{title_block(document)}\par\vspace{{{TITLE_GAP}pt}}")
                height = r"\dimexpr\textheight-" + f"{title_height + TITLE_GAP}pt" + r"\relax"
            else:
                height = r"\textheight"
            first_page = False
            out.append(r"\nointerlineskip\noindent\hbox to\textwidth{%")
            for c, column in enumerate(page):
                out.append(rf"\begin{{minipage}}[t][{height}][t]{{\csw}}\vspace{{0pt}}")
                for p, piece in enumerate(column):
                    if p:
                        out.append(r"\vskip\csgap")
                    if piece.kind == "note":
                        out.append(rf"\csnote{{{notes[piece.ident].text}}}")
                        continue
                    table = tables[piece.ident]
                    title = table.title + (" " + latex_escape(CONTINUED) if piece.continued else "")
                    rows = "\n".join(row_tex(*table.rows[r], r) for r in range(piece.first, piece.last))
                    out.append(rf"\cstable{{{title}}}{{{rows}}}")
                out.append(r"\end{minipage}%" + ("\n" + r"\hfill%" if c < len(page) - 1 else ""))
            out.append("}")
    out.append(r"\end{document}")
    return "\n".join(out) + "\n"


##############################################################################
# The build
##############################################################################

def source_epoch(source):
    """Return the time to write in the PDF: SOURCE_DATE_EPOCH, or the time of
    the last commit of the source, or FALLBACK_EPOCH."""
    if os.environ.get("SOURCE_DATE_EPOCH", "").isdigit():
        return int(os.environ["SOURCE_DATE_EPOCH"])
    try:
        path = Path(source).resolve()
        out = subprocess.run(["git", "log", "-1", "--format=%ct", "--", str(path)],
                             capture_output=True, text=True, check=True,
                             cwd=path.parent).stdout.strip()
        if out.isdigit():
            return int(out)
    except (OSError, subprocess.CalledProcessError):
        pass
    return FALLBACK_EPOCH


def run_engine(tex_path, epoch):
    """Run the LaTeX engine on tex_path. Return its log, or raise."""
    env = dict(os.environ, SOURCE_DATE_EPOCH=str(epoch), FORCE_SOURCE_DATE="1")
    try:
        result = subprocess.run([LATEX_ENGINE, "-interaction=nonstopmode", "-halt-on-error", tex_path.name],
                                cwd=tex_path.parent, env=env, capture_output=True, text=True)
    except OSError as error:
        raise ConverterError(f"{LATEX_ENGINE} could not run: {error}") from error
    log_path = tex_path.with_suffix(".log")
    log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else result.stdout
    if result.returncode != 0:
        errors = [line for line in log.splitlines() if line.startswith("!")][:3]
        raise ConverterError(f"{LATEX_ENGINE} failed: " + "; ".join(errors or ["see the log"]))
    return log


def check_final_log(log):
    """Raise when the second pass lost text or overflowed a column."""
    for pattern, what in ((r"Missing character: There is no [^\n]*", "a character is missing in the font"),
                          (r"Overfull \\vbox[^\n]*", "a column is too full"),
                          (r"Overfull \\hbox \((?:[1-9]|0\.[6-9])[^\n]*", "a cell is too wide")):
        found = re.search(pattern, log)
        if found:
            raise ConverterError(f"{what}: {found.group(0)}")


def fixed_id(pdf):
    """Return the bytes of a PDF with its trailer ID, which the engine takes
    from the random folder of the build, set to a hash of the rest, so that
    the same source gives the same file. The ID keeps its length, so the
    offsets in the file stay right."""
    pattern = re.compile(rb"/ID\s*\[\s*<([0-9A-Fa-f]{32})>\s*<([0-9A-Fa-f]{32})>\s*\]")
    found = pattern.search(pdf)
    if found is None:
        return pdf
    blank = pdf[:found.start(1)] + b"0" * 32 + pdf[found.end(1):found.start(2)] + b"0" * 32 + pdf[found.end(2):]
    digest = hashlib.md5(blank).hexdigest().encode()
    return pdf[:found.start(1)] + digest + pdf[found.end(1):found.start(2)] + digest + pdf[found.end(2):]


def build(source, output, balance=True):
    """Build the PDF at output from the Markdown at source. Return the
    number of pages."""
    source, output = Path(source), Path(output)
    document = parse_markdown(source.read_text(encoding="utf-8"), str(source))
    epoch = source_epoch(source)
    with tempfile.TemporaryDirectory() as folder:
        work = Path(folder)
        measure = work / "measure.tex"
        measure.write_text(measure_source(document), encoding="utf-8")
        measures = parse_measures(run_engine(measure, epoch))
        if ("G",) not in measures:
            raise ConverterError("the first pass did not measure the page")
        column_height = measures[("G",)][0]
        title_height = measures[("T",)][0]
        pages_by_flow = []
        for index, flow in enumerate(document.flows):
            items = []
            for item in flow:
                if isinstance(item, Note):
                    items.append(("note", measures[("N", item.ident)][0]))
                else:
                    rows = [measures[("R", item.ident, r)][0] for r in range(len(item.rows))]
                    items.append(("table", measures[("H", item.ident)][0], rows))
            first = column_height - (title_height + TITLE_GAP if index == 0 else 0)
            pages_by_flow.append(layout_flow_items(flow, items, first, column_height, balance))
        final = work / output.stem
        final = final.with_suffix(".tex")
        final.write_text(final_source(document, pages_by_flow, title_height), encoding="utf-8")
        log = run_engine(final, epoch)
        check_final_log(log)
        wanted = sum(len(pages) for pages in pages_by_flow)
        written = re.search(r"\((\d+) pages?", log)
        if written is None or int(written.group(1)) != wanted:
            raise ConverterError(f"the PDF has {written.group(1) if written else 'no'} pages, not the {wanted} that were placed")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(fixed_id(final.with_suffix(".pdf").read_bytes()))
    return wanted


def layout_flow_items(flow, items, first_cap, full_cap, balance):
    """Lay out one flow, whose measured items are items, and return its pages
    with each Piece's ident the number of the table or note in the document."""
    pages = layout_flow(items, first_cap - EPSILON, full_cap - EPSILON, balance)
    idents = [(item.ident if isinstance(item, (Table, Note)) else None) for item in flow]
    return [[[dataclasses.replace(piece, ident=idents[piece.ident]) for piece in column]
             for column in page] for page in pages]


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build the cheat sheet PDF from its Markdown source.")
    parser.add_argument("--source", default=DEFAULT_SOURCE, help="the Markdown file")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="the PDF to write")
    parser.add_argument("--check", action="store_true", help="only check the Markdown, and write nothing")
    parser.add_argument("--print-output", action="store_true", help="print the name of the PDF and stop")
    parser.add_argument("--no-balance", action="store_true", help="fill the columns of the last page from the left")
    args = parser.parse_args(argv)
    if args.print_output:
        print(args.output)
        return 0
    try:
        if args.check:
            parse_markdown(Path(args.source).read_text(encoding="utf-8"), args.source)
            print(f"{args.source} is valid.")
            return 0
        pages = build(args.source, args.output, balance=not args.no_balance)
    except (ConverterError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"{args.output}: {pages} page{'s' if pages != 1 else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
