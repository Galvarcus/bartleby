vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# search.vim: searches the text of all documents of a scrive into the
# quickfix list with :vimgrep. The only UI is the query prompt: browse
# the results with Vim's quickfix commands, such as :copen, :cnext, and
# :cprev.
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

  # Very nomagic: search for the plain text, not a regex, which is what a
  # find in project prompt usually means. With very nomagic, only the
  # backslash and the pattern delimiter need escaping.
  var pattern: string = '\V' .. escape(query, '/\')
  var fileArgs: string = join(files->mapnew((_, f) => fnameescape(f)), ' ')
  execute $'silent! vimgrep /{pattern}/j {fileArgs}'

  if empty(getqflist())
    log.Info($'no matches for "{query}"')
    return
  endif
  copen
enddef
