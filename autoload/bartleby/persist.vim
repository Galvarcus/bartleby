vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# persist.vim: reads and writes JSON files: a dict in, a dict out. It
# knows nothing of projects or the Binder. Its callers, such as
# project.vim and document.vim, do.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/log.vim' as L

var log = L.New(expand('<sfile>:t'))

export def ReadJson(path: string): dict<any>
  if !filereadable(path)
    log.Warn(printf(IN.T("no such file: %s"), path))
    return {}
  endif
  try
    return json_decode(join(readfile(path), "\n"))
  catch
    log.Exception()
    return {}
  endtry
enddef

export def WriteJson(path: string, data: dict<any>): void
  try
    var dir: string = fnamemodify(path, ':h')
    if !isdirectory(dir)
      mkdir(dir, 'p')
    endif
    writefile([json_encode(data)], path)
  catch
    log.Exception()
  endtry
enddef
