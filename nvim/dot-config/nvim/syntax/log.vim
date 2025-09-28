" Vim syntax file
" Language:         Generic log file
" Maintainer:       MTDL9 <https://github.com/MTDL9>
" Latest Revision:  2020-08-23

if exists('b:current_syntax')
  finish
endif

let s:cpo_save = &cpoptions
set cpoptions&vim


" Operators
"---------------------------------------------------------------------------
syn match pagerOperator display '[;,\?\:\.\<=\>\~\/\@\!$\%&\+\-\|\^(){}\*#]'
syn match pagerBrackets display '[\[\]]'
syn match pagerEmptyLines display '-\{3,}'
syn match pagerEmptyLines display '\*\{3,}'
syn match pagerEmptyLines display '=\{3,}'
syn match pagerEmptyLines display '- - '


" Constants
"---------------------------------------------------------------------------
syn match pagerNumber       '\<-\?\d\+\>'
syn match pagerHexNumber    '\<0[xX]\x\+\>'
syn match pagerHexNumber    '\<\d\x\+\>'
syn match pagerBinaryNumber '\<0[bB][01]\+\>'
syn match pagerFloatNumber  '\<\d.\d\+[eE]\?\>'

syn keyword pagerBoolean    TRUE FALSE True False true false
syn keyword pagerNull       NULL Null null

syn region pagerString      start=/"/ end=/"/ end=/$/ skip=/\\./
" Quoted strings, but no match on quotes like "don't", "plurals' elements"
syn region pagerString      start=/'\(s \|t \| \w\)\@!/ end=/'/ end=/$/ end=/s / skip=/\\./


" Dates and Times
"---------------------------------------------------------------------------
" Matches 2018-03-12T or 12/03/2018 or 12/Mar/2018
syn match pagerDate '\d\{2,4}[-\/]\(\d\{2}\|Jan\|Feb\|Mar\|Apr\|May\|Jun\|Jul\|Aug\|Sep\|Oct\|Nov\|Dec\)[-\/]\d\{2,4}T\?'
" Matches 8 digit numbers at start of line starting with 20
syn match pagerDate '^20\d\{6}'
" Matches Fri Jan 09 or Feb 11 or Apr  3 or Sun 3
syn keyword pagerDate Mon Tue Wed Thu Fri Sat Sun Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec nextgroup=pagerDateDay
syn match pagerDateDay '\s\{1,2}\d\{1,2}' contained

" Matches 12:09:38 or 00:03:38.129Z or 01:32:12.102938 +0700
syn match pagerTime '\d\{2}:\d\{2}:\d\{2}\(\.\d\{2,6}\)\?\(\s\?[-+]\d\{2,4}\|Z\)\?\>' nextgroup=pagerTimeZone,pagerSysColumns skipwhite

" Follows pagerTime, matches UTC or PDT 2019 or 2019 EDT
syn match pagerTimeZone '[A-Z]\{2,5}\>\( \d\{4}\)\?' contained
syn match pagerTimeZone '\d\{4} [A-Z]\{2,5}\>' contained


