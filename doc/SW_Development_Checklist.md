# Software Development Checklist

Checklists for developers who work on Bartleby. Use them to check a change before it is merged.

Each row has a **quick instruction** for developers who know Bartleby, and under it an expandable **full instructions** section for developers who are new to Bartleby or to Vim9 script.

## How to use

1. Copy the checklists that apply to your change into the description of your pull request or issue. Copy a whole checklist: its heading, its sentence, and its table. Part 1 applies to nearly every change. Part 2 has one checklist for each group of components, and you copy those that you touched.
2. Work down each table. Mark exactly one box in each row by replacing `☐` with `☑` in that column.
3. Under the table, write one line for each row that is Failed, Requires Attention, or N/A. Name the row and give the reason.
4. Merge only when no row is Failed or Requires Attention.

| Column | Mark it when |
| --- | --- |
| Completed | You did the instruction and the result is as it says. |
| Failed | You did the instruction and the result is not as it says. Fix it, or explain why not. |
| Requires Attention | You need an answer or a decision from someone else before you can finish. |
| N/A | The instruction does not apply to this change. Give the reason. |

The first word of each instruction tells you what kind of work it is.

| Type | Meaning |
| --- | --- |
| **Setup** | Prepare your machine or your branch. |
| **Code** | Write or change code in the way that the project requires. |
| **Test** | Write, register, or run tests. |
| **Check** | Look at the result by hand, or check a rule with a command. |
| **Translate** | Add or update a translation. |
| **Docs** | Write or update documentation. |
| **Commit** | Record the change in git. |
| **Review** | Ask for review, or answer it. |

GitHub shows the boxes in a table as plain symbols and does not let you click them. Replace the symbol by editing the text. Copy the checked box from here: `☑`.


## Contents


**Part 1: Every change**

