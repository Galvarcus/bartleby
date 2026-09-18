vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# scrive.vim - locates, opens, and bootstraps scrives (Bartleby writing
# projects) under g:bartleby_binder_root. No Binder-tree or UI knowledge
# lives here - that's project.vim and binder.vim respectively.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/templates.vim' as Tm
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var binderroot: string = g:bartleby_binder_root

export const SCRIVE_EXT: string = '.bartleby'

# g:bartleby_binder_root wins when set; falls back to ~/Documents. Scrives
# themselves live one level down, in a "Bartleby" folder under that root -
# e.g. the ~/Documents default puts them at ~/Documents/Bartleby.
export def BinderRoot(): string
  var normalized: string = substitute(fnamemodify(binderroot, ':p'), '[/\\]$', '', '')
  return normalized .. '/Bartleby'
enddef

export def ScrivePath(name: string): string
  return BinderRoot() .. '/' .. name .. SCRIVE_EXT
enddef

# Every *.bartleby directory directly under the binder root, by bare name.
export def ListScrives(): list<string>
  var root: string = BinderRoot()
  if !isdirectory(root)
    return []
  endif
  return globpath(root, '*' .. SCRIVE_EXT, false, true)
    ->filter((_, p) => isdirectory(p))
    ->mapnew((_, p) => fnamemodify(p, ':t:r'))
enddef

# Loads an existing scrive by name. null_object if the directory or its
# project.json is missing/unreadable.
export def Open(name: string): Pj.Project
  var dir: string = ScrivePath(name)
  if !isdirectory(dir)
    log.Error($'no scrive named "{name}" under {BinderRoot()}')
    return null_object
  endif
  var project: Pj.Project = Pj.Project.new(dir)
  if !project.Load()
    return null_object
  endif
  return project
enddef

# Bootstraps a brand-new scrive on disk: binder/ dir, a project.json seeded
# with DefaultTree()'s starter folders/documents for `projectType`, and the
# matching empty files on disk. Returns it loaded.
export def Create(name: string, projectType: string = Pj.TYPE_NOVEL): Pj.Project
  var dir: string = ScrivePath(name)
  if isdirectory(dir)
    log.Error($'scrive "{name}" already exists at {dir}')
    return null_object
  endif
  mkdir(dir .. '/binder', 'p')
  var project: Pj.Project = Pj.Project.new(dir)
  project.InitNew(name, projectType)
  var tree: list<BI.BinderItem> = Tm.DefaultTree(projectType, project.DocExt())
  Tm.Materialize(tree, project.BinderRoot())
  project.SeedTree(tree)
  project.Save()
  return project
enddef
