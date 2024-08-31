if exists('b:current_syntax')
    finish
endif

syn match GrappleId /^\/\d* / conceal nextgroup=grappleDirname
syn match grappleDirname /.*\// contained

hi def link grappleDirname Comment

let b:current_syntax = 'grapple'