- [1. Set up](#1-set-up)
- [2. Code standards](#2-code-standards)
- [3. Tests](#3-tests)
- [4. Messages and translation](#4-messages-and-translation)
- [5. Documentation](#5-documentation)
- [6. Commit, pull request, and CI](#6-commit-pull-request-and-ci)

**Part 2: By component**

- [7. Binder and the scrive tree](#7-binder-and-the-scrive-tree)
- [8. Panes and windows](#8-panes-and-windows)
- [9. Corkboard, Outliner, and lists](#9-corkboard-outliner-and-lists)
- [10. Writing tools](#10-writing-tools)
- [11. Goals and progress](#11-goals-and-progress)
- [12. Data on disk](#12-data-on-disk)
- [13. Compile and language tools](#13-compile-and-language-tools)
- [14. Popups, commands, palette, and menu](#14-popups-commands-palette-and-menu)

## Part 1: Every change

### 1. Set up

Do these once on each machine, before your first change.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Setup:** Install Vim 9.2.1172 or later, from the latest vim-appimage release.<br><details><summary>Expand for full instructions</summary>The test harness refuses an older Vim, because an older Vim crashes on code that the tests use. A Vim from a Linux package is usually too old.<ol><li>Open `https://github.com/vim/vim-appimage/releases/latest` and download the file named `Vim-v...-x86_64.AppImage`.</li><li>Make it executable with `chmod +x` and unpack it with `./Vim-v*.AppImage --appimage-extract`. This needs no FUSE.</li><li>Link `squashfs-root/AppRun` as `vim` in a folder on your `PATH`. Do not call the unpacked binary directly, so that Vim finds its own runtime.</li><li>Run `vim --version` and check that `Included patches` ends at 1172 or higher.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Setup:** Clone Bartleby, and clone Logger into its `deps/Logger` folder.<br><details><summary>Expand for full instructions</summary>Bartleby imports `Logger/logger.vim` from the Logger plugin, which is not part of this repository. The test commands and CI expect it in `deps/Logger`.<ol><li>Clone Bartleby, then change into the clone.</li><li>Run `git clone https://github.com/Galvarcus/Logger.git deps/Logger`.</li><li>Check that `deps/Logger/import/Logger/logger.vim` exists.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Setup:** Install only the tools that your change needs.<br><details><summary>Expand for full instructions</summary>Each tool below belongs to one kind of change. A test that needs a tool you did not install is skipped, or fails when its tool is required.<ol><li>Translations: `gettext` for `msgfmt`, and a German locale for `tests/test_i18n.vim`.</li><li>Compile: `pandoc`, `texlive-latex-extra`, `texlive-fonts-recommended`, and `texlive-plain-generic`.</li><li>Cheat sheet: `texlive-xetex`, `texlive-latex-recommended`, `fonts-texgyre`, `fonts-dejavu-mono`, `poppler-utils`, and `fontconfig`.</li><li>Tagger: Python 3 with `spacy` and the model `en_core_web_sm`, installed in a virtual environment.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Run the full suite before you change anything, and confirm that it passes.<br><details><summary>Expand for full instructions</summary>A failure that is already there is not yours, and you need to know that before you start.<ol><li>From the root of the repository, run `vim -es -u NONE -N -c 'set rtp+=.,deps/Logger' -c 'source tests/harness.vim' -c 'quit'`.</li><li>Run `cat tests/results.txt`. It must read `All tests passed`.</li><li>If the file does not exist, run the command again with `-V20/tmp/vim.log` after `-N`, and read the log. The `-es` mode hides every message, so the file and the log are the only output.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Setup:** Branch from Development, and open your pull request into Development.<br><details><summary>Expand for full instructions</summary>Create the branch with `git switch -c <name> Development`. CI commits generated files to `main` and `Development`, so pull before you push there.</details> | ☐ | ☐ | ☐ | ☐ |

### 2. Code standards

Check these for every `.vim` file that you add or change. They are the project's Vim9 script standards.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Code:** Start the script with the required header and the version guard `v:version < 902`.<br><details><summary>Expand for full instructions</summary>Autoload, plugin, and import scripts start with the header below. Copy it from any file in `autoload/bartleby/`. Syntax and ftdetect files run once per buffer, so they do not use the `s:is_loaded` guard.<ol><li>Line 1: `vim9script`, then a blank line.</li><li>Then `if exists('s:is_loaded') \|\| v:version < 902 \|\| &cp`, `finish`, and `endif`.</li><li>Then a blank line and `var is_loaded: bool = true`.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Order the sections as the standard says, and put a class first when another function's signature names it.<br><details><summary>Expand for full instructions</summary>The order is: header, top comment block, imports, script variables, constants, global variables, functions with the exported ones first, then classes with the exported ones first. A class that appears in the parameters, the return type, or a field of something defined earlier must itself come first, because Vim resolves that type when it reads the `def` line. Say why in a short comment above the class. An interface cannot name the class that implements it, so type those parameters `any`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Name by the case table: PascalCase, camelCase, snake_case, and ALLCAPS.<br><details><summary>Expand for full instructions</summary>Use PascalCase for classes, functions, methods, and user commands. Use camelCase for variables and parameters inside a function or class. Use snake_case for global, script, buffer, window, and tab variables. Use ALLCAPS for constants and import aliases. Never use kebab-case, and never separate a number from letters: `special_var1`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Import with the first-letter alias, check that it is free, and keep it the same everywhere.<br><details><summary>Expand for full instructions</summary>Autoload from `autoload/`, with `import autoload 'bartleby/foo.vim' as F`. Use a plain `import` only for the shared constants file.<ol><li>Take the first letter of the script as the alias. When it is taken, add the first letter of the next word, or the next free letter.</li><li>A test module uses `T` and the first letter of each word after `test_`: `test_binder.vim` is `TB`.</li><li>Look for taken aliases with `grep -rn " as TB$" tests` and `grep -rhn "^import" autoload plugin \| grep " as F$"`.</li><li>Use the same alias for a script in every file, and never one alias for two scripts.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Define a value that more than one script uses once, in the shared constants file.<br><details><summary>Expand for full instructions</summary>The file is `import/bartleby/variables/constants.vim`. Export the constant, and import it with `import 'bartleby/variables/constants.vim' as CO`. Never write the plugin name into a script: derive display names from `PLUGIN_NAME`. A value stored on disk, such as a file extension, keeps its own literal, so that renaming the plugin never breaks a user's data. The constants file imports nothing.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Read a global setting with a one-line `get()` in `plugin/bartleby.vim`, and copy it into a script variable.<br><details><summary>Expand for full instructions</summary>In the plugin: `g:bartleby_name = get(g:, 'bartleby_name', default)`. In the script that uses it, after the imports: `var name = g:bartleby_name`. Add the setting to the Configuration table in `README.md`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Comment the reason, above the code, in 78 columns or fewer, without parentheses, quotes, or dashes.<br><details><summary>Expand for full instructions</summary>Comment only what the code cannot say. A block that documents a definition starts with `# FUNCTION:`, `# METHOD:`, `# CLASS:`, or `# SECTION:`. Its delimiter lines hold only `#`. A comment inside a function has no identifier and goes on the line directly above the code. Never put a comment at the end of a line of code.<ol><li>Find lines over the width: `awk 'length>78 && /^[ \t]*#/ {print FILENAME": "FNR}' file.vim`.</li><li>Find forbidden characters: `grep -nE '^\s*#' file.vim \| grep -E '\(\|\)\|;\| - \|"'`.</li><li>A hit inside a code example is allowed.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Link an issue only when it explains why the code is odd: `# REFERENCE: <full URL>`, on its own line below the comment.<br><details><summary>Expand for full instructions</summary>Use it for an obscure change, a workaround, or code that breaks normal practice. Do not link every issue. Example: the version guard in `tests/harness.vim`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Write strings in the standard order, and prefer `$'{expression}'` to `..`.<br><details><summary>Expand for full instructions</summary>Regexes use single quotes. A string that needs an escape such as a newline uses double quotes. Any other string without a single quote uses single quotes. A string with a single quote and no double quote uses double quotes. Text that the user sees follows the checklist on messages instead.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Log only where the script shows a message, through its logger.<br><details><summary>Expand for full instructions</summary>Do not add logging for its own sake. Do not add a setting that copies a Logger option.<ol><li>Import the logger: `import autoload 'bartleby/log.vim' as L`.</li><li>Create it after the imports: `var log = L.New(expand('<sfile>:t'))`.</li><li>Use `log.Info`, `log.Warn`, or `log.Error` with a text from `IN.T`.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Format with two spaces, no tabs, no trailing whitespace, no backslash continuations, and long option names.<br><details><summary>Expand for full instructions</summary>Break a long line at a meaning boundary. Write `tabstop`, not `ts`. Use Unix line endings.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Keep each script to one task, prefer classes, and move code used twice into an exported function.<br><details><summary>Expand for full instructions</summary>Name the one job of the script in its top comment block, and keep the code to that job. When you write the same code in a second place, move it into an exported function or class in the script that owns that job, and import it from both. Prefer a class when the code keeps state across calls, as the popups do. Use a bare function only when a class would add nothing.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Do not use behavior that needs Vim 9.2.1172 in the plugin code. Only the tests may.<br><details><summary>Expand for full instructions</summary>The plugin must run on older Vim 9.2. One known case is a lambda that assigns to a member of a captured function argument, as in `result.ids = ids`. That crashed Vim before patch 9.2.1172. `tests/harness.vim` refuses an older Vim, so the tests may use it. The plugin code may use it only after that patch is in common distributions.</details> | ☐ | ☐ | ☐ | ☐ |

### 3. Tests

Check these for every change that touches behavior.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Test:** Add or update a test for each behavior that you change, in `tests/test_<script>.vim`.<br><details><summary>Expand for full instructions</summary>Fix a bug by writing the test that shows it first, then the fix.<ol><li>Use Vim's own `assert_equal()`, `assert_true()`, and `assert_fails()`. Do not add a test framework.</li><li>Put the tests of `autoload/bartleby/foo.vim` in `tests/test_foo.vim`. Export one `RunAll(): void` that calls each `Test_` function.</li><li>Name each test as a sentence: `Test_a_table_that_does_not_fit_moves_whole()`.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Register a new test file in `tests/harness.vim`: one import and one entry in the `suites` list.<br><details><summary>Expand for full instructions</summary>The harness lists every test file by hand, in order.<ol><li>Choose a free alias, as in the code standards. Check it with `grep -rn " as TX$" tests`.</li><li>Add `import './test_foo.vim' as TF` with the other imports.</li><li>Add `TF.RunAll,` to the `suites` list.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Run the full suite, and confirm that `tests/results.txt` reads `All tests passed`.<br><details><summary>Expand for full instructions</summary>From the root of the repository, run `vim -es -u NONE -N -c 'set rtp+=.,deps/Logger' -c 'source tests/harness.vim' -c 'quit'`. Then run `cat tests/results.txt`. A failure names the test function and the line. The exit code is 1 on a failure.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Prove that each new test can fail: break the behavior on purpose, see the test fail by name, and restore it.<br><details><summary>Expand for full instructions</summary>A test that cannot fail proves nothing. A run that stops without naming a test also counts as a failure, but name the test when you can. Restore with `git checkout -- <file>` when the file has no other changes.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Make each test independent of your machine and of the tests before it.<br><details><summary>Expand for full instructions</summary>Use `tempname()` for files, and the helpers in `tests/fixtures.vim`, such as `BuildProject()`, `WriteDocContent()`, and `CleanupProjectFiles()`. Remove what the test made. Set each option that the test depends on, because an earlier test may have changed it. A window option such as `winfixwidth` stays with a window that `:only` kept. Headless Vim is 80 columns wide. Auto-save writes a modified buffer when you leave it, so set `g:bartleby_autosave = false` in a test of unsaved changes.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Test a popup through its public function with `feedkeys('...', 'xt')`.<br><details><summary>Expand for full instructions</summary>Open the popup, send keys, and check the result. If the popup class is exported, you may call its filter function directly. A popup needs no terminal to run its key code. In a test of a pane, use the `Answer(key)` helper in `tests/test_binder.vim`, so that a missing popup fails the test and does not hang it.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Run the smoke tests and converter tests that your change can affect.<br><details><summary>Expand for full instructions</summary><ol><li>Compile: `vim -es -u NONE -N -c 'set rtp+=.,deps/Logger' -c 'source tests/test_compile_smoke.vim' -c 'quit'`, then `cat tests/smoke_results.txt`. It needs Pandoc and LaTeX.</li><li>Tagger: the same command with `tests/test_tagger_smoke.vim`, then `cat tests/tagger_results.txt`. It needs spaCy.</li><li>Wiki converter: `python3 -m unittest discover -s tools/wiki -p 'test_*.py'`.</li><li>Cheat sheet converter: `CHEATSHEET_REQUIRE_ENGINE=1 python3 -m unittest discover -s tools/cheatsheet -p 'test_*.py'`.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** Try the change by hand in a real Vim, not only in the suite.<br><details><summary>Expand for full instructions</summary>The suite runs without a terminal, so layout, colors, and key handling can differ. Make a small vimrc and start Vim with `vim -u that-file`:<ol><li>Put `set nocompatible`, `set rtp+=/path/to/bartleby,/path/to/bartleby/deps/Logger`, `filetype plugin on`, and `syntax on` in it.</li><li>Open a scrive with `:BartlebyOpen <name>` and use the feature.</li><li>Repeat it with Quill on and off, because Quill remaps keys.</li><li>When the change touches the status line, repeat it with vim-airline installed.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |

### 4. Messages and translation

Check these when a change shows text to the user. The full source is `Localization_README.md`.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Code:** Pass every text the user sees through `IN.T`, or `IN.N` for plurals, as a double-quoted literal in the call.<br><details><summary>Expand for full instructions</summary>Import with `import autoload 'bartleby/i18n.vim' as IN`. The extractor reads the text from the source, so a variable or an interpolated string cannot be translated.<ol><li>`log.Info(IN.T("compiled"))`</li><li>`log.Warn(printf(IN.T("skipping missing file: %s"), path))`</li><li>`echo printf(IN.N("%d document", "%d documents", count), count)`</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Never build a sentence from pieces. Write one whole sentence for each case, and insert values with `printf`.<br><details><summary>Expand for full instructions</summary>A translator needs the whole sentence to reorder the words. Where a value changes the sentence, such as a folder kind, write one sentence for each value.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Keep data in English and translate it only where it is shown, through the existing name functions.<br><details><summary>Expand for full instructions</summary>Stored labels, statuses, scrive types, role prefixes, and Spotlight mode names are data. Show the translated name and store the English value. The functions are `LabelNames` and `StatusNames` in `document.vim`, `TypeNames` in `project.vim`, `RolePrefixes` in `binderitem.vim`, `FieldLabels` in `inspector.vim`, and `ModeNames` in `spotlight.vim`. A picker takes such a map as its `names` argument. A syntax file that matches shown text builds its pattern from the same function.</details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** Run `python3 tools/i18n/extract.py` and commit the updated `lang/bartleby.pot`.<br><details><summary>Expand for full instructions</summary>CI runs `python3 tools/i18n/extract.py --check` and fails when the template is out of date. The extractor stops with an error at a call whose text is not a literal. The repository has no pre-commit hook, so run the command yourself, or confirm that your own hook ran it.</details> | ☐ | ☐ | ☐ | ☐ |
| **Translate:** When English text that has a translation changes, merge the template and compile again.<br><details><summary>Expand for full instructions</summary>Skip this when `lang/` has no `.po` file yet. The commands below use `de`.<ol><li>`python3 tools/i18n/extract.py`</li><li>`msgmerge -U lang/de.po lang/bartleby.pot`</li><li>Translate each new and fuzzy text. Vim ignores a fuzzy text until you check it and remove the mark.</li><li>`sh tools/i18n/compile.sh`</li><li>Commit the `.po` file and the compiled `.mo` file, so that users need no gettext tools.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** Check a translation: keep every `%s` and `%d`, the `[Y]es` key letters, and the spaces at the ends of popup titles.<br><details><summary>Expand for full instructions</summary>Keep the keys `y` and `n` in every language, as in `[Y] Ja`. A label such as `Chapter: ` keeps its colon and space. Run `msgfmt --check -o /dev/null lang/<code>.po`. Then check it in Vim with `:language messages de_DE.UTF-8`. The menu keeps the language that was active when it first opened, so restart Vim to see a changed language there.</details> | ☐ | ☐ | ☐ | ☐ |

### 5. Documentation

Check these when a command, key, setting, or behavior changes.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Docs:** Update `README.md`. It is the source of the Vim help file and of the wiki.<br><details><summary>Expand for full instructions</summary>Change the command table, the key table of the pane, or the Configuration table, whichever your change touches. Do not edit `doc/bartleby.txt` or the wiki by hand, because CI generates both from the README.<ol><li>Keep exactly one H1 in `README.md`, at the top.</li><li>Put content for GitHub only, such as badges and a manual table of contents, between `<!-- vimdoc-ignore-start -->` and `<!-- vimdoc-ignore-end -->`.</li><li>Keep images out of text that the help file needs. The generator removes every image.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Docs:** Update `Users_Guide.md` for anything an author sees.<br><details><summary>Expand for full instructions</summary>It is written for writers, not for developers. Add the feature to the section that fits it, and add a new section to the contents list at the top. Describe what to do, not how the code works.</details> | ☐ | ☐ | ☐ | ☐ |
| **Docs:** Add each new command, `<leader>` mapping, and pane key to `doc/cheatsheet.md`.<br><details><summary>Expand for full instructions</summary>A test fails when a command or a `<leader>b` mapping of the plugin is missing from the sheet. Pane keys are not tested, so add them by hand.<ol><li>A table is a `###` heading with a two-column table under it. The heading becomes the black header row, and the first row of the table is left out of the PDF.</li><li>A line with only `<!-- newpage -->` starts a new page.</li><li>Check the file with `python3 tools/cheatsheet/build_cheatsheet.py --check`.</li><li>Do not commit `cheatsheet.pdf`. CI builds it on `main` and `Development`.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Docs:** Keep the header comment and the function comments of each changed script true.<br><details><summary>Expand for full instructions</summary>A comment that no longer matches the code is worse than none. Reread the top-of-script block and the blocks above the functions that you changed.</details> | ☐ | ☐ | ☐ | ☐ |
| **Docs:** Update `Localization_README.md` when you change a language file, the tagger, the dictionary, or the compile language.<br><details><summary>Expand for full instructions</summary>That file explains how to add a language, what `tools/lang/<code>.json` controls, how the tagger and the dictionary and thesaurus are set up, and the rules for messages. Change the section that matches your change, and keep its examples true. Run each command of a changed example once.</details> | ☐ | ☐ | ☐ | ☐ |

### 6. Commit, pull request, and CI

Check these when your change is ready.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Check:** Read your own `git diff` for debug code, stray files, and secrets.<br><details><summary>Expand for full instructions</summary>Run `git status` and `git diff`. Look for leftover `echo` lines, test output such as `tests/results.txt` and `ghostcode*.log`, files from your editor, and API keys. Remove them or add them to `.gitignore`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Commit:** Make one logical change per commit, with a subject that says what and why.<br><details><summary>Expand for full instructions</summary>Write the subject in the imperative, under 72 characters. Add a body when the reason is not obvious. Do not commit generated files: `doc/bartleby.txt`, `cheatsheet.pdf`, and the wiki come from CI.</details> | ☐ | ☐ | ☐ | ☐ |
| **Review:** Open the pull request into Development, and paste the checklists that apply into its description.<br><details><summary>Expand for full instructions</summary>Always paste the checklists of Part 1 that apply to your change. Add the checklist of each component that you touched. Mark each row as the instructions above this table say.</details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** Wait for CI, and read the `Tests` job. A failure there stops everything after it.<br><details><summary>Expand for full instructions</summary><ol><li>Open the Actions tab and the run of your pull request.</li><li>The jobs `unit`, `compile-smoke`, `tagger-smoke`, `wiki-tool`, and `cheatsheet-tool` feed the gate `Tests`. A job is skipped when its files did not change.</li><li>Read the log of a failed job. The `unit` job prints `tests/results.txt`.</li><li>GhostCode reports code that nothing uses. Remove the code, or explain it in the pull request.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** After the merge, pull the branch, and check the generated commits.<br><details><summary>Expand for full instructions</summary>CI commits `doc/bartleby.txt` after a README change, and `cheatsheet.pdf` after a change to the sheet. The wiki updates on `main` only. Run `git pull` before you continue, so that your next commit sits on top of the generated ones.</details> | ☐ | ☐ | ☐ | ☐ |
| **Review:** Resolve every Failed and Requires Attention row, and state the reason of each N/A row in a line under its table.<br><details><summary>Expand for full instructions</summary>For a Failed row, fix the problem and mark it Completed, or say in a line under the table why you cannot. For a Requires Attention row, name who you need and what you need to know. For an N/A row, give one line of reason, such as the component that you did not touch. A reviewer reads these lines first.</details> | ☐ | ☐ | ☐ | ☐ |

## Part 2: By component

### 7. Binder and the scrive tree

For a change to `binder.vim`, `tree.vim`, `binderitem.vim`, `mutate.vim`, `trash.vim`, `templates.vim`, `project.vim`, or `syntax/bartleby-binder.vim`. The tests are `tests/test_binder.vim`, `test_binder_directory.vim`, `test_tree.vim`, `test_mutate.vim`, `test_trash.vim`, and `test_templates.vim`.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Code:** Keep `binder.vim` to the pane: keys, drawing, and prompts. Put tree logic in `mutate.vim`, `tree.vim`, or `binderitem.vim`.<br><details><summary>Expand for full instructions</summary>Look at where a similar change already lives, and put yours beside it. The pane calls the tree code and then redraws.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Add a pane key in three places: the keymap in `binder.vim`, its line in the key help list there, and the key tables.<br><details><summary>Expand for full instructions</summary><ol><li>Check that the key is free: `grep -n "nnoremap <buffer>" autoload/bartleby/binder.vim`.</li><li>Add the `nnoremap <buffer> <silent> <key> <ScriptCmd>Function()<CR>` line to the keymap block.</li><li>Add `['<key>', IN.T("Description")]` to the help list that `?` shows.</li><li>Add a row to the Binder key table in `README.md`, in `Users_Guide.md`, and in the Binder tables of `doc/cheatsheet.md`.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Refuse a key that changes the tree when the cursor is in the Trash. Use `RefusedInTrash()`, and test with `RowInTrash()`.<br><details><summary>Expand for full instructions</summary>`Flatten()` in `tree.vim` sets `topItem` on each `Row`, so `RowInTrash(row)` in `trash.vim` is one check. Do not walk the tree to find out whether a row is in the Trash. Keys that add, move, rename, or indent must refuse there.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Give the file a place through `Place()` of `layout.vim` when an item is added, moved, or renamed. Never build a path by hand.<br><details><summary>Expand for full instructions</summary>`layout.vim` is the single source of the path of a document, as in `manuscript/part-1/chapter-2/arrival.md`. A new item has an empty `relPath`, and the caller places it. Existing files move only through `:BartlebyTidyFiles`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Keep `syntax/bartleby-binder.vim` in step with the shown text. It builds its patterns from the same name functions as the pane.<br><details><summary>Expand for full instructions</summary>The syntax file colors what the pane draws, such as labels, statuses, and role prefixes. The pane shows translated names, so the syntax file builds its patterns from the same name functions, `LabelNames` and `RolePrefixes`, and not from English text. When you change what the pane draws, change the pattern, then open the Binder in a real Vim and check the colors.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Test a key with `feedkeys('...', 'xt')` on a pane that the test opens, and test each case of the Trash.<br><details><summary>Expand for full instructions</summary>Use `Answer(key)` from `tests/test_binder.vim` for a confirmation popup, so a missing popup fails the test. Test the key in the Trash, in a collapsed folder, and on a structural folder such as the Manuscript.</details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** In a real Vim, add, rename, move, indent, trash, and restore items, and collapse folders. Then run `:BartlebyTidyFiles`.<br><details><summary>Expand for full instructions</summary>Check that the files on disk follow the Binder, that nothing in the Trash moves, and that a collapsed folder opens when an item inside it is restored.</details> | ☐ | ☐ | ☐ | ☐ |

### 8. Panes and windows

For a change to `windows.vim`, `inspector.vim`, `closeall.vim`, or `syntax/bartleby-inspector.vim`. The tests are `tests/test_panes.vim`, `test_inspector.vim`, and `test_closeall.vim`.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Code:** Find a pane or the edit window through `windows.vim`: `IsChromeBuffer()` and `GoToEditorWindow()`. Do not use `:wincmd p`.<br><details><summary>Expand for full instructions</summary>The functions find a window by the name of its buffer. `:wincmd p` goes to the last window, which can be a pane.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** A feature that changes keys, text, or the view of the current window calls `W.RefusedInPane()` first.<br><details><summary>Expand for full instructions</summary>Only the edit window, and the Focus tab, takes part in Focus, Spotlight, and Quill. In a pane they must say so and change nothing.<ol><li>Call `if W.RefusedInPane(IN.T("Feature"))` and `return` at the start of the function that turns the feature on.</li><li>Guard any code that runs in every window, such as a refresh on `CursorMoved`, with `W.IsChromeBuffer(bufnr())`.</li><li>Turning a feature off from a pane is allowed.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Give a new pane a name constant, an entry in `CHROME_BUFFER_NAMES`, `buftype=nofile`, `winfixwidth`, and its own filetype.<br><details><summary>Expand for full instructions</summary>Add the constant, as `INSPECTOR_BUF`, to `import/bartleby/variables/constants.vim`. Add it to `CHROME_BUFFER_NAMES` in `windows.vim`. Then add a test in `tests/test_panes.vim` that Focus, Spotlight, and Quill refuse in the pane.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Draw the Inspector only through `RefreshFor()`, never with `setline()` on its buffer.<br><details><summary>Expand for full instructions</summary>Its buffer is `nomodifiable` and stays when the Inspector is closed. `RefreshFor()` makes it modifiable, clears it, writes it, and locks it again. Writing straight to it fails with E21, or leaves old lines.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Keep the edit window when the last one closes beside a pane. `WatchEditWindow()` makes an empty one and restores the pane widths.<br><details><summary>Expand for full instructions</summary>A change to how windows close must keep that. A window that shows an empty buffer may close, so that `:q` can end a session. Test it in `tests/test_panes.vim`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** When a component holds a window, a buffer, or state, close it in `closeall.vim`, in `All()`.<br><details><summary>Expand for full instructions</summary>`:BartlebyClose` must leave one empty buffer. The order is: remember the session, leave Focus and Spotlight, save, close the windows, wipe the buffers, and forget the scrive. Add a test in `tests/test_closeall.vim`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** In a layout test, reset `winfixwidth` on the edit window, and give each pane the name that Bartleby gives it.<br><details><summary>Expand for full instructions</summary>A window that `:only` kept may be an old pane, and a pane keeps its width, which squeezes the panes of your test. Set the pane widths after both panes exist.</details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** In a real Vim, open the Binder and the Inspector, close the edit window with `:q`, and run `:BartlebyClose`.<br><details><summary>Expand for full instructions</summary><ol><li>After `:q` an empty edit window must stay, and the panes must keep their widths.</li><li>`:q` in that empty window must close it.</li><li>Try Spotlight, Focus, and Quill from each pane. They must refuse.</li><li>`:BartlebyClose` must save your changes and leave one empty buffer.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |

### 9. Corkboard, Outliner, and lists

For a change to `corkboard.vim`, `outliner.vim`, `scrivelist.vim`, `search.vim`, `helppopup.vim`, or `wordcount.vim`. The tests are `tests/test_corkboard.vim`, `test_outliner.vim`, `test_scrivelist.vim`, and `test_wordcount.vim`.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Code:** Handle every key in the popup's filter function, close on `q` or `<Esc>`, and list the keys in the `?` help.<br><details><summary>Expand for full instructions</summary>A popup with a filter takes every key while it is open. A key that the filter does not handle must still be swallowed or passed on on purpose. Add each new key to the help list of the view.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Take word counts from `wordcount.vim` once for each render, and pass the totals down. Never count for each row.<br><details><summary>Expand for full instructions</summary>`Totals()` caches by file size and time. It counts an open buffer, and the documents of an open Scrivening, from memory, so unsaved text counts and the title lines of a Scrivening do not.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Show the translated name of a stored value, and sort and filter by the stored value.<br><details><summary>Expand for full instructions</summary>Use the name functions in the checklist on messages. The Outliner sorts by a column and leaves the tree as it is.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Test a view through its public function with `feedkeys('...', 'xt')`, and test an empty scrive and a long list.<br><details><summary>Expand for full instructions</summary>Open the view with its public function, send keys with `feedkeys('...', 'xt')`, and check the result. Add a case for a scrive with no documents, and one with more rows than the popup shows, to check scrolling.</details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** Open the view on a scrive with a few hundred documents. A render must not read a file again when nothing changed.<br><details><summary>Expand for full instructions</summary>Open the Outliner twice. The second render must be fast, because the counts come from the cache.</details> | ☐ | ☐ | ☐ | ☐ |
| **Docs:** Update the key table of the view in `README.md`, in `Users_Guide.md`, and in `doc/cheatsheet.md`.<br><details><summary>Expand for full instructions</summary>Find the table of the view: the Corkboard, Outliner, or Scrive list table in `README.md` and in `doc/cheatsheet.md`, and the section in `Users_Guide.md`. Add or change the row of each key, and keep the key help list in the code the same.</details> | ☐ | ☐ | ☐ | ☐ |

### 10. Writing tools

For a change to `scrivenings.vim`, `focus.vim`, `spotlight.vim`, `quill.vim`, `wrap.vim`, `tty.vim`, or `autosave.vim`. The tests are `tests/test_scrivenings.vim`, `test_focus.vim`, `test_spotlight_pos.vim`, `test_tty.vim`, and `test_autosave.vim`.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Code:** In a Scrivening, find the document under the cursor with `SV.DocumentHere(project)`, and its text with `SV.SectionTexts()`.<br><details><summary>Expand for full instructions</summary>A Scrivening is one buffer that holds many documents, with a protected title line before each. A feature that finds its document with `FindItemByPath(expand('%:p'))` alone fails there. The Inspector, Quill, the session, snapshots, and auto-save already ask `SV.DocumentHere()`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Never let a change reach a title line. A key that moves or joins lines needs a guard, as `<Up>`, `<Down>`, `<BS>`, and `<Del>` have.<br><details><summary>Expand for full instructions</summary>Quill maps the arrow keys to move by screen lines. In a Scrivening it calls `SV.MapArrows()` instead, so that the arrows still pass a title line. A new mapping of those keys must do the same. Paragraph formatting must not join a title line to text: the buffer declares the title mark as a comment leader.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Save a Scrivening with `SV.SaveIfModified()`, not with `:update`.<br><details><summary>Expand for full instructions</summary>Auto-save runs from an autocommand, and Vim does not fire `BufWriteCmd`, the write of a Scrivening, inside another autocommand. Calling `:update` there fails with E676.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** After a change to the Binder, call `SV.SyncWithTree(project)`. After files change on disk, call it with `true`.<br><details><summary>Expand for full instructions</summary>It saves the open Scrivening, builds it again from the folder, and keeps the cursor in its document at the same line.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Register a new Spotlight mode in `mode_handlers`, give it a name in `ModeNames`, and put its word lists in `tools/lang/en.json`.<br><details><summary>Expand for full instructions</summary>Add a test with a sample sentence in `tests/test_spotlight_pos.vim`. Language rules come from `tools/lang/<code>.json`, never from the script. See the checklist on compile and language tools.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Remove what a mode added when it ends: window options, matches, tab variables, and mappings.<br><details><summary>Expand for full instructions</summary>Focus restores the options it changed when it exits. Spotlight clears the matches of each window. Quill removes its buffer mappings. Test that the window is as before.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Test a key sequence in each Quill mode: off, soft, and hard.<br><details><summary>Expand for full instructions</summary>Quill remaps keys, and its auto mode joins and splits lines while you type.</details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** Check Spotlight in a terminal with 256 colors, and with a colorscheme that sets the Normal highlight.<br><details><summary>Expand for full instructions</summary>Spotlight needs a known background and foreground to compute its dimmed color. Use `TERM=xterm-256color`. In the tests, set `t_Co` and the Normal highlight as `tests/test_spotlight_pos.vim` does.</details> | ☐ | ☐ | ☐ | ☐ |

### 11. Goals and progress

For a change to `progress.vim`, `progressview.vim`, `wordcount.vim`, or `autoload/airline/extensions/bartleby.vim`. The tests are `tests/test_progress.vim` and `test_wordcount.vim`.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Code:** Count words only through `wordcount.vim` and `ManuscriptWords()`: the Manuscript, with unsaved text, without the Trash, notes, or title lines.<br><details><summary>Expand for full instructions</summary>Words written are the net change of the Manuscript, so deleting text lowers them. The display never shows less than 0.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Refresh the counts on pauses, `InsertLeave`, and saves. Never on each key. The status line only reads the stored text.<br><details><summary>Expand for full instructions</summary>`Refresh()` counts and stores the text. `Status()` returns it. A status line calls `Status()` on every redraw, so it must cost nothing.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Write `progress.json` with `WriteJson`, and read it only after `filereadable()`.<br><details><summary>Expand for full instructions</summary>A new scrive and one from before the goals have no such file. `ReadJson` warns about a missing file, which is right for a file that must exist and wrong here.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Compute dates with the calendar functions in `progress.vim`, not with `strptime()`.<br><details><summary>Expand for full instructions</summary>`strptime()` is not on every system. A writing day starts at the hour in `g:bartleby_day_starts_at`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Keep the airline extension a legacy Vim script, and add the progress with `append_to_section()`.<br><details><summary>Expand for full instructions</summary>vim-airline calls its extension functions by lowercase names, which a Vim9 script cannot export. The section comes from `g:bartleby_airline_section`. Add the part only in windows that have text, so that no empty separator shows.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Pass the time to `Refresh(now)`, and check the tracker figures against a known example and a day boundary.<br><details><summary>Expand for full instructions</summary>Do not wait for a day to end. `tests/test_progress.vim` checks a 30-day tracker against the figures of a worked example.</details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** Check the status line in a real Vim, with vim-airline and without it, and in a Binder or Inspector pane.<br><details><summary>Expand for full instructions</summary>Without airline, the progress shows only when the `statusline` option is empty. In a pane it must show nothing.</details> | ☐ | ☐ | ☐ | ☐ |
| **Docs:** Document a new setting in the Configuration table, and keep the Known Issues note on word counts in a Scrivening true.<br><details><summary>Expand for full instructions</summary>Vim's own `g CTRL-G` and vim-airline count the title lines of a Scrivening. Bartleby's counts do not.</details> | ☐ | ☐ | ☐ | ☐ |

### 12. Data on disk

For a change to `persist.vim`, `project.vim`, `session.vim`, `snapshot.vim`, `layout.vim`, `recover.vim`, `restore.vim`, `document.vim`, or `autosave.vim`. The tests are `tests/test_persist.vim`, `test_scrive.vim`, `test_session.vim`, `test_recover.vim`, `test_layout.vim`, `test_restore.vim`, and `test_document.vim`.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Code:** Write JSON only through `PE.WriteJson()`, never with `writefile()` onto a data file.<br><details><summary>Expand for full instructions</summary>It writes a `.tmp` file and renames it, so a crash cannot leave half a file. With the backup flag it keeps the old file as `.bak` first.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Validate on load, change nothing when a file is damaged, and name the file and its backup in the message.<br><details><summary>Expand for full instructions</summary>`Project.Load()` returns false for a truncated, empty, or wrongly structured `project.json`, and `Save()` refuses until a load or a new scrive succeeded. A new stored file needs the same care.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Read an optional file only after `filereadable()`, because `ReadJson()` warns about a missing file.<br><details><summary>Expand for full instructions</summary>`ReadJson()` logs a warning when its file is missing, which is right for a file that must exist. A scrive made before a feature has no file for it, and a new scrive has none until it is used. Call `ReadJson()` only when `filereadable(path)` is true, and use an empty default otherwise.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Keep a format change readable by old files: read every key with `get(data, key, default)`.<br><details><summary>Expand for full instructions</summary>A scrive made by an earlier version must still open. A value stored on disk keeps its own literal and does not follow the plugin name.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Write the session only on change. Reset its cache with `ForgetKnownStates()` in a test.<br><details><summary>Expand for full instructions</summary>The session keeps the last read or written state of each file and skips a write that would change nothing.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Move files only through `layout.vim` `Tidy()`: temporary names, a save after each phase, and never over a file the Binder does not list.<br><details><summary>Expand for full instructions</summary>Leave the Trash alone, stop when a document has unsaved changes, and reopen a moved open document at the same cursor.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Use real files in a `tempname()` folder, and test each damaged case: truncated, empty, and wrongly structured.<br><details><summary>Expand for full instructions</summary>Call `FI.CleanupProjectFiles()` at the end of the test.</details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** Copy a real scrive folder first. Then open one made before your change, and try `:BartlebyRecover`.<br><details><summary>Expand for full instructions</summary>Check that the old scrive loads, that the session restores the document and the Binder, and that nothing in the folder was changed that you did not intend.</details> | ☐ | ☐ | ☐ | ☐ |

### 13. Compile and language tools

For a change to `compile.vim`, `tools/latex`, `tools/css`, `pos.vim`, `tagger.vim`, `tools/pos`, `lang.vim`, `tools/lang`, or the `lexicon` scripts. The tests are `tests/test_compile.vim`, `test_compile_select.vim`, `test_compile_smoke.vim`, `test_pos.vim`, `test_lang.vim`, `test_lexicon.vim`, and `test_tagger_smoke.vim`.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Code:** Run Pandoc and LaTeX as a job with `job_start`, and never wait for it. Skip with a message when a program is missing.<br><details><summary>Expand for full instructions</summary>The compile smoke test polls for the output file because a job is asynchronous. It skips with exit code 0 when a program is not installed.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Take everything that depends on the language of the writing from `tools/lang/<code>.json`, through `lang.vim`. Never put an English rule in a script.<br><details><summary>Expand for full instructions</summary>The file holds the word lists, the adverb and contraction rules, the dialogue pattern, the tagger model, the Pandoc language, and the paper size. See `Localization_README.md` to add a language.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Keep the tagger a separate Python process, and keep `tests/mock_tagger.py` in step with its output.<br><details><summary>Expand for full instructions</summary>The suite uses the mock. The smoke test uses the real tagger.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Keep the dictionary and thesaurus in layers: the lookup in `lexicon.vim`, a provider in `lexicon_mw.vim`, results in `lexicon_result.vim`, and the popup in `lexiconpopup.vim`.<br><details><summary>Expand for full instructions</summary>Take an API key from a setting. Never commit a key. Answers are cached, and `:BartlebyLexiconClearCache` clears them.</details> | ☐ | ☐ | ☐ | ☐ |
| **Test:** Test with the mock tagger and with sample data in the suite, and run the smoke test for the real program.<br><details><summary>Expand for full instructions</summary>CI runs `compile-smoke` with Pandoc and LaTeX, and `tagger-smoke` with spaCy. Run the same command as in the checklist on tests.</details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** Run `:BartlebyCompile` on a sample scrive for each kind of output that you changed, and open the result.<br><details><summary>Expand for full instructions</summary>The compile pane lists only the contents of the Front Matter, Manuscript, and Back Matter, and allows three folders at most.</details> | ☐ | ☐ | ☐ | ☐ |
| **Docs:** Update `Localization_README.md` for a language file field, the tagger, the dictionary, or the compile language.<br><details><summary>Expand for full instructions</summary>Add a new field to the table of fields, in the section on what a language file controls, with its use and its English value. Describe a new tagger or dictionary setting in its own section. Keep the step-by-step list for adding a language in step.</details> | ☐ | ☐ | ☐ | ☐ |

### 14. Popups, commands, palette, and menu

For a change to `inputpopup.vim`, `dialog_popup.vim`, `picker.vim`, `buttonspopup.vim`, `commandpalette.vim`, `menu.vim`, `bartlebymenu.vim`, or `plugin/bartleby.vim`. The tests are `tests/test_inputpopup.vim`, `test_dialog_popup.vim`, and the test of the component that owns the command.

| Instructions | Completed | Failed | Requires Attention | N/A |
| --- | :---: | :---: | :---: | :---: |
| **Code:** Build a form with `InputPopup`, and a one-field prompt with its prompt functions. Do not draw a popup by hand.<br><details><summary>Expand for full instructions</summary>Fields are `text`, `choice`, `filter`, and `multiline`. `PromptText`, `PromptFilter`, and `PromptMultiline` open a single field. Confirmations use `dialog_popup.vim`.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Give every popup a key path that does not need `<C-s>`.<br><details><summary>Expand for full instructions</summary>The Linux console and some terminals take `<C-s>` for flow control, so Vim never sees it. A multiline field has Save and Cancel buttons that Tab reaches. A new form needs a button or `<CR>` route to submit.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Draw the cursor as a highlighted character, with a trailing space where it can sit past the end of a line.<br><details><summary>Expand for full instructions</summary>Only the drawn line gets the space. The text does not.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Add a command in `plugin/bartleby.vim` with `command!`: a PascalCase name that starts with `Bartleby`, `-bar`, and `-bang` when `!` turns a mode off or closes it.<br><details><summary>Expand for full instructions</summary>Use `-nargs` only when the command takes arguments. Keep the command body to one call into an autoload script.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Add the command to the palette in `commandpalette.vim`, in both its command table and its name table, and to the menu in `bartlebymenu.vim`.<br><details><summary>Expand for full instructions</summary>Use `IN.T` for each label. The palette and the menu run the command through its Ex name, so a form with a bang, such as `BartlebyScrivenings!`, is a separate entry.</details> | ☐ | ☐ | ☐ | ☐ |
| **Code:** Define a `<leader>` mapping in `plugin/bartleby.vim` with the prefix `<leader>b`, and check that the key is free.<br><details><summary>Expand for full instructions</summary>Search `plugin/bartleby.vim` for `<leader>b` to list the keys in use.</details> | ☐ | ☐ | ☐ | ☐ |
| **Docs:** Add the command to the command table in `README.md` and `doc/cheatsheet.md`, and a mapping to the leader table of the sheet.<br><details><summary>Expand for full instructions</summary>A test fails when a command or a `<leader>b` mapping is missing from the sheet.</details> | ☐ | ☐ | ☐ | ☐ |
| **Check:** Open the palette with `:BartlebyCommands` and the menu with `:BartlebyMenu`, and run your entry from each.<br><details><summary>Expand for full instructions</summary><ol><li>Open the palette, type part of the name of your entry, and press `<CR>`.</li><li>Open the menu, move with `h`, `j`, `k`, and `l`, and press `<CR>` on your entry.</li><li>Check that the command ran, and that the labels show in the language of Vim when a translation exists.</li></ol></details> | ☐ | ☐ | ☐ | ☐ |

## Maintaining this file

- A table cell cannot contain a line break, so each row is one long line. Edit a row in an editor that wraps lines.
- Inside a cell, write line breaks as `<br>`, lists as `<ol><li>...</li></ol>`, and a pipe as `\|`. Put every identifier, path, and key in backticks, because `<name>` outside backticks is read as an HTML tag.
- Keep the quick instruction short. Put the commands and the reasons in the full instructions.
- When a rule changes in `Localization_README.md`, in `.github/workflows/ci.yml`, or in the project standards, change the rows that state it.
