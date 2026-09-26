vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# document.vim: the metadata of a document: label, status, synopsis,
# keywords, word count target, and custom fields. Kept apart from
# BinderItem so that it loads only when needed: the Binder does not use
# it, the Corkboard, Outliner, and Inspector do. Saved as a JSON file
# next to the document's text file.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/persist.vim' as Pe

# Display strings that are also the stored values. PickOne shows them
# unchanged, see picker.vim, so there is no second list of names to keep
# in step.
export const LABELS: list<string> = ['None', 'Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Purple']
export const STATUSES: list<string> = ['To Do', 'First Draft', 'Revised', 'Done']

export class DocMeta
  var label: string = 'None'
  var status: string = 'To Do'
  var synopsis: string = ''
  var keywords: list<string> = []
  var wordCountTarget: number = 0
  var custom: dict<any> = {}

  # METHOD: Build a DocMeta from a decoded JSON dict. Missing keys get
  # defaults, so older or partial files still load.
  static def FromDict(src: dict<any>): DocMeta
    var meta: DocMeta = DocMeta.new()
    meta.label = get(src, 'label', 'None')
    meta.status = get(src, 'status', 'To Do')
    meta.synopsis = get(src, 'synopsis', '')
    meta.keywords = get(src, 'keywords', [])
    meta.wordCountTarget = get(src, 'wordCountTarget', 0)
    meta.custom = get(src, 'custom', {})
    return meta
  enddef

  def ToDict(): dict<any>
    return {
      label: this.label,
      status: this.status,
      synopsis: this.synopsis,
      keywords: this.keywords,
      wordCountTarget: this.wordCountTarget,
      custom: this.custom,
    }
  enddef

  # METHOD: Load the metadata file at sidecarPath, an absolute path. A
  # missing file gives the defaults, not an error: a document without
  # metadata is normal.
  static def Load(sidecarPath: string): DocMeta
    if !filereadable(sidecarPath)
      return DocMeta.new()
    endif
    return DocMeta.FromDict(Pe.ReadJson(sidecarPath))
  enddef

  def Save(sidecarPath: string): void
    Pe.WriteJson(sidecarPath, this.ToDict())
  enddef

  # METHOD: Set the label. Fields are written only inside the class, error
  # E1335.
  def SetLabel(newLabel: string): void
    this.label = newLabel
  enddef

  def SetStatus(newStatus: string): void
    this.status = newStatus
  enddef

  def SetSynopsis(newSynopsis: string): void
    this.synopsis = newSynopsis
  enddef

  def SetKeywords(newKeywords: list<string>): void
    this.keywords = newKeywords
  enddef

  # METHOD: Set the word count target, which the Inspector's Target field
  # edits. 0 means no target.
  def SetWordCountTarget(target: number): void
    this.wordCountTarget = target
  enddef
endclass
