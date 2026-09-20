vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# document.vim - metadata attached to a document-kind BinderItem: label,
# status, synopsis, keywords, freeform custom fields. Kept separate from
# BinderItem so it can be loaded lazily - the Binder sidebar never needs it,
# Corkboard/Inspector (later phases) do. Persisted as a JSON sidecar next to
# the document's text file.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/persist.vim' as Pe

# Display strings doubling as stored values - shown verbatim in the
# label/status popupbuttons picker (see picker.vim), so no separate
# slug<->display mapping to keep in sync.
export const LABELS: list<string> = ['None', 'Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Purple']
export const STATUSES: list<string> = ['To Do', 'First Draft', 'Revised', 'Done']

export class DocMeta
  var label: string = 'None'
  var status: string = 'To Do'
  var synopsis: string = ''
  var keywords: list<string> = []
  var wordCountTarget: number = 0
  var custom: dict<any> = {}

  # Builds a DocMeta from a decoded JSON dict, tolerating missing keys so
  # older/partial sidecars still load.
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

  # sidecarPath is absolute. Missing file yields plain defaults rather than
  # an error - a document with no metadata yet is a normal state.
  static def Load(sidecarPath: string): DocMeta
    if !filereadable(sidecarPath)
      return DocMeta.new()
    endif
    return DocMeta.FromDict(Pe.ReadJson(sidecarPath))
  enddef

  def Save(sidecarPath: string): void
    Pe.WriteJson(sidecarPath, this.ToDict())
  enddef

  # Field writes stay inside the class - same E1335 reasoning as elsewhere.
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

  # No Outliner/Inspector UI sets this yet - added now so the field round-
  # trips through ToDict/FromDict once one does.
  def SetWordCountTarget(target: number): void
    this.wordCountTarget = target
  enddef
endclass
