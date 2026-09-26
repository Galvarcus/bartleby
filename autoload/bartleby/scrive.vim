vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# scrive.vim: finds, opens, and creates scrives, the Bartleby writing
# projects, under g:bartleby_binder_root. The Binder tree is in
# project.vim and the UI in binder.vim.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/templates.vim' as Tm
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var binderroot: string = g:bartleby_binder_root

export const SCRIVE_EXT: string = '.bartleby'

# FUNCTION: Return the folder that holds the scrives: a Bartleby folder
# in g:bartleby_binder_root when it is set, else in ~/Documents. The
# default is ~/Documents/Bartleby.
export def BinderRoot(): string
  var normalized: string = substitute(fnamemodify(binderroot, ':p'), '[/\\]$', '', '')
  return normalized .. '/Bartleby'
enddef

export def ScrivePath(name: string): string
  return BinderRoot() .. '/' .. name .. SCRIVE_EXT
enddef

# FUNCTION: Return the bare name of every .bartleby folder directly in
# the binder root.
export def ListScrives(): list<string>
  var root: string = BinderRoot()
  if !isdirectory(root)
    return []
  endif
  return globpath(root, '*' .. SCRIVE_EXT, false, true)
    ->filter((_, p) => isdirectory(p))
    ->mapnew((_, p) => fnamemodify(p, ':t:r'))
enddef

# FUNCTION: Load a scrive by name, or return null_object when its folder
# or project.json is missing or cannot be read.
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

# FUNCTION: Create a scrive on disk: the binder folder, a project.json
# with the starter tree of DefaultTree for projectType, and the empty
# files of that tree. Return it loaded.
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
