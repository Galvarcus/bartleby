# Bartleby

Bartleby is a writing environment for Vim, written in Vim9script. Work in this repository follows the rules below.

## Repositories

All repositories are under `/Users/joe/Development`.

| Repository | Path | Notes |
| --- | --- | --- |
| Bartleby | `bartleby` | `github.com/Galvarcus/bartleby`, branch `Development` |
| Bartleby wiki | `bartleby.wiki` | Clone of the GitHub wiki |
| GhostCode | `GhostCode` | Dead-code analyzer for Vim9script. Bartleby CI runs it |
| Logger | `Logger` | Message logging plugin that Bartleby and GhostCode use |
| Skills | `claude-skills` | Source of the skills in `skills/`. `.claude/skills` and `dist/` are generated |

`bartleby/.claude/skills` is a symlink to `claude-skills/.claude/skills`. After a change in `claude-skills/skills/`, run:

```bash
python3 tools/install.py <skill> --target project --force
python3 tools/package.py <skill>
```

## Skills

Use these skills. Read each one before work that falls under it.

- **vim9script-plugin** - Vim9script standards: naming, script structure, named values, the plugin file, and logging.
- **code-comments** - The comment rules for every language and file type.
- **github-markdown-style** - Editing rules for Markdown documentation.
- **token-efficient-execution** - Lean execution for every task with more than one step.

## Preferences

- Respond tersely, in Simplified Technical English.
- For a new feature, write a design plan for approval first. Implement after approval. Do separate features as separate jobs.
- Never hard-code a value. Define it once and import it: shared values go in `import/bartleby/variables/constants.vim`, script values in a script-level `const`.
- Keep names short but clear, with intuitive abbreviations such as `str`, `amt`, and `cmd`. Test names are exempt.
- Link a GitHub issue from a comment only when the issue explains why the code is as it is. Put it on its own line below the comment as `# REFERENCE: <full issue URL>`.
- In project text, do not name proprietary applications unless asked. FOSS applications are fine.
- Verify a change before reporting it as done, and say plainly what was not verified.

## Issues

`.github/workflows/issue-triage.yml` runs `.github/scripts/triage.js` on each new or edited issue. An issue must pass it.

- Write the body in the layout of its form in `.github/ISSUE_TEMPLATE/`: each field as `### <label>`, a blank line, then the answer, in form order. Write `_No response_` for an empty optional field. `triage.js` finds the answers by these headings.
- A bug needs a **Minimal vimrc** that loads Bartleby and Logger. Without one, the workflow adds `needs-repro` and posts a comment. Use the placeholder of the form:

  ```vim
  set nocompatible
  set rtp+=/path/to/bartleby,/path/to/Logger
  filetype plugin on
  syntax on
  ```

- Give the **Component** answer exactly as the form lists it. The workflow adds the matching label. A **Where do you run Vim?** answer of gVim, MacVim, or Other GUI Vim adds `gui`.
- Put no API key in an issue. The workflow adds `needs-redaction`.
- After you create or edit an issue, wait for its triage run and check its labels and comments.
- When the forms or `triage.js` change, update this section in the same change.

## Architecture

- `plugin/bartleby.vim` holds settings, commands, mappings, and autocommands only, and loads no autoload script at startup. A test checks this. Default keys come from the `MAPPINGS` table, each with a `<Plug>` name, and `g:bartleby_no_mappings` turns them off.
- `autoload/bartleby.vim` and `autoload/bartleby/*.vim` hold the code, loaded on first use.
- A script copies each setting into a script-level variable when it loads. Only a setting that the user may change while Vim runs, such as `g:bartleby_table_autoformat`, is read when used.
- Messages live in `autoload/bartleby/locale/*.vim`, one file per area, with the aliases `MB` (binder), `MC` (common), `MK` (compile), `MW` (writing), `MI` (ui), `MP` (panes), `MV` (views), `MG` (progress), and `MD` (data).
- `IN.T` and `IN.N` take only literal text, so that `tools/i18n/extract.py` can collect it. Text from template files goes through `IN.TFile`. The extractor collects that text from `templates/` itself.
- Binder folders carry roles such as `characters`, `research`, and `manuscript`. Code finds folders by role, not by title.
- Popups come from `InputPopup` in `inputpopup.vim`. A text field whose value is something that Vim can complete, such as a file or folder path, names its completion type in the `complete` option, as the import prompt and the compile cover image do, so that `Tab` completes it as on the command line. Every new field of that kind does the same.
- Compile runs Pandoc with the templates in `tools/latex/`, `tools/css/book.css`, and the Lua filter `tools/pandoc/tables.lua`. Before a PDF, `texcheck.vim` checks for the engine and every class and package that the template names. A `% NEEDS:` line in a template lists what its class loads.

## Verification

Run from the root of the Bartleby repository. Logger must be in `deps/Logger`.

| Check | Command | Passes when |
| --- | --- | --- |
| Unit tests | `vim -es -u NONE -N -c 'set rtp+=.,deps/Logger' -c 'source tests/harness.vim' -c 'quit'` | `tests/results.txt` reads `All tests passed` |
| Compile smoke tests | the same, with `source tests/test_compile_smoke.vim` | `tests/smoke_results.txt` reads `All smoke tests passed` |
| Cheat sheet | `python3 tools/cheatsheet/build_cheatsheet.py --check` | it reports the file valid |
| Cheat sheet tests | `python3 -m unittest discover -s tools/cheatsheet -p 'test_*.py'` | all tests pass |
| Workflows | `actionlint .github/workflows/*.yml` | no findings, with `shellcheck` installed |
| GhostCode | as the `ghostcode` job in `.github/workflows/ci.yml` runs it | no findings |

- The compile smoke tests need Pandoc, `pdflatex`, `xelatex`, and the `sffms` and `ulem` packages. CI runs them with the distro Pandoc and with Pandoc 3.10, in the image `ghcr.io/galvarcus/bartleby-ci` that the repository variable `CI_IMAGE` names. `.github/docker/Dockerfile` defines it, and `.github/workflows/ci-image.yml` builds it.
- A new test goes in `tests/test_<area>.vim` and is registered in `tests/harness.vim`.
- To prove a test guards a change, break the change on purpose and confirm that a named test fails. Earlier sessions did this for every feature.
- Never run `python3 tools/i18n/extract.py`. The pre-commit hook runs it after a change to a translated text and stages `lang/bartleby.pot`. CI checks the template with `--check`.
