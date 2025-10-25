function! coqtop#new()"{{{
  let l:coq = deepcopy(s:coq)
  call l:coq.start()
  return l:coq
endfunction"}}}

let s:coq = {
      \ 'proc': {},
      \ 'bufnr': -1,
      \ 'last_line': 0,
      \ 'backtrack': {},
      \ 'match_id': 0,
      \ }

function! s:coq_project_options()
  let inputfile = "./_CoqProject"
  let array = []
  if filereadable(inputfile)
    for line in readfile(inputfile)
      let array = array + split(line, "")
    endfor
  endif
  return array
endfunction

function! s:coq.start()"{{{
  let self.proc = vimproc#popen2(['coqtop', '-emacs'] + s:coq_project_options())

  rightbelow vnew
    let self.bufnr = bufnr('%')
    setlocal buftype=nofile bufhidden=hide noswapfile
  wincmd p
  let l:buf = self.read_until_prompt(1)
  let l:buf = substitute(l:buf, '</prompt>.*$', '', '')
  let [l:msg, l:prompt] = split(l:buf, '<prompt>')
  call self.display(split(l:msg, '\n'))

  let self.backtrack[0] = s:parse_prompt(l:prompt)

  command! -buffer CoqQuit call b:coq.quit()
  command! -buffer CoqClear call b:coq.clear()
  command! -buffer CoqGoto call b:coq.goto()
  command! -buffer -nargs=1 CoqPrint call b:coq.print(<q-args>)
  command! -buffer -nargs=1 CoqSearchAbout call b:coq.search_about(<q-args>)

  inoremap <buffer> <expr> <Plug>(coqtop-goto) <SID>coqgoto_i()
  if !exists('g:coqtop_no_default_mappings') || !g:coqtop_no_default_mappings
    nnoremap <buffer> <silent> <LocalLeader>q :<C-u>CoqQuit<CR>
    nnoremap <buffer> <silent> <LocalLeader>c :<C-u>CoqClear<CR>
    nnoremap <buffer> <silent> <LocalLeader>g :<C-u>CoqGoto<CR>
    nnoremap <buffer> <silent> <LocalLeader>p :<C-u>CoqPrint<Space>
    nnoremap <buffer> <silent> <LocalLeader>a :<C-u>CoqSearchAbout<Space>
    imap <buffer> <C-g> <Plug>(coqtop-goto)
  endif

  hi def link coqtopFrozen Folded
  augroup coqtop
    autocmd CursorMoved,CursorMovedI <buffer> call b:coq.check_line()
  augroup END
endfunction"}}}"}}}

function! s:coqgoto_i()"{{{
  let l:prefix = "\<Esc>:\<C-u>CoqGoto\<CR>"
  if line('.') == line('$')
    return l:prefix . 'o'
  else
    return l:prefix . 'jO'
  endif
endfunction"}}}

function! s:coq.check_line()"{{{
  let l:line = line('.')
  if l:line <= self.last_line-1 && l:line < line('$')
    setlocal nomodifiable
  else
    setlocal modifiable
  endif
endfunction"}}}

function! s:coq.quit()"{{{
  call self.proc.stdin.write("Quit.\n")
  call self.proc.waitpid()

  let l:winnr = bufwinnr(self.bufnr)
  let l:cur = winnr()
  if l:winnr != -1
    execute l:winnr 'wincmd w'
    close
    execute l:cur 'wincmd w'
  endif

  unlet b:coq
  augroup coqtop
    autocmd!
  augroup END

  delcommand CoqQuit
  delcommand CoqClear
  delcommand CoqGoto
  delcommand CoqPrint
  delcommand CoqSearchAbout

  if !exists('g:coqtop_no_default_mappings') || !g:coqtop_no_default_mappings
    nunmap <buffer> <LocalLeader>q
    nunmap <buffer> <LocalLeader>c
    nunmap <buffer> <LocalLeader>g
    nunmap <buffer> <LocalLeader>p
    nunmap <buffer> <LocalLeader>a
    iunmap <buffer> <C-g>
  endif

  setlocal modifiable
endfunction"}}}

function! s:coq.clear()"{{{
  call self.proc.stdin.write("Quit.\n")
  call self.proc.waitpid()
  let self.proc = vimproc#popen2(['coqtop', '-emacs'] + s:coq_project_options())
  let self.last_line = 0
  let self.backtrack = {}
  if self.match_id > 0
    let self.match_id = matchdelete(self.match_id)
  end
  let l:buf = self.read_until_prompt(1)
  let l:buf = substitute(l:buf, '</prompt>.*$', '', '')
  let [l:msg, l:prompt] = split(l:buf, '<prompt>')
  call self.display(split(l:msg, '\n'))
endfunction"}}}

