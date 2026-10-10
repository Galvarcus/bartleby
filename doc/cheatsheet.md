<!--
  The source of cheatsheet.pdf at the top level of the repository, which
  the cheatsheet job of .github/workflows/ci.yml makes from this file. See
  tools/cheatsheet/build_cheatsheet.py for the rules.

  Each ### heading and the table under it is one table of the card. The
  heading is its black header row. The first row of the table, Key and
  Action, is for readers of this file and is left out of the card.
  A table has two columns. The ## headings are not printed. The comment
  between two groups below starts a new page of the card.

  Keep this file in step with README.md when a command or a key changes.
-->

# Bartleby Quick Reference Card

Commands, mappings, and keys of Bartleby, a writing environment for Vim.
`<leader>` is your mapleader, and `<CR>` is Enter.

## User commands

### General

| Command | Action |
| --- | --- |
| `:BartlebyCommands` | Open the command palette |
| `:BartlebyMenu` | Open the command menu |
| `:BartlebyProfile` | Edit your author profile |
| `:BartlebyProjectInfo` | Edit the profile for this scrive only |

### Scrive

| Command | Action |
| --- | --- |
| `:BartlebyOpen [name]` | Open a scrive by name. Without a name, open the last one |
| `:BartlebyNewScrive {name}` | Create a scrive. Asks for its type |
| `:BartlebyList` | List all scrives and open one |
| `:BartlebyClose[!]` | Close the scrive and all that is open of Bartleby. With `!`, throw away unsaved changes |

### Binder and views

| Command | Action |
| --- | --- |
| `:BartlebyToggleBinder` | Show or hide the Binder |
| `:BartlebyToggleInspector` | Show or hide the Inspector |
| `:BartlebyScrivenings[!]` | Open a Scrivening of the folder of the document. With `!`, save and close it |
| `:BartlebySearch` | Search the scrive into the quickfix list |

### Writing tools

| Command | Action |
| --- | --- |
| `:BartlebyFocus[!] [dim]` | Toggle Focus. `!` turns it off |
| `:BartlebySpotlight[!] [mode]` | Toggle Spotlight. `!` turns it off |
| `:BartlebyQuill [mode]` | Set the wrap mode: detect, off, hard, soft, or toggle |

### Goals

| Command | Action |
| --- | --- |
| `:BartlebyGoals` | Set the session goal, the daily goal, and the tracker |
| `:BartlebyProgress` | Show the writing progress and the words of each day |

### Snapshots

| Command | Action |
| --- | --- |
| `:BartlebySnapshot` | Take a snapshot of the current document |
| `:BartlebySnapshots` | View or restore snapshots |

### Files and compile

| Command | Action |
| --- | --- |
| `:BartlebyCompile` | Compile the scrive |
| `:BartlebyTidyFiles` | Move the files so that the folders follow the Binder |
| `:BartlebyRecover [name]` | Add documents that the Binder does not list. With a name, rebuild a Binder that does not open |
| `:BartlebyEmptyTrash` | Delete everything in the Trash for good |

### Lookup

| Command | Action |
| --- | --- |
| `:BartlebyDefine [word]` | Define the word under the cursor, or word |
| `:BartlebyThesaurus [word]` | Show synonyms for the word under the cursor, or word |
| `:BartlebyLexiconClearCache` | Delete the lookup cache |

<!-- newpage -->

## Leader commands

### Views and tools

| Mapping | Action |
| --- | --- |
| `<leader>bi` | Toggle the Inspector |
| `<leader>bz` | Toggle Focus |
| `<leader>bl` | Toggle Spotlight |
| `<leader>bL` | Pick a Spotlight mode |
| `<leader>bp` | Toggle Quill |

### Palette and menu

| Mapping | Action |
| --- | --- |
| `<leader>b<Space>` | Open the command palette |
| `<leader>bm` | Open the command menu |

### Lookup

| Mapping | Action |
| --- | --- |
| `<leader>bd` | Define the word under the cursor or the Visual selection |
| `<leader>bt` | Thesaurus for the word under the cursor or the Visual selection |

`<leader>bd` and `<leader>bt` exist only when their API key is set.

## Quick commands

### Binder: open and add

| Key | Action |
| --- | --- |
| `<CR>` | Open the document, or expand or collapse the folder |
| `<Tab>` | Expand or collapse the folder |
| `a` | Add a document |
| `A` | Add a folder: Chapter or Part where the type allows |
| `r` | Rename the item |

