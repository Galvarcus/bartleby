vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# profile.vim - author/contact info for Compile (name, author, address,
# phone, email). Global default + optional per-scrive override, merged
# field-by-field (blank scrive field falls back to global). Edited via
# formpopup.vim.
#
# ProjectInfo is defined before the functions that use it, not just by
# convention: several of them use ProjectInfo in their own parameter or
# return type, and Vim9 resolves a function's signature eagerly at
# definition time - unlike a class used only inside a function body,
# which can forward-reference one defined later in the file just fine.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/persist.vim' as Pe
import autoload 'bartleby/inputpopup.vim' as IP
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

const FIELDS: list<string> = ['name', 'authorname', 'address', 'city', 'state',
  'countrycode', 'zip', 'phonenumber', 'email']

export class ProjectInfo
  var name: string = ''
  var authorname: string = ''
  var address: string = ''
  var city: string = ''
  var state: string = ''
  var countrycode: string = ''
  var zip: string = ''
  var phonenumber: string = ''
  var email: string = ''

  static def FromDict(src: dict<any>): ProjectInfo
    var info: ProjectInfo = ProjectInfo.new()
    info.name = get(src, 'name', '')
    info.authorname = get(src, 'authorname', '')
    info.address = get(src, 'address', '')
    info.city = get(src, 'city', '')
    info.state = get(src, 'state', '')
    info.countrycode = get(src, 'countrycode', '')
    info.zip = get(src, 'zip', '')
    info.phonenumber = get(src, 'phonenumber', '')
    info.email = get(src, 'email', '')
    return info
  enddef

  def ToDict(): dict<any>
    return {name: this.name, authorname: this.authorname, address: this.address,
      city: this.city, state: this.state, countrycode: this.countrycode,
      zip: this.zip, phonenumber: this.phonenumber, email: this.email}
  enddef

  # Author name falls back to name when left blank.
  def EffectiveAuthor(): string
    return this.authorname !=# '' ? this.authorname : this.name
  enddef
endclass

export def GlobalPath(): string
  return expand('~/.bartleby/profile.json')
enddef

export def ScriveInfoPath(project: Pj.Project): string
  return project.scriveDir .. '/project-info.json'
enddef

def LoadFrom(path: string): ProjectInfo
  if !filereadable(path)
    return ProjectInfo.new()
  endif
  return ProjectInfo.FromDict(Pe.ReadJson(path))
enddef

export def LoadGlobal(): ProjectInfo
  return LoadFrom(GlobalPath())
enddef

export def LoadForScrive(project: Pj.Project): ProjectInfo
  return LoadFrom(ScriveInfoPath(project))
enddef

# Per-field merge: a blank scrive-level field falls back to global.
export def Resolve(project: Pj.Project): ProjectInfo
  var g: dict<any> = LoadGlobal().ToDict()
  var s: dict<any> = LoadForScrive(project).ToDict()
  var merged: dict<any> = {}
  for f in FIELDS
    merged[f] = get(s, f, '') !=# '' ? s[f] : get(g, f, '')
  endfor
  return ProjectInfo.FromDict(merged)
enddef

def FormLayout(): list<list<string>>
  return [['name'], ['authorname'], ['address'],
    ['city', 'state', 'countrycode', 'zip'], ['phonenumber'], ['email']]
enddef

def FormLabels(): dict<string>
  return {authorname: 'Author Name', countrycode: 'Country Code',
    zip: 'Zip Code', phonenumber: 'Phone Number'}
enddef

def SaveAndValidate(path: string, values: dict<any>, requireName: bool): void
  if requireName && get(values, 'name', '') ==# ''
    log.Error('Name is required')
    return
  endif
  Pe.WriteJson(path, values)
enddef

export def EditGlobal(): void
  var current: dict<any> = LoadGlobal().ToDict()
  var form: IP.InputPopup = IP.InputPopup.new(IP.TextFields(FormLayout()), current,
    {title: ' Bartleby Profile ', labels: FormLabels()})
  form.OnSubmit((values: dict<any>) => {
    SaveAndValidate(GlobalPath(), values, true)
  })
  form.Open()
enddef

export def EditForScrive(project: Pj.Project): void
  var globalDict: dict<any> = LoadGlobal().ToDict()
  var current: dict<any> = Resolve(project).ToDict()
  var form: IP.InputPopup = IP.InputPopup.new(IP.TextFields(FormLayout()), current,
    {title: $' {project.name} Info ', labels: FormLabels()})
  form.OnSubmit((values: dict<any>) => {
    var overrides: dict<any> = {}
    for key in keys(values)
      overrides[key] = values[key] ==# get(globalDict, key, '') ? '' : values[key]
    endfor
    SaveAndValidate(ScriveInfoPath(project), overrides, false)
  })
  form.Open()
enddef
