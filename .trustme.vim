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
"   ~/.vim/pack/landonb/start/dubs_edit_juice/plugin/dubs_edit_juice.vim @ 1712
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

" Do not run if invoked as EDITOR. This isn't quite how you check, but it works.
if (v:servername != '')
  silent exec s:cmd
endif