### Binder: move and remove

| Key | Action |
| --- | --- |
| `dd` | Move the item to the Trash. In the Trash, delete for good |
| `u` | Restore the item from the Trash |
| `J` / `K` | Move the item down or up, also into the next or previous chapter |
| `m` | Move the item to a folder picked from a list |
| `>>` / `<<` | Indent or outdent the item |

### Binder: details

| Key | Action |
| --- | --- |
| `l` | Set the label of the document |
| `s` | Set the status of the document |
| `L` | Show or hide the Chapter and Part prefixes |
| `S` | Take a snapshot of the document |
| `gS` | View or restore snapshots |

### Binder: views

| Key | Action |
| --- | --- |
| `gc` | Open the Corkboard for the folder |
| `go` | Open the Outliner for the folder |
| `v` | Open a Scrivening of the folder |
| `/` | Search the scrive |
| `?` | Show the key list |
| `q` | Close the Binder |

### Corkboard

| Key | Action |
| --- | --- |
| Arrows or `h` `j` `k` `l` | Move between cards |
| `<CR>` or `<Space>` | Open the selected document |
| `e` | Edit the synopsis |
| `J` / `K` | Move the card later or earlier |
| `?` | Show the key list |
| `<Esc>` | Close the Corkboard |

### Outliner

| Key | Action |
| --- | --- |
| `j` / `k` | Move the selection |
| `<CR>` | Open the document |
| `l` | Set the label |
| `s` | Set the status |
| `gs` | Sort by a column. The tree stays as it is |
| `?` | Show the key list |
| `q` | Close the Outliner |

### Inspector

| Key | Action |
| --- | --- |
| `e` on Label or Status | Pick a value |
| `e` on Target or Keywords | Type a value |
| `e` on Synopsis | Edit the synopsis. `<CR>` adds a line, `<C-s>` saves |
| `e` on a goal | Edit the writing goals |

### Scrive list

| Key | Action |
| --- | --- |
| `j` / `k` | Move the selection |
| `<CR>` | Open the scrive |
| `?` | Show the key list |
| `q` | Close the list |

### Compile selection

| Key | Action |
| --- | --- |
| `x` | Include or exclude the document, or all under a folder |
| `<CR>` | Accept the selection and continue |
| `?` | Show the key list |
| `q` | Cancel |

### Dictionary and thesaurus

| Key | Action |
| --- | --- |
| `j` / `k` | Move the selection |
| `<CR>` in the thesaurus | Replace the word in the text |
| `<CR>` on a suggestion | Look up the suggestion |
| `a` | Show antonyms or synonyms |
| `d` | Show the definition of the selected word |
| `?` | Show the key list |
| `q` | Close |

### Writing progress

| Key | Action |
| --- | --- |
| `j` / `k` | Scroll |
| `e` | Edit the goals |
| `q` or `<Esc>` | Close |

### Forms

| Key | Action |
| --- | --- |
| `<Tab>` / `<S-Tab>` | Next or previous field or button |
| `<CR>` | Next field. On a button, press it |
| `<C-s>` | Submit the form |
| `<Esc>` or `<C-c>` | Cancel |
| `<Left>` / `<Right>` | Choose an option, or move between buttons |
| `<C-a>` / `<C-e>` | Go to the start or end of the text |
| `<C-u>` | Clear the field |

### Lists and palette

| Key | Action |
| --- | --- |
| Type | Filter the list |
| `<Down>` / `<Up>` | Move the selection |
| `<C-j>` / `<C-k>` | Move the selection |
| `<PageDown>` / `<PageUp>` | Move a page |
| `<CR>` | Pick the selection |
| `<Esc>` | Cancel |

### Menu

| Key | Action |
| --- | --- |
| `h` / `l` | Move between menus in the bar |
| `j` / `k` | Move down or up in a menu |
| `<CR>`, `<Space>`, or `l` | Open the menu or the item |
| `h` | Go back |
| `q` or `<Esc>` | Close |

### Confirmation

| Key | Action |
| --- | --- |
| `y` | Yes |
| `n`, `x`, or `<Esc>` | No |
| `<CR>` | The default answer, which is No for every deletion |

Generated from doc/cheatsheet.md. Bartleby is free software under the GNU
General Public License 3.0. https://github.com/Galvarcus/bartleby
