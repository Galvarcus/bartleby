# Contributing to Bartleby

Bartleby is a writing environment for Vim, written in Vim9script. This page
covers how to report a fault and how to offer a change.

## Reporting a fault or asking for a feature

Open an issue from one of the forms. A workflow reads the answers by their
headings and adds the matching labels, so keep the layout the form produces.

- A fault report needs a **Minimal vimrc** that loads Bartleby and Logger.
  Without one, a workflow adds `needs-repro` and asks for it.
- Give the **Component** answer exactly as the form lists it.
- Put no API key in an issue. A workflow adds `needs-redaction`.

## Requirements

| Purpose | Needs |
| --- | --- |
| Running the plugin | Vim 9.2 or newer, with `+popupwin` |
| Running the test suite | Vim 9.2.1172 or newer[^patch] |
| Either | [Logger](https://github.com/Galvarcus/Logger) on the runtimepath |
| The compile tests | Pandoc 3.x, `pdflatex`, `xelatex`, and the `sffms` and `ulem` packages |
| The cheat sheet tests | `xelatex`, with the fonts TeX Gyre Heros and DejaVu Sans Mono[^fonts] |

## Branches

Base your work on `Development`. Changes reach `main` from there.

## Commit messages

A commit message states the problem the commit fixes, in the format that Vim
uses:

```text
subject states the problem

Problem:  Full sentence restating the subject.
Solution: Short description of the fix, ending with your name in
          parentheses.

Prose for a longer account of the problem and the fix. No bullet points.

fixes:   #NNNN
related: #NNNN
closes:  #NNNN

Assisted-by: Name of the AI tool
Signed-off-by: Your Name <you@example.com>
```

- **The subject states the problem, not the fix.** `fix the path check` is
  wrong. `two spellings of one path compare unequal on macOS` is right. Keep
  it to 72 characters, in lower case, with no trailing period.
- **The `Problem:` line repeats the subject as a full sentence**, with a
  period. Name a reporter in parentheses after it when someone else found the
  fault.
- **The `Solution:` line ends with your name in parentheses**, then a period.
- Wrap the prose at 78 columns. Write no bullet points in it.
- **`fixes:` names the issue the commit fixes**, and **`related:` names an
  issue that bears on it**, including one that caused it. Align the values and
  end them without a period. Both may appear more than once.
- **`closes:` names the pull request the commit closes.** Write it only in a
  commit that comes with one, and keep `fixes:` for an issue.
- **`Assisted-by:` is required when an AI tool wrote any of the change.** Name
  the tool. `Co-authored-by:` names a person instead.
- Keep each commit to one change.

## Signing off

Every commit needs a `Signed-off-by:` trailer. Add it with the `-s` flag:

```bash
git commit -s
```

The trailer certifies the [Developer Certificate of
Origin](https://developercertificate.org): you wrote the change, or you have
the right to offer it under the licence of this project. Git adds the trailer
from your `user.name` and `user.email`, so set both before you commit.[^hook]

## Code

- Every file opens with `vim9script`, then a guard on `v:version` and `&cp`,
  then a header block naming the plugin, what the file does, and the licence.
- PascalCase names a class, a function, a method, and a command. camelCase
  names a local variable and a parameter. snake_case names a script variable
  and a global one. ALLCAPS names a constant and an import alias.
- Define a value once and import it. A shared value goes in
  `import/bartleby/variables/constants.vim`, and one that a single script uses
  goes in a script level `const`.
- A comment states why the code is as it is, never what it does. Put no
  comment at the end of a line of code, and keep a comment line to 78 columns.
- `plugin/bartleby.vim` holds settings, commands, mappings, and autocommands
  only. The code lives in `autoload/bartleby/`, loaded on first use. A test
  checks this.

## Verification

Run these from the root of the repository, with Logger on the runtimepath as
`deps/Logger` or by its own path.

| Check | Command | Passes when |
| --- | --- | --- |
| Unit tests | `vim -es -u NONE -N -c 'set rtp+=.,deps/Logger' -c 'source tests/harness.vim' -c 'quit'` | `tests/results.txt` reads `All tests passed` |
| Compile smoke tests | the same, with `source tests/test_compile_smoke.vim` | `tests/smoke_results.txt` reads `All smoke tests passed` |
| Cheat sheet | `python3 tools/cheatsheet/build_cheatsheet.py --check` | it reports the file valid |
| Cheat sheet tests | `python3 -m unittest discover -s tools/cheatsheet -p 'test_*.py'` | all tests pass |
| Workflows | `actionlint .github/workflows/*.yml` | no findings |
| GhostCode | `vim --cmd 'set rtp+=.,deps/Logger,<GhostCode>' -c 'let g:ghostcode_exports_are_api = 0' -c 'runtime plugin/ghostcode.vim' -c 'GhostCode .' -c 'copen'` | no finding is marked `[ghost]` |

[GhostCode](https://github.com/Galvarcus/GhostCode) finds dead code, and CI
runs it on every change to the plugin. It needs its own checkout, which
`<GhostCode>` stands for above. The setting matters: the exports of Bartleby
serve its own files, so without it an export that nothing uses goes
unreported.

Two things make a local run differ from the job, and both are in the
quickfix list rather than in your code. `:GhostCode` takes one path and
reads every file under it, so a `deps/Logger` inside the repository is read
as well: give Logger by its own path for this check, or read only the
findings in Bartleby's own files. And a file that git ignores is in your
checkout and not in CI's.

## Tests

A new test goes in `tests/test_<area>.vim` and is registered in
`tests/harness.vim`. Each test file exports one `RunAll` function that calls
its own test functions.

Prove that a test guards the change: break the change on purpose, confirm that
a named test fails, then put it back.

## Pull requests

Fill in every section of the pull request template. Paste the checklists from
[doc/SW_Development_Checklist.md](doc/SW_Development_Checklist.md) that apply,
Part 1 for every change and the checklist of each component you touched. Mark
each row, and explain every Failed, Requires Attention, or N/A row in a line
under its table.

## Licence

Bartleby is under the GNU General Public License 3.0. Your contribution goes
under the same licence.

[^fonts]: XeTeX finds a font by name through fontconfig, not through the
file name database of TeX, so a `tex-gyre` installed as TeX files alone
stays invisible and the build stops with `The font "TeX Gyre Heros" cannot
be found`. Run `fc-list | grep Heros` to see whether the font is
resolvable. `build_cheatsheet.py` names both fonts at the top.

[^patch]: The harness refuses to run below that patch and says so. Use the
latest [vim-appimage](https://github.com/vim/vim-appimage), or
[vim-win32-installer](https://github.com/vim/vim-win32-installer) on Windows,
as `.github/actions/install-vim` does.

[^hook]: To add the trailer to every commit without the flag, write a
`prepare-commit-msg` hook that calls `git interpret-trailers`. Git has no
configuration variable for it.
