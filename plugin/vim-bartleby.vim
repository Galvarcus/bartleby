" =====================================================================
"  bartleby.vim - A novel structuring plugin for Vim
" =====================================================================

if exists('g:loaded_bartleby')
  finish
endif
let g:loaded_bartleby = 1

" --- Core Configuration Variables ---
if !exists('g:bartleby_manuscript_dir')
  let g:bartleby_manuscript_dir = './manuscript'
endif

if !exists('g:bartleby_output_format')
  let g:bartleby_output_format = 'epub'
endif

if !exists('g:bartleby_latex_engine')
  let g:bartleby_latex_engine = 'xelatex'
endif

if !exists('g:bartleby_font_family')
  let g:bartleby_font_family = 'EB Garamond'
endif

" --- User Command Declarations ---
command! BartlebyBinder call s:OpenBinder()
command! -nargs=? BartlebyNewChapter call s:CreateChapter(<q-args>)
command! -nargs=? BartlebyNewScene call s:CreateScene(<q-args>)
command! BartlebyCompile call s:CompileNovel()
command! BartlebyStats call s:ShowStats()

" --- Function Implementations ---

" Open manuscript folder in vertical split Netrw (The Binder)
function! s:OpenBinder()
  let l:dir = expand(g:bartleby_manuscript_dir)
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  execute 'vsplit'
  execute 'Lexplore ' . fnameescape(l:dir)
  execute 'vertical resize 30'
  echo 'Vim Bartleby: Binder activated at ' . l:dir
endfunction

" Create new chapter folder & default scene
function! s:CreateChapter(name)
  let l:ch_name = a:name
  if l:ch_name == ''
    let l:ch_name = input('Enter chapter title (e.g. Chapter 1 Sunrise): ')
  endif
  if l:ch_name == ''
    return
  endif

  " Sanitize chapter folder name for filesystem
  let l:folder_name = tolower(l:ch_name)
  let l:folder_name = substitute(l:folder_name, '\s\+', '_', 'g')
  let l:folder_name = substitute(l:folder_name, '[:''"?,.!]', '', 'g')

  let l:full_path = expand(g:bartleby_manuscript_dir) . '/' . l:folder_name
  if !isdirectory(l:full_path)
    call mkdir(l:full_path, 'p')
  endif

  " Scaffold first scene
  let l:scene_path = l:full_path . '/scene_1.md'
  execute 'edit ' . fnameescape(l:scene_path)

  call setline(1, '# ' . l:ch_name)
  call setline(2, '')
  call setline(3, 'Write your first scene draft here in standard markdown...')
  execute 'write'
  echo 'Chapter scaffolding compiled successfully: ' . l:folder_name
endfunction

" Create new scene inside current chapter directory
function! s:CreateScene(name)
  let l:scene_name = a:name
  if l:scene_name == ''
    let l:scene_name = input('Enter scene file name: ')
  endif
  if l:scene_name == ''
    return
  endif

  let l:file_name = tolower(l:scene_name)
  let l:file_name = substitute(l:file_name, '\s\+', '_', 'g') . '.md'

  " Detect if current buffer resides in a chapter folder
  let l:curr_dir = expand('%:p:h')
  let l:manuscript_full = fnamemodify(expand(g:bartleby_manuscript_dir), ':p')

  let l:target_dir = l:manuscript_full
  if l:curr_dir =~# l:manuscript_full
    let l:target_dir = l:curr_dir
  endif

  let l:scene_path = l:target_dir . '/' . l:file_name
  execute 'edit ' . fnameescape(l:scene_path)

  call setline(1, '# ' . l:scene_name)
  call setline(2, '')
  call setline(3, 'Start writing your next manuscript scene here...')
  execute 'write'
  echo 'Scene draft initialised: ' . l:scene_path
endfunction

" Compile the manuscript recursively using Pandoc & LaTeX engines
function! s:CompileNovel()
  echo 'Vim Bartleby: Compiling manuscript drafts...'
  let l:output_file = 'novel.' . g:bartleby_output_format
  let l:manuscript_dir = expand(g:bartleby_manuscript_dir)
  let l:draft_temp = 'drafts_compiled.md'

  " Step 1: Concatenate drafts in hierarchical sequence
  if has('win32')
    let l:concat_cmd = 'powershell -Command "Get-ChildItem -Path ' . l:manuscript_dir . ' -Filter *.md -Recurse | Sort-Object FullName | Get-Content | Out-File -FilePath ' . l:draft_temp . ' -Encoding utf8"'
  else
    let l:concat_cmd = 'find ' . shellescape(l:manuscript_dir) . ' -name "*.md" | sort | xargs cat > ' . shellescape(l:draft_temp)
  endif
  echo "Compiling draft with " . l:concat_cmd
  call system(l:concat_cmd)

  " Step 2: Invoke pandoc compilation routine
  let l:compile_cmd = ''
  if g:bartleby_output_format ==# 'pdf'
    let l:compile_cmd = 'pandoc ' . shellescape(l:draft_temp) . ' -o ' . shellescape(l:output_file) . ' --pdf-engine=' . shellescape(g:bartleby_latex_engine) . ' -V geometry:margin=0.75in -V mainfont=' . shellescape(g:bartleby_font_family)
  elseif g:bartleby_output_format ==# 'epub'
    let l:compile_cmd = 'pandoc ' . shellescape(l:draft_temp) . ' -o ' . shellescape(l:output_file) . ' --toc --standalone'
  endif

  echo 'Executing compiler macro: ' . l:compile_cmd
  let l:res = system(l:compile_cmd)

  " Step 3: Clean temporary concatenations
  if filereadable(l:draft_temp)
    call delete(l:draft_temp)
  endif

  echo 'Compilation successful. eBook compiled output: ' . l:output_file
endfunction

" Calculate stats and total word count across all scenes
function! s:ShowStats()
  let l:manuscript_dir = expand(g:bartleby_manuscript_dir)
  if !isdirectory(l:manuscript_dir)
    echo 'Vim Bartleby: Manuscript directory not initialized.'
    return
  endif

  if has('win32')
    let l:word_count_cmd = 'powershell -Command \"(Get-ChildItem -Path ' . l:manuscript_dir . ' -Filter *.md -Recurse | Get-Content | Measure-Object -Word).Words\"'
  else
    let l:word_count_cmd = 'find ' . shellescape(l:manuscript_dir) . ' -name "*.md" -exec cat {} + | wc -w'
  endif

  let l:total_words = trim(system(l:word_count_cmd))
  echo '=== BARTLEBY MANUSCRIPT STATS ==='
  echo 'Manuscript Folder: ' . l:manuscript_dir
  echo 'Draft Word Count:  ' . l:total_words . ' words'
endfunction

" --- Keybindings Mapping Setup ---
" let l:map_trigger = 's'
execute 'nnoremap <silent> <leader> s b :BartlebyBinder<CR>'
execute 'nnoremap <silent> <leader> s n :BartlebyNewScene<CR>'
execute 'nnoremap <silent> <leader> s c :BartlebyCompile<CR>'
execute 'nnoremap <silent> <leader> s w :BartlebyStats<CR>'
