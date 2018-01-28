" USAGE:
"
"   1. Copy this file to the base of your project.
"
"   2. Replace /path/to/project herein with the full path to your project.
"
"   3. Symlink .trustme.sh to the base of your project.

" NOTE: The tags path cannot be relative.
set tags=/path/to/project/tags

" If you open from project.vim (via the magic in=""),
" then neither of these globals will have been set
" by dubs_edit_juice.vim.
if !exists("g:DUBS_TRUST_ME_ON_FILE")
  let g:DUBS_TRUST_ME_ON_FILE = '<project.vim>'
endif
if !exists("g:DUBS_TRUST_ME_ON_SAVE")
  let g:DUBS_TRUST_ME_ON_SAVE = 0
endif

let s:cmd = '!' .
  \ ' DUBS_TRUST_ME_ON_FILE=' . shellescape(g:DUBS_TRUST_ME_ON_FILE) .
  \ ' DUBS_TRUST_ME_ON_SAVE=' . shellescape(g:DUBS_TRUST_ME_ON_SAVE) .
  \ ' /path/to/project/.trustme.sh &'
silent exec s:cmd