function! s:coq.goto() abort"{{{
  let l:end = line(".")
  if l:end <= self.last_line
    call self.clear()
    call self.eval_to(l:end)
  else
    call self.eval_to(l:end)
  endif
  if self.match_id > 0
    call matchdelete(self.match_id)
  endif
  let self.match_id = matchadd('coqtopFrozen', '\%' . self.last_line . 'l'. '\%1c')
endfunction"}}}

function! s:coq.eval_to(end) abort"{{{
  let l:lines = getline(self.last_line+1, a:end)
  let l:count = s:count_dots(l:lines, self.last_line+1)
  if l:count == 0
    return
  endif
  let l:input = join(l:lines, "\n") . "\n"
  call self.proc.stdin.write(l:input)
  let l:buf = self.read_until_prompt(l:count)
  let l:lineno = self.last_line + 1
  let l:outputs = split(l:buf, '</prompt>')
  let l:len = len(l:outputs)
  let l:i = 0
  while l:i < l:len
    let l:r = s:count_dots([l:lines[l:lineno - self.last_line - 1]], l:lineno)
    while l:r == 0
      let l:lineno += 1
      let l:r = s:count_dots([l:lines[l:lineno - self.last_line - 1]], l:lineno)
    endwhile
    let [l:msg, l:prompt] = split(l:outputs[l:i + (l:r-1)], '<prompt>')
    let self.backtrack[l:lineno] = s:parse_prompt(l:prompt)
    let l:lineno += 1
    let l:i += l:r
  endwhile
  let self.last_line = l:lineno - 1
  call self.display(split(l:msg, '\n'))
endfunction"}}}

function! s:count_dots(lines, lineno)"{{{
  let l:count = 0
  let l:lineno = a:lineno
  let l:bullet_regexps = ['^ *-$','^ *- ', '^ *+', '^ *\*']
  for l:line in a:lines
    if match(l:line, '\<Add LoadPath\>') == 0
      let l:count += 1
      continue
    endif

    " ' .. 'がある場合は1行のNotations with recursive patternsとして扱う
    if match(l:line, ' \.\. ') != -1
      let l:count += 1
      continue
    endif

    if match(l:line, '\.\{-2,}') != -1
      return 0
    endif

    if match(l:line, '\<Require Import\>') != -1
      if synIDattr(synID(l:lineno, 1, 1), 'name') !~# 'Comment'
        let l:count += 1
      endif
      let l:lineno += 1
      continue
    endif

    for bullet_regexp in l:bullet_regexps
      if match(l:line, bullet_regexp) == 0 && synIDattr(synID(l:lineno, 1, 1), 'name') !~# 'Comment'
        let l:count += 1
      endif
    endfor

    if match(l:line, 'Notation') == 0
      let l:count += 1
    else
      let l:pos = match(l:line, '\(\. \|\.$\)')
      while l:pos != -1
        if synIDattr(synID(l:lineno, l:pos+1, 1), 'name') !~# 'Comment'
          let l:count += 1
        endif
        let l:pos = match(l:line, '\(\. \|\.$\)', l:pos+1)
      endwhile
    endif
    let l:lineno += 1
  endfor
  return l:count
endfunction"}}}

function! s:coq.read_until_prompt(n)"{{{
  let l:buf = ''
  while match(l:buf, '</prompt>', 0, a:n) == -1
    let l:buf .= self.proc.stdout.read(-1, 100)
  endwhile
  return l:buf
endfunction"}}}

function! s:parse_prompt(prompt) abort"{{{
  let l:prompt = substitute(a:prompt, '^\s*', '', '')
  let l:dict = {}
  let l:id_and_nums = split(l:prompt, '\s*<\s*')
  let l:dict.id = l:id_and_nums[0]
  let l:env = split(l:id_and_nums[1], '\s*|\s*')
  let l:dict.env_state = l:env[0]
  let l:dict.opened_proofs = l:env[1 : -2]
  let l:dict.proof_state = l:env[-1]
  return l:dict
endfunction"}}}

function! s:coq.display(lines)"{{{
  try
    let l:cur = winnr()
    execute bufwinnr(self.bufnr) 'wincmd w'
    silent %delete _
    call setline(1, a:lines)
  finally
    execute l:cur 'wincmd w'
  endtry
endfunction"}}}

function! s:coq.exec_and_display(cmd)"{{{
  call self.proc.stdin.write(a:cmd)
  let l:buf = self.read_until_prompt(1)
  let l:buf = substitute(l:buf, '</prompt>.*$', '', '')
  let [l:msg, l:prompt] = split(l:buf, '<prompt>')
  call self.display(split(l:msg, '\n'))
endfunction"}}}

function! s:coq.print(id)"{{{
  call self.exec_and_display('Print ' . a:id . ".\n")
endfunction"}}}

function! s:coq.search_about(input)"{{{
  call self.exec_and_display('SearchAbout ' . a:input . ".\n")
endfunction"}}}
