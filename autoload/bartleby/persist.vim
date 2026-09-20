vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# persist.vim - thin JSON file I/O. Single job: dict in, dict out, on disk.
# No knowledge of project/binder shape lives here - that belongs to whoever
# calls this (project.vim, document.vim).
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

export def ReadJson(path: string): dict<any>
  if !filereadable(path)
    log.Warn($'no such file: {path}')
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
