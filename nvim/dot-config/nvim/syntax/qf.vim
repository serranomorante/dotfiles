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
hi QuickFixHeaderHard gui=nocombine
hi QuickFixHeaderSoft gui=nocombine
hi QuickFixFilename gui=nocombine
hi QuickFixFilenameInvalid gui=nocombine
hi QuickFixLineNr gui=nocombine
