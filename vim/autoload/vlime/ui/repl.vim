function! vlime#ui#repl#InitREPLBuf(conn)
    let repl_buf = bufnr(vlime#ui#REPLBufName(a:conn), v:true)
    if !vlime#ui#VlimeBufferInitialized(repl_buf)
        call vlime#ui#SetVlimeBufferOpts(repl_buf, a:conn)
        call setbufvar(repl_buf, '&filetype', 'vlime_repl')
        call vlime#ui#WithBuffer(repl_buf, function('s:InitREPLBuf'))
    endif
    return repl_buf
endfunction

function! vlime#ui#repl#AppendOutput(repl_buf, str)
    let repl_winnr = bufwinnr(a:repl_buf)
    call setbufvar(a:repl_buf, '&modifiable', 1)
    if repl_winnr > 0
        " If the REPL buffer is visible, move to that window to enable
        " automatic scrolling
        let old_win_id = win_getid()
        try
            execute repl_winnr . 'wincmd w'
            call vlime#ui#AppendString(a:str)
        finally
            call win_gotoid(old_win_id)
        endtry
    else
        call vlime#ui#WithBuffer(a:repl_buf,
                    \ function('vlime#ui#AppendString', [a:str]))
    endif
    call setbufvar(a:repl_buf, '&modifiable', 0)
endfunction

function! vlime#ui#repl#InspectCurREPLPresentation()
    if index(b:vlime_conn.cb_data['contribs'], 'SWANK-PRESENTATIONS') < 0
        call vlime#ui#ErrMsg('SWANK-PRESENTATIONS is not available.')
        return
    endif

    let p_coord = s:FindCurCoord(
                \ getcurpos(), getbufvar('%', 'vlime_repl_coords', {}))
    if type(p_coord) == type(v:null)
        return
    endif

    if p_coord['type'] == 'PRESENTATION'
        call b:vlime_conn.InspectPresentation(
                    \ p_coord['id'], v:true,
                    \ {c, r -> c.ui.OnInspect(c, r, v:null, v:null)})
    endif
endfunction

function! vlime#ui#repl#YankCurREPLPresentation()
    let p_coord = s:FindCurCoord(
                \ getcurpos(), getbufvar('%', 'vlime_repl_coords', {}))
    if type(p_coord) == type(v:null)
        return
    endif

    if p_coord['type'] == 'PRESENTATION'
        let @" = '(swank:lookup-presented-object ' . p_coord['id'] . ')'
        echom 'Presented object ' . p_coord['id'] . ' yanked.'
    endif
endfunction

function! vlime#ui#repl#ClearREPLBuffer()
    setlocal modifiable
    1,$delete _
    if exists('b:vlime_repl_pending_coords')
        unlet b:vlime_repl_pending_coords
    endif
    if exists('b:vlime_repl_coords')
        unlet b:vlime_repl_coords
    endif
    call s:ShowREPLBanner(b:vlime_conn)
    setlocal nomodifiable
endfunction

function! vlime#ui#repl#NextField(forward)
    if !exists('b:vlime_repl_coords') || len(b:vlime_repl_coords) <= 0
        return
    endif

    let cur_pos = getcurpos()
    let sorted_coords = sort(copy(b:vlime_repl_coords),
                \ function('s:CoordSorter', [a:forward]))
    let next_coord = v:null
    for c in sorted_coords
        if a:forward
            if c['begin'][0] > cur_pos[1]
                let next_coord = c
                break
            elseif c['begin'][0] == cur_pos[1] && c['begin'][1] > cur_pos[2]
                let next_coord = c
                break
            endif
        else
            if c['begin'][0] < cur_pos[1]
                let next_coord = c
                break
            elseif c['begin'][0] == cur_pos[1] && c['begin'][1] < cur_pos[2]
                let next_coord = c
                break
            endif
        endif
    endfor

    if type(next_coord) == type(v:null)
        let next_coord = sorted_coords[0]
    endif

    call setpos('.', [0, next_coord['begin'][0],
                    \ next_coord['begin'][1], 0,
                    \ next_coord['begin'][1]])
endfunction

function! s:ShowREPLBanner(conn)
    let banner = 'SWANK'
    if has_key(a:conn.cb_data, 'version')
        let banner .= ' version ' . a:conn.cb_data['version']
    endif
    if has_key(a:conn.cb_data, 'pid')
        let banner .= ', pid ' . a:conn.cb_data['pid']
    endif
    let banner_len = len(banner)
    let banner .= ("\n" . repeat('=', banner_len) . "\n")
    call vlime#ui#AppendString(banner)
endfunction

function! s:FindCurCoord(cur_pos, coords)
    if len(a:coords) <= 0
        return v:null
    endif

    " Coords at the end of the list are more likely to get chosen.
    let idx = len(a:coords) - 1
    while idx >= 0
        if vlime#ui#MatchCoord(a:coords[idx], a:cur_pos[1], a:cur_pos[2])
            return a:coords[idx]
        endif
        let idx -= 1
    endwhile

    return v:null
endfunction

function! s:InitREPLBuf()
    setlocal modifiable
    call s:ShowREPLBanner(b:vlime_conn)
    setlocal nomodifiable

    call vlime#ui#MapBufferKeys('repl')
endfunction

function! s:CoordSorter(direction, c1, c2)
    if a:c1['begin'][0] > a:c2['begin'][0]
        return a:direction ? 1 : -1
    elseif a:c1['begin'][0] == a:c2['begin'][0]
        if a:c1['begin'][1] > a:c2['begin'][1]
            return a:direction ? 1 : -1
        elseif a:c1['begin'][1] == a:c2['begin'][1]
            return 0
        else
            return a:direction ? -1 : 1
        endif
    else
        return a:direction ? -1 : 1
    endif
endfunction
