vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# search.vim - project-wide text search across a scrive's documents,
# populating the quickfix list via :vimgrep. No UI beyond the one query
# prompt - results are browsed with Vim's own quickfix commands (:copen,
# :cnext, :cprev, ...) rather than a bespoke results view.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/inputpopup.vim' as IP
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

export def Run(project: Pj.Project): void
  IP.PromptText('Search scrive', '', (query: string) => {
    RunSearch(project, query)
  })
enddef

def RunSearch(project: Pj.Project, query: string): void
  if query ==# ''
    return
  endif

  var files: list<string> = globpath(project.BinderRoot(), '**/*' .. project.DocExt(), false, true)
  if empty(files)
    log.Info('no documents to search')
    return
  endif

  # \V (very nomagic): a plain-text search by default, not a regex one -
  # matches what typing a phrase into a "find in project" prompt usually
  # means. Only backslash and the pattern delimiter need escaping under \V.
  var pattern: string = '\V' .. escape(query, '/\')
  var fileArgs: string = join(files->mapnew((_, f) => fnameescape(f)), ' ')
  execute $'silent! vimgrep /{pattern}/j {fileArgs}'

  if empty(getqflist())
    log.Info($'no matches for "{query}"')
    return
  endif
  copen
enddef
