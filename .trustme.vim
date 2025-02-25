" vim:tw=0:ts=2:sw=2:et:norl:nospell:ft=vim
" Author: Landon Bouma <https://tallybark.com/>
" Project: https://github.com/landonb/trust_me#🧿
" License: GPLv3

" -------------------------------------------------------------------

" USAGE:
"
"   1. Copy this file to your project under .trustme/
"
"   2. Replace /path/to/project/tags with the path to your tags file
"
"   3. Symlink .trustme.sh under .trustme/

" -------------------------------------------------------------------

" SAVVY: The tags path cannot be relative.

let s:project_tags="/path/to/project/tags"

if exists(s:project_tags)
  exec 'set tags=./tags,tags,' .. s:project_tags
endif

" -------------------------------------------------------------------

" If you open from project.vim (via the magic in=""), then neither
" of these globals will have been set by dubs_edit_juice.vim.
" - CXREF: SeekForSecurityHolePluginFileToLoad
"   ~/.kit/nvim/landonb/dubs_edit_juice/plugin/dubs_edit_juice.vim @ 1712
if !exists("g:DUBS_TRUST_ME_ON_FILE")
  let g:DUBS_TRUST_ME_ON_FILE = '<project.vim>'
endif
if !exists("g:DUBS_TRUST_ME_ON_SAVE")
  let g:DUBS_TRUST_ME_ON_SAVE = 0
endif

" -------------------------------------------------------------------

" CXREF: If installed via DepoXy, found at:
"   ~/.kit/sh/trust_me/.trustme.sh
let s:cmd = '!' .
  \ ' DUBS_TRUST_ME_ON_FILE=' . shellescape(g:DUBS_TRUST_ME_ON_FILE) .
  \ ' DUBS_TRUST_ME_ON_SAVE=' . shellescape(g:DUBS_TRUST_ME_ON_SAVE) .
  \ ' ' .. expand('<script>:h') .. '/.trustme.sh &'

" Do not run if invoked as EDITOR.
" - This check is not perfect and relies on business logic.
" - One option is to check if run as GVim or not, because author
"   (and DepoXy) users would generally invoke GVim with a specific
"   --servername, e.g.,
"     if (v:servername != '')
"       ...
" - Another option is to check $EDITOR environ, but this, too, relies
"   on user- (or DepoXy-) specific knowledge, namely that when invoked
"   per EDITOR, author (and DepoXy) users specify a minimal Vim config:
"     ~/.kit/nvim/nvim-depoxy/bin/editor-vim-0-0-insert-minimal
" - For coverage, we'll use both checks, though note:
"   - Checking v:servername assumes EDITOR never used to invoke GVim.
"   - Checking $EDITOR handles use case where user runs `vim` in terminal.
if (v:servername != "") || (fnamemodify($EDITOR, ":h") != "editor-vim-0-0-insert-minimal")
  silent exec s:cmd
endif

