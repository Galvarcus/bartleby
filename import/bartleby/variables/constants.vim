vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# import/bartleby/variables/constants.vim: every constant that more than
# one script uses, each defined once. Import it with a plain import, which
# Vim finds in the import folder of runtimepath:
#   import 'bartleby/variables/constants.vim' as CO
# This file imports nothing, so it can never be part of an import cycle.
# A constant that only one script uses stays in that script.
# License: GNU GPL 3.0
##############################################################################

##############################################################################
# SECTION: Identity. Display names derive from PLUGIN_NAME. Values stored
# on disk, SCRIVE_EXT and SCRIVE_FOLDER, have their own literals: they
# identify existing user data, so they must not change with the name.
##############################################################################

export const PLUGIN_NAME: string = 'Bartleby'
export const MENU_NAME: string = tolower(PLUGIN_NAME)
export const PROFILE_TITLE: string = $' {PLUGIN_NAME} Profile '
export const SCRIVE_EXT: string = '.bartleby'
export const SCRIVE_FOLDER: string = 'Bartleby'
export const PROJECT_FILE: string = 'project.json'

##############################################################################
# SECTION: Pane buffers. windows.vim protects these panes from being
# replaced, and each pane's own script creates its buffer by this name.
##############################################################################

export const BINDER_BUF: string = $'{PLUGIN_NAME}-Binder'
export const INSPECTOR_BUF: string = $'{PLUGIN_NAME}-Inspector'
export const COMPILE_SELECT_BUF: string = $'{PLUGIN_NAME}-Compile-Select'

##############################################################################
# SECTION: Binder items and scrive types.
##############################################################################

export const KIND_FOLDER: string = 'folder'
export const KIND_DOCUMENT: string = 'document'

# What a folder is in the structure, independent of its title. ROLE_PART
# and ROLE_CHAPTER exist only under ROLE_MANUSCRIPT, and ROLE_CUSTOM only
# at the top level. ROLE_NONE is a plain folder. See binderitem.vim.
export const ROLE_NONE: string = ''
export const ROLE_FRONT_MATTER: string = 'front-matter'
export const ROLE_MANUSCRIPT: string = 'manuscript'
export const ROLE_PART: string = 'part'
export const ROLE_CHAPTER: string = 'chapter'
export const ROLE_CHARACTERS: string = 'characters'
export const ROLE_RESEARCH: string = 'research'
export const ROLE_BACK_MATTER: string = 'back-matter'
export const ROLE_CUSTOM: string = 'custom'

export const TYPE_NOVEL: string = 'novel'
export const TYPE_NOVEL_PARTS: string = 'novel_parts'
export const TYPE_SHORT_STORY: string = 'short_story'
export const TYPE_SCREENPLAY: string = 'screenplay'

##############################################################################
# SECTION: Document metadata. The display strings are also the stored
# values. syntax/bartleby-binder.vim builds its label rule from LABELS.
##############################################################################

export const LABELS: list<string> = ['None', 'Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Purple']
export const STATUSES: list<string> = ['To Do', 'First Draft', 'Revised', 'Done']

##############################################################################
# SECTION: Dictionary and thesaurus. Each reference names its provider,
# see lexicon.vim, and a language file chooses its default references.
##############################################################################

export const KIND_DICTIONARY: string = 'dictionary'
export const KIND_THESAURUS: string = 'thesaurus'
export const REFERENCES: dict<dict<string>> = {
  collegiate: {
    provider: 'merriam-webster',
    apiName: 'collegiate',
    kind: KIND_DICTIONARY,
    title: 'Merriam-Webster Dictionary',
  },
  thesaurus: {
    provider: 'merriam-webster',
    apiName: 'thesaurus',
    kind: KIND_THESAURUS,
    title: 'Merriam-Webster Thesaurus',
  },
}

##############################################################################
# SECTION: Part of speech and Fountain. syntax/fountain.vim builds its
# character cue and scene heading rules from the two patterns.
##############################################################################

# Mode name to its list key in the lists of tools/lang/<code>.json.
export const MODE_LISTS: dict<string> = {
  Pronouns: 'pronouns',
  Determiners: 'determiners',
  Prepositions: 'prepositions',
  Conjunctions: 'conjunctions',
  Auxiliaries: 'auxiliaries',
  Fillers: 'fillers',
  Adverbs: 'adverbs',
  Contractions: 's_contraction_words',
}

export const FOUNTAIN_CHARACTER_PATTERN: string = '^\L*$'
# A scene heading starts with a standard prefix, or with a period that
# forces a heading. syntax/fountain.vim uses the two parts in two rules.
export const FOUNTAIN_SCENE_PREFIX_PATTERN: string = '^\c\(int\|ext\|est\|i\/e\)\([.\/]\| \)'
export const FOUNTAIN_FORCED_SCENE_PATTERN: string = '^\.\a'
export const FOUNTAIN_SCENE_HEADING_PATTERN: string =
  $'{FOUNTAIN_SCENE_PREFIX_PATTERN}\|{FOUNTAIN_FORCED_SCENE_PATTERN}'
