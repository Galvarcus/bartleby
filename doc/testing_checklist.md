# Bartleby Testing Checklist

For engineers and developers writing or reviewing tests, or debugging
a failure. Every item here traces back to a real bug found during
this plugin's development - this isn't generic advice, it's a record
of what has actually gone wrong and how it was caught (or missed).

See [`testing_feasibility_report.md`](testing_feasibility_report.md)
for the reasoning behind the overall approach; this document is the
checklist you actually run through while doing the work.

## Before writing any test

- [ ] Know which tier the code under test falls into - pure logic,
      buffer/window state, or popup. The tier determines the technique
      (see below); guessing wrong wastes time on a test that can't
      actually pass reliably.
- [ ] Check whether a `fixtures/*.json` file already covers the
      project shape you need before building one through the UI layer
      inside the test itself - that couples the test to code paths
      (`Sc.Create()`, `AddDocument()`) that aren't what you're actually
      testing.
- [ ] If the code path touches `filetype`/`syntax` at all, confirm
      `$VIMRUNTIME` is set in whatever environment the test runs in.
      A from-source or minimal Vim build silently no-ops `filetype
      on`/`syntax on` without it - this looks exactly like a real
      regression (a filetype-dependent branch silently taking the
      wrong path) and has cost real debugging time before.

## Tier 1: pure logic

- [ ] No `popup_create()`, no buffer, no real file I/O in the function
      under test - if there is, it's not actually Tier 1.
- [ ] Test the actual return value / list of lines, not a rendered
      side effect. `compile.vim`'s `Walk*`/`Join*` functions return
      `list<string>` directly - assert against that list, don't render
      it and scrape the buffer.
- [ ] For anything involving the 5 structural folders (Front Matter/
      Manuscript/Back Matter/Characters/Research), test both "is this
      folder itself restricted" and "does a restriction on it actually
      block the operation" - `RoleAllowedUnder()` existing is not the
      same as it covering the case you think it covers. (This exact
      gap - the function existed and looked reasonable, but simply
      never checked these 5 roles at all - went unnoticed until
      directly asked "does indent/outdent actually block on these.")
- [ ] For any function combining several sibling blocks with a
      separator, test the boundary case explicitly: what's the
      separator behavior when the block on either side of the join
      point starts with something other than a `#` heading (a raw
      LaTeX block, an empty block, etc.)? `StartsWithHeading()`-based
      separator suppression only works when that assumption holds -
      it silently doesn't for anything else, and this exact case
      produced a stray `* * *` in real Book output that only user
      testing caught.
- [ ] `does it source` is not a test. Vim9 compiles `def` bodies
      lazily, on first real call - a broken default-parameter value or
      function body inside an untested branch will source cleanly and
      still be broken. Every new function needs at least one actual
      call in a test, not just inclusion in a file that loads without
      error.

## Tier 2: buffer/window state

- [ ] Drive interaction with `feedkeys('...', 'xt')` (the `x` flag
      executes immediately; `t` uses real typeahead so buffer-local
      mappings actually fire) rather than calling the underlying
      function directly, when the thing under test is the mapping/key
      wiring itself, not just the logic behind it.
- [ ] For anything that maps `line('.')` to a data-model index
      (`CursorContext()`-style functions), test with a header/title
      line present if the buffer has one - an off-by-one here is easy
      to introduce when a header line is added later and every
      cursor-to-row calculation needs updating together. (This exact
      change - adding Binder's title line - required threading a
      `HEADER_LINES` offset through two call sites; a test asserting
      the mapping was correct before the header line existed wouldn't
      have caught a regression when the header was added, unless
      re-run after.)
- [ ] Test window-management fixes in the **freshest, most minimal**
      scenario first, not as an afterthought after a more elaborate
      setup. A fix that depends on "which window is current" can pass
      a test that happens to already have the target window focused
      from earlier setup, and fail the real, common case where nothing
      is open yet. (`GoToEditorWindow()` missing before an `execute
      'edit'` call passed an early manual test purely because a
      document was already open beforehand - the actual bug only
      showed up testing the plain, expected first-use case.)
- [ ] Test syntax highlighting with `synID()`/`synIDattr()` **per
      column**, never by visual inspection alone. Visual terminal
      color-checking (including via `tmux capture-pane`) is not
      precise enough to catch a match region that's off by a few
      columns or overlapping incorrectly with another rule - both of
      the real syntax bugs found in this plugin (see below) looked
      fine visually and were only caught by checking the actual syntax
      group name at each byte column.
- [ ] Any file-deleting/clearing operation: assert the file(s) on disk
      are untouched afterward, not just that the binder tree/UI
      updated. Bartleby's convention is that no user-facing "delete"
      or "clear" operation ever touches files on disk, only the
      binder's own tracking of them - a test that only checks the tree
      updated wouldn't catch a regression that started actually
      deleting files.

## Tier 3: popups

