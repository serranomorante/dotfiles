" https://github.com/kevinhwang91/nvim-bqf?tab=readme-ov-file#rebuild-syntax-for-quickfix
if exists('b:current_syntax')
    finish
endif

syn match qfDirName /^.\{,70}\// nextgroup=qfFileName
syn match qfFileName /[^┃]*/ contained nextgroup=qfSeparatorLeft
syn match qfSeparatorLeft /┃/ contained

setlocal cursorline
setlocal cursorlineopt=line

let b:current_syntax = 'qf'

" Prevent quicker.nvim hl overrides
hi QuickFixHeaderHard gui=bold
hi QuickFixHeaderSoft gui=bold
hi QuickFixFilename gui=bold
hi QuickFixFilenameInvalid gui=bold
hi QuickFixLineNr gui=bold
