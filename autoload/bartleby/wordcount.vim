vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# wordcount.vim: counts the words of documents and folders, for the
# Outliner. A word is a run of characters between white space.
#
# A document open in a buffer is counted from the buffer, so that text not
# yet saved counts. Any other document is counted from its file, and the
# count is kept until the size or the time of the file changes, so that an
# unchanged file is read once. Totals counts each document once, and adds
# the counts up into the totals of the folders.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI

# The words of each file read: path to size, time, and count.
var cache: dict<list<number>> = {}

# FUNCTION: Return the number of words in lines.
export def Count(lines: list<string>): number
  return len(split(join(lines, ' ')))
enddef

# FUNCTION: Return the loaded buffers, as full path to buffer number.
def LoadedBuffers(): dict<number>
  var buffers: dict<number> = {}
  for info in getbufinfo({bufloaded: 1})
    if info.name !=# ''
      buffers[fnamemodify(info.name, ':p')] = info.bufnr
    endif
  endfor
  return buffers
enddef

# FUNCTION: Return the words of the document at path: from its buffer when
# it is loaded, or else from its file, through the cache. A missing file
# has no words.
def DocumentWords(path: string, buffers: dict<number>): number
  if has_key(buffers, path)
    return Count(getbufline(buffers[path], 1, '$'))
  endif
  if !filereadable(path)
    return 0
  endif
  var stamp: list<number> = [getfsize(path), getftime(path)]
  var known: list<number> = get(cache, path, [])
  if !empty(known) && known[0 : 1] == stamp
    return known[2]
  endif
  var words: number = Count(readfile(path))
  cache[path] = stamp + [words]
  return words
enddef

# FUNCTION: Return the words of items and of everything inside them, as the
# id of each item to its count. A folder counts the words of all the
# documents inside it.
export def Totals(items: list<BI.BinderItem>, binderRoot: string): dict<number>
  var totals: dict<number> = {}
  var buffers: dict<number> = LoadedBuffers()
  def Walk(item: BI.BinderItem): number
    var words: number = 0
    if item.IsDocument()
      words = DocumentWords(item.AbsPath(binderRoot), buffers)
    else
      for child in item.children
        words += Walk(child)
      endfor
    endif
    totals[item.id] = words
    return words
  enddef
  for item in items
    Walk(item)
  endfor
  return totals
enddef

# FUNCTION: Forget the counts of all files. The tests use it.
export def ClearCache(): void
  cache = {}
enddef
