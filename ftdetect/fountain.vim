" Plugin_Name: Bartleby
" ftdetect/fountain.vim - *.fountain gets its own real filetype rather
" than falling back on whatever (if anything) the user's own Vim
" runtime happens to guess - syntax/fountain.vim and Spotlight's
" fountain-aware dialogue detection both depend on &filetype being
" reliably 'fountain', not left to chance.
" License: GNU GPL 3.0
autocmd BufRead,BufNewFile *.fountain setfiletype fountain