" Entities
"---------------------------------------------------------------------------
syn match pagerUrl        'http[s]\?:\/\/[^\n|,; '"]\+'
syn match pagerDomain     /\v(^|\s)(\w|-)+(\.(\w|-)+)+\s/
syn match pagerUUID       '\w\{8}-\w\{4}-\w\{4}-\w\{4}-\w\{12}'
syn match pagerMD5        '\<[a-z0-9]\{32}\>'
syn match pagerIPV4       '\<\d\{1,3}\(\.\d\{1,3}\)\{3}\>'
syn match pagerIPV6       '\<\x\{1,4}\(:\x\{1,4}\)\{7}\>'
syn match pagerMacAddress '\<\x\{2}\(:\x\{2}\)\{5}'
syn match pagerFilePath   '\<\w:\\[^\n|,; ()'"\]{}]\+'
syn match pagerFilePath   '[^a-zA-Z0-9"']\@<=\/\w[^\n|,; ()'"\]{}]\+'


" Syspager Columns
"---------------------------------------------------------------------------
" Syspager hostname, program and process number columns
syn match pagerSysColumns '\w\(\w\|\.\|-\)\+ \(\w\|\.\|-\)\+\(\[\d\+\]\)\?:' contains=pagerOperator,pagerSysProcess contained
syn match pagerSysProcess '\(\w\|\.\|-\)\+\(\[\d\+\]\)\?:' contains=pagerOperator,pagerNumber,pagerBrackets contained


" XML Tags
"---------------------------------------------------------------------------
" Simplified matches, not accurate with the spec to avoid false positives
syn match pagerXmlHeader       /<?\(\w\|-\)\+\(\s\+\w\+\(="[^"]*"\|='[^']*'\)\?\)*?>/ contains=pagerString,pagerXmlAttribute,pagerXmlNamespace
syn match pagerXmlDoctype      /<!DOCTYPE[^>]*>/ contains=pagerString,pagerXmlAttribute,pagerXmlNamespace
syn match pagerXmlTag          /<\/\?\(\(\w\|-\)\+:\)\?\(\w\|-\)\+\(\(\n\|\s\)\+\(\(\w\|-\)\+:\)\?\(\w\|-\)\+\(="[^"]*"\|='[^']*'\)\?\)*\s*\/\?>/ contains=pagerString,pagerXmlAttribute,pagerXmlNamespace
syn match pagerXmlAttribute    contained "\w\+=" contains=pagerOperator
syn match pagerXmlAttribute    contained "\(\n\|\s\)\(\(\w\|-\)\+:\)\?\(\w\|-\)\+\(=\)\?" contains=pagerXmlNamespace,pagerOperator
syn match pagerXmlNamespace    contained "\(\w\|-\)\+:" contains=pagerOperator
syn region pagerXmlComment     start=/<!--/ end=/-->/
syn match pagerXmlCData        /<!\[CDATA\[.*\]\]>/
syn match pagerXmlEntity       /&#\?\w\+;/


" Levels
"---------------------------------------------------------------------------
syn keyword pagerLevelEmergency EMERGENCY EMERG
syn keyword pagerLevelAlert ALERT
syn keyword pagerLevelCritical CRITICAL CRIT FATAL
syn keyword pagerLevelError ERROR ERR FAILURE SEVERE
syn keyword pagerLevelWarning WARNING WARN
syn keyword pagerLevelNotice NOTICE
syn keyword pagerLevelInfo INFO
syn keyword pagerLevelDebug DEBUG FINE
syn keyword pagerLevelTrace TRACE FINER FINEST


" Highlight links
"---------------------------------------------------------------------------
hi def link pagerNumber Number
hi def link pagerHexNumber Number
hi def link pagerBinaryNumber Number
hi def link pagerFloatNumber Float
hi def link pagerBoolean Boolean
hi def link pagerNull Constant
hi def link pagerString String

hi def link pagerDate Identifier
hi def link pagerDateDay Identifier
hi def link pagerTime Function
hi def link pagerTimeZone Identifier

hi def link pagerUrl Underlined
hi def link pagerDomain Label
hi def link pagerUUID Label
hi def link pagerMD5 Label
hi def link pagerIPV4 Label
hi def link pagerIPV6 ErrorMsg
hi def link pagerMacAddress Label
hi def link pagerFilePath Conditional

hi def link pagerSysColumns Conditional
hi def link pagerSysProcess Include

hi def link pagerXmlHeader Function
hi def link pagerXmlDoctype Function
hi def link pagerXmlTag Identifier
hi def link pagerXmlAttribute Type
hi def link pagerXmlNamespace Include
hi def link pagerXmlComment Comment
hi def link pagerXmlCData String
hi def link pagerXmlEntity Special

hi def link pagerOperator Operator
hi def link pagerBrackets Comment
hi def link pagerEmptyLines Comment

hi def link pagerLevelEmergency ErrorMsg
hi def link pagerLevelAlert ErrorMsg
hi def link pagerLevelCritical ErrorMsg
hi def link pagerLevelError ErrorMsg
hi def link pagerLevelWarning WarningMsg
hi def link pagerLevelNotice Character
hi def link pagerLevelInfo Repeat
hi def link pagerLevelDebug Debug
hi def link pagerLevelTrace Comment



let b:current_syntax = 'log'

let &cpoptions = s:cpo_save
unlet s:cpo_save