- [ ] Call the popup's `filter` function directly with a key string
      (`popup.Filter(popup.winid, 'j')`) to test its decision logic,
      rather than trying to simulate real keypresses into a rendered
      popup - this is both more reliable and covers what actually
      matters (the logic), without needing the popup to render at all.
- [ ] For any multi-key sequence (like Outliner's `gs`), test the
      *sequence*, not just each key alone - a popup filter receives
      one key at a time with no built-in multi-key buffering, so `g`
      then `s` needs its own explicit state test distinct from a bare
      `s` alone. (An early draft of this exact sequence would have
      silently triggered the wrong action, since `s` alone was already
      mapped to something else - only testing the actual two-key
      sequence, not just each key individually, would catch this.)
- [ ] If the popup was created with `mapping: false`, confirm that's
      actually still in `popup_create()`'s options after any refactor
      - without it, Vim pre-expands keys through whatever buffer
      happens to be underneath first, which only manifests when a
      colliding buffer-local mapping happens to exist underneath (so
      it can silently regress without an isolated test noticing).
- [ ] Don't write a test asserting a popup's exact visual layout
      (wrapping, `prop_add()` highlight pixel/column position) unless
      it's one of the small number of cases flagged in the feasibility
      report as worth a `screendump.vim` test (popup stacking being
      the clearest example). Chasing full visual coverage here has a
      poor cost/benefit ratio and the feasibility report explicitly
      recommends against it.

## Vim9 language gotchas worth a standing test or a code-review check

These are real bugs found in this codebase, specifically because they
don't look like bugs on casual reading:

- [ ] **Forward-referencing a class in a function's own signature**
      (a parameter or return type) is resolved eagerly and throws
      `E1010` if the class is defined later in the file - this is
      different from referencing a class only inside a function body
      (a local variable's type, or `.new()`), which works fine either
      order. Don't "fix" a signature-order issue by just reordering
      unless you've confirmed which case you're in.
- [ ] **Script-local function names must start with a capital letter**
      - `E1267` if not. This isn't just the project's PascalCase
      convention; it's an actual Vim9 language requirement.
- [ ] **`max()`/`min()` take a single list argument**, not multiple
      positional arguments - `max(a, b)` is invalid; use `max([a, b])`.
- [ ] **A bare dict literal `{...}` as the sole or tail expression of
      an arrow lambda is ambiguous with a block body** (`E475`/`E488`)
      - true even with real content inside it, not just when empty.
      Wrap it: `=> ({...})`.
- [ ] **`() => {}` as a default parameter value hits the same
      ambiguity** - use a named no-op function instead.
- [ ] **A multi-byte character inside a `[...]` character class**
      doesn't reliably advance Vim's regex match position to the next
      real character - silently breaks any pattern requiring a literal
      space or other text immediately after the class. Use
      non-capturing alternation (`\%(a\|b\|c\)`) instead of a character
      class whenever any alternative is multi-byte.
- [ ] **Two `syntax match` rules that both anchor on the same starting
      text conflict**, even when a `\zs` in the second rule limits
      what actually gets highlighted - the first rule's claim on that
      span blocks the second from matching there at all. Use a
      lookbehind (`\(...\)\@<=`) instead of a shared prefix + `\zs`
      when two rules need to build on the same anchor.

## Pre-merge checklist

- [ ] New/changed pure-logic function has a Tier 1 test calling it
      with more than one input, including at least one edge case
      (empty list, the 5 structural roles specifically if relevant,
      a boundary between two sibling blocks).
- [ ] New/changed cursor-line-to-data-index mapping re-verified with
      any header/title lines the buffer actually has.
- [ ] New/changed syntax rule checked with `synID()` per column, not
      just visually.
- [ ] New/changed popup filter has a direct-call test for every branch
      of its key handling, including multi-key sequences.
- [ ] Any new document-opening code path calls `GoToEditorWindow()`
      (or the equivalent for the context) before `execute 'edit'` -
      don't assume the current window is the right one.
- [ ] Any new destructive Binder operation (delete/clear) shows a
      `confirm()` prompt and leaves files on disk untouched.
- [ ] `tests/harness.vim` run locally and passing before pushing,
      not just relying on CI to catch it.

## CI checklist

- [ ] Fast suite (Tier 1 + Tier 2 + popup filter-direct tests) runs on
      every push and pull request, no external tool dependencies.
- [ ] Compile smoke test is a separate, explicitly gated job (needs
      Pandoc + a LaTeX install) so a missing external tool fails
      clearly as "smoke test skipped/failed to find pandoc," not
      mixed in with the fast suite's own pass/fail signal.
- [ ] A CI failure's actual error output is captured, not just its
      exit code - for the compile smoke test especially, the real
      LaTeX log (not any Vim-level assertion) is what pinned down both
      real compile bugs found so far (a missing font, a missing
      `\tightlist` macro definition).
