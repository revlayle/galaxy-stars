; Explosions (spec section 6): the list, drawing over the 3x3 tiles, and the area checks.
; An explosion covers the 3x3 tiles around its centre tile, clipped to the playfield, for FRAMES frames. Stationary
; stars in those tiles are set off; the player and hostile stars are hit only within its round core (hits()).
; `cover` counts the explosions over each tile: star color changes skip covered tiles, and a tile is
; redrawn from the map only when its last explosion ends.
; Stars caught by one explosion explode one after another: in random order, each STAGGER frames after the last.
; Frame time: the tiles of an ended explosion are restored through a queue, one explosion per frame (the danger
; ends on time); stars.update starts at most one supernova per frame (`starts`).

%import video
%import stars
%import player
%import score

explode {
    const ubyte MAX = 8                 ; [TUNE] explosions at once; a new one takes the oldest slot when full
    const ubyte FRAMES = 30             ; [TUNE] 0.6 s, dangerous for the whole time
    const ubyte COLOR = assets.TILE_EXPLODE_0_COLOR | video.MC
    const ubyte ART = assets.TILE_EXPLODE_0_TL     ; first char of the explosion art (for the assembly)
    &ubyte[video.MAP_W * video.MAP_H] cover = $C600

    ubyte[MAX] col
    ubyte[MAX] row
    ubyte[MAX] timer                    ; frames left, 0 = free slot
    uword[MAX] core_x                   ; each explosion's centre in playfield pixels (centre of its centre tile)
    ubyte[MAX] core_y
    ; [TUNE] the round core that hurts the player and destroys hostiles (designer, 2026-10-18; was the whole 3x3
    ; square): their centre closer than REACH to the explosion's centre, measured as the longer side plus half the
    ; shorter (an octagon). The bright part of the art is about 36 px across; 22 adds a little for the body.
    const ubyte REACH = 22
    uword @shared obj_x                 ; hits(): centre of the object to test
    ubyte @shared obj_y
    ubyte started                       ; explosions started (debug readout)
    ubyte starts                        ; explosions started this frame
    ubyte live                          ; explosions running
    const ubyte QUEUE = 16
    ubyte[QUEUE] queue_col              ; centres of ended explosions whose tiles are still to restore
    ubyte[QUEUE] queue_row
    ubyte queued
    ubyte[9] caught_stars               ; stars in the area of the explosion being started (a hurl's centre tile can hold one)

    ; area set by area_at()
    ubyte c0
    ubyte c1
    ubyte r0
    ubyte r1

    sub clear() {
        sys.memset(&cover, len(cover), 0)
        sys.memset(&timer, MAX, 0)
        queued = 0
        starts = 0
        live = 0
    }

    sub area_at(ubyte c, ubyte r) {
        ; The 3x3 tiles around tile (c, r), clipped to the playfield, in c0-c1, r0-r1.
        ; prog8c 12.3.4 bug: "c0 = c / if c0 != 0" at the start of a sub tested the flags of the caller's last
        ; load (the row), not c. Written so the test needs a fresh load.
        c0 = c - 1
        if c == 0
            c0 = 0
        c1 = c + 1
        if c1 == video.MAP_W
            c1--
        r0 = r
        if r0 != 0
            r0--
        r1 = r + 1
        if r1 == video.MAP_H
            r1--
    }

    sub start(ubyte c, ubyte r) {
        if main.PROFILE
            prof.sub_begin()
        ubyte s = free_slot()
        col[s] = c
        row[s] = r
        timer[s] = FRAMES
        started++
        starts++
        live++
        core_x[s] = ((c as uword) << 4) + 8
        core_y[s] = (r << 4) + 8
        area_at(c, r)
        ubyte n = draw_area(c, r)
        ; shuffle, then stagger the countdowns of the stars that start one
        ubyte k
        ubyte j = n
        while j > 1 {
            k = stars.rand_below(j)
            j--
            ubyte tmp = caught_stars[k]
            caught_stars[k] = caught_stars[j]
            caught_stars[j] = tmp
        }
        ubyte extra = 0
        k = 0
        while k < n {
            if stars.caught(caught_stars[k], extra)
                extra += stars.STAGGER
            k++
        }
        if main.PROFILE
            prof.sub_end(0)
    }

    sub free_slot() -> ubyte {
        ; A free slot, or the oldest explosion (least time left), which is ended first.
        ubyte s
        ubyte oldest = 0
        for s in 0 to MAX - 1 {
            if timer[s] == 0
                return s
            if timer[s] < timer[oldest]
                oldest = s
        }
        finish(oldest)
        return oldest
    }

    sub finish(ubyte s) {
        ; The danger ends now; the tiles are restored from the queue (at once if it is full).
        timer[s] = 0
        live--
        if queued == QUEUE {
            restore(col[s], row[s])
            return
        }
        queue_col[queued] = col[s]
        queue_row[queued] = row[s]
        queued++
    }

    sub restore(ubyte c, ubyte r) {
        if main.PROFILE
            prof.sub_begin()
        area_at(c, r)
        restore_area()
        if main.PROFILE
            prof.sub_end(1)
    }

    asmsub draw_area(ubyte c @A, ubyte r @Y) clobbers(X, Y) -> ubyte @A {
        ; Explosion start, the tiles of the area c0-c1, r0-r1 (set by area_at) around centre tile (c, r): the art
        ; (stored tile by tile, row by row, 4 chars each), one more in cover, and the stars there listed in
        ; caught_stars. Returns how many stars. Assembly: 36 chars and 36 colors (frame time).
        %asm {{
_scr = P8ZP_SCRATCH_W1
_clr = P8ZP_SCRATCH_W2
            .section BSS
_c          .byte ?
_r          .byte ?
_tr         .byte ?
_tc         .byte ?
_ch         .byte ?
_n          .byte ?
            .send BSS
            sta  _c
            sty  _r
            lda  #0
            sta  _n
            lda  p8b_explode.p8v_r0
            sta  _tr
_row
            ; first char of the row's first tile: art + ((tr - r + 1) * 3 + (c0 - c + 1)) * 4
            lda  _tr
            sec
            sbc  _r
            clc
            adc  #1                     ; 0-2
            sta  _ch
            asl  a
            clc
            adc  _ch                    ; * 3
            sta  _ch
            lda  p8b_explode.p8v_c0
            sec
            sbc  _c
            clc
            adc  #1                     ; 0-2
            clc
            adc  _ch
            asl  a
            asl  a
            clc
            adc  #p8b_explode.p8c_ART
            sta  _ch
            ; screen and color RAM pointers of tile (c0, tr)
            ldy  _tr
            lda  p8b_explode.p8v_c0
            sta  _tc
            asl  a
            clc
            adc  p8b_video.p8v_tile_row_addr_lsb,y
            sta  _scr
            sta  _clr
            lda  p8b_video.p8v_tile_row_addr_msb,y
            adc  #0
            sta  _scr+1
            clc
            adc  #>(p8b_video.p8c_COLOR_RAM - p8b_video.p8c_SCREEN)
            sta  _clr+1
_tile
            ldy  _tr
            lda  p8b_video.p8v_row_start,y
            clc
            adc  _tc
            tax                         ; tile index
            inc  p8b_explode.p8v_cover,x
            lda  p8b_video.p8v_tiles,x
            beq  +
            ldy  _n
            sec
            sbc  #1
            sta  p8b_explode.p8v_caught_stars,y
            inc  _n
+           lda  _ch
            ldy  #0
            sta  (_scr),y
            clc
            adc  #1
            iny
            sta  (_scr),y
            adc  #1
            ldy  #40
            sta  (_scr),y
            adc  #1
            iny
            sta  (_scr),y
            lda  #p8b_explode.p8c_COLOR
            ldy  #0
            sta  (_clr),y
            iny
            sta  (_clr),y
            ldy  #40
            sta  (_clr),y
            iny
            sta  (_clr),y
            ; next tile in the row
            lda  _tc
            cmp  p8b_explode.p8v_c1
            beq  _rowdone
            inc  _tc
            lda  _ch
            clc
            adc  #4
            sta  _ch
            lda  _scr
            clc
            adc  #2
            sta  _scr
            sta  _clr
            bcc  _tile
            inc  _scr+1
            inc  _clr+1
            jmp  _tile
_rowdone
            lda  _tr
            cmp  p8b_explode.p8v_r1
            beq  _done
            inc  _tr
            jmp  _row
_done
            lda  _n
            rts
        }}
    }

    asmsub restore_area() clobbers(A, X, Y) {
        ; Explosion end, the tiles of the area c0-c1, r0-r1 (set by area_at): one less in cover, and a tile with no
        ; explosion left over it is redrawn from the map. Assembly (frame time).
        %asm {{
            .section BSS
_tr         .byte ?
_tc         .byte ?
            .send BSS
            lda  p8b_explode.p8v_r0
            sta  _tr
_row
            lda  p8b_explode.p8v_c0
            sta  _tc
_tile
            ldy  _tr
            lda  p8b_video.p8v_row_start,y
            clc
            adc  _tc
            tax
            dec  p8b_explode.p8v_cover,x
            bne  +
            lda  _tc
            ldy  _tr
            jsr  p8b_video.p8s_draw_tile
+           lda  _tc
            cmp  p8b_explode.p8v_c1
            beq  _rowdone
            inc  _tc
            jmp  _tile
_rowdone
            lda  _tr
            cmp  p8b_explode.p8v_r1
            beq  _done
            inc  _tr
            jmp  _row
_done
            rts
        }}
    }

    sub update() {
        ubyte s
        for s in 0 to MAX - 1 {
            if timer[s] != 0 {
                timer[s]--
                if timer[s] == 0
                    finish(s)
            }
        }
        if queued != 0 {
            restore(queue_col[0], queue_row[0])
            queued--
            ubyte k = 0
            while k < queued {
                queue_col[k] = queue_col[k + 1]
                queue_row[k] = queue_row[k + 1]
                k++
            }
        }
        starts = 0
    }

    sub check_player() {
        ; The player's centre in a running explosion's core. Not while dying or safe after reappearing.
        if live == 0 or not player.hurtable()
            return
        obj_x = player.x + player.BOX / 2
        obj_y = player.y + player.BOX / 2
        ubyte s
        for s in 0 to MAX - 1 {
            if timer[s] != 0 and hits(s) {
                player.hurt()
                return
            }
        }
    }

    asmsub hits(ubyte s @Y) clobbers(A) -> bool @Pc {
        ; Carry set when (obj_x, obj_y) is within REACH of explosion s's centre: dx, dy are the distances along
        ; each axis, and longer + shorter / 2 < REACH (an octagon close to a circle). Assembly: called for every
        ; hostile and running explosion each frame.
        %asm {{
            .section BSS
_ax         .byte ?
_ay         .byte ?
            .send BSS
            ; dx = |obj_x - core_x|, a miss when 256 or more
            sec
            lda  p8b_explode.p8v_obj_x
            sbc  p8b_explode.p8v_core_x_lsb,y
            sta  _ax
            lda  p8b_explode.p8v_obj_x+1
            sbc  p8b_explode.p8v_core_x_msb,y
            beq  _xok
            cmp  #$ff
            bne  _miss
            lda  _ax
            beq  _miss                  ; -256
            eor  #$ff
            clc
            adc  #1
            sta  _ax
_xok
            lda  _ax
            cmp  #p8b_explode.p8c_REACH
            bcs  _miss
            ; dy = |obj_y - core_y|
            lda  p8b_explode.p8v_obj_y
            sec
            sbc  p8b_explode.p8v_core_y,y
            bcs  +
            eor  #$ff
            adc  #1                     ; carry is clear: negate
+           cmp  #p8b_explode.p8c_REACH
            bcs  _miss
            sta  _ay
            ; longer + shorter / 2
            cmp  _ax
            bcc  _xlonger
            lda  _ax
            lsr  a
            clc
            adc  _ay
            jmp  _cmp
_xlonger
            lsr  a                      ; A = dy, the shorter
            clc
            adc  _ax
_cmp
            cmp  #p8b_explode.p8c_REACH
            bcs  _miss
            sec
            rts
_miss
            clc
            rts
        }}
    }
}
