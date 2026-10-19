; Frame-time profiler for self-tests (main.PROFILE). CIA 2 timer A counts CPU cycles; the play loop marks the
; end of each part of the frame. The worst frame's breakdown, each part's maximum and the maxima of a few
; routines (sub_begin/sub_end) are shown on char rows 21-24. Costs about 50 cycles per mark.

prof {
    const ubyte PARTS = 10
    const ubyte SUBS = 4                ; 0 explode.start, 1 explode.restore, 2 score.add_type, 3 explode.step

    uword last                          ; timer value at the last mark
    uword[PARTS] cur                    ; this frame's cycles per part
    uword[PARTS] worst_part             ; breakdown of the worst frame
    uword[PARTS] max_part               ; each part's maximum over the run
    uword worst_total
    uword worst_frame
    ubyte worst_live                    ; explosions running in the worst frame
    ubyte worst_busy                    ; stars in a countdown started by an explosion
    ubyte worst_used                    ; hostile slots in use
    uword frames
    uword sub_start
    uword[SUBS] sub_max
    bool dirty

    sub init() {
        c64.CIA2TAL = $FF
        c64.CIA2TAH = $FF
        c64.CIA2CRA = %00010001         ; force load, start, continuous, count CPU cycles
    }

    asmsub now() clobbers(X) -> uword @AY {
        ; The timer (counts down), read again if the high byte changed between the two reads.
        %asm {{
-           ldy  c64.CIA2TAH
            lda  c64.CIA2TAL
            ldx  c64.CIA2TAH
            stx  P8ZP_SCRATCH_B1
            cpy  P8ZP_SCRATCH_B1
            bne  -
            rts
        }}
    }

    sub start() {
        last = now()
    }

    sub mark(ubyte k) {
        uword t = now()
        cur[k] = last - t
        last = t
    }

    sub sub_begin() {
        sub_start = now()
    }

    sub sub_end(ubyte k) {
        uword d = sub_start - now()
        if d > sub_max[k] {
            sub_max[k] = d
            dirty = true
        }
    }

    sub end_frame() {
        ; After the last mark: totals and maxima. The first frames are skipped (setup).
        frames++
        if frames < 3
            return
        uword total = 0
        ubyte k
        for k in 0 to PARTS - 1 {
            total += cur[k]
            if cur[k] > max_part[k] {
                max_part[k] = cur[k]
                dirty = true
            }
        }
        if total > worst_total {
            worst_total = total
            worst_frame = frames
            for k in 0 to PARTS - 1
                worst_part[k] = cur[k]
            worst_live = explode.live
            worst_busy = stars.blast_countdowns
            worst_used = hostiles.used
            dirty = true
        }
        if frames & 15 == 0 {
            dirty = false
            show()                      ; every 16 frames: stars and explosions in rows 21-24 draw over it
        }
    }

    sub show() {
        ; row 21: worst frame parts 0-7 | row 22: parts 8-9, total, frame, live, blast countdowns, hostiles |
        ; row 23: maxima of parts 0-7 | row 24: maxima of parts 8-9, then explode.start, restore, score.add, step
        sys.memset(video.row_addr(21), 160, video.CHAR_SPACE)
        sys.memset(video.row_addr(21) + video.COLOR_RAM - video.SCREEN, 160, 1)
        ubyte k
        for k in 0 to 7 {
            word_at(21, k * 5, worst_part[k])
            word_at(23, k * 5, max_part[k])
        }
        word_at(22, 0, worst_part[8])
        word_at(22, 5, worst_part[9])
        word_at(22, 10, worst_total)
        word_at(22, 15, worst_frame)
        digit_at(22, 20, worst_live)
        digit_at(22, 22, worst_busy >> 4)
        digit_at(22, 23, worst_busy & 15)
        digit_at(22, 25, worst_used)
        word_at(24, 0, max_part[8])
        word_at(24, 5, max_part[9])
        for k in 0 to SUBS - 1
            word_at(24, 10 + k * 5, sub_max[k])
    }

    sub word_at(ubyte row, ubyte col, uword value) {
        digit_at(row, col, msb(value) >> 4)
        digit_at(row, col + 1, msb(value) & 15)
        digit_at(row, col + 2, lsb(value) >> 4)
        digit_at(row, col + 3, lsb(value) & 15)
    }

    sub digit_at(ubyte row, ubyte col, ubyte n) {
        ; screen codes: '0'-'9' = 48-57, 'a'-'f' = 1-6
        @(video.row_addr(row) + col) = if n < 10 n + 48 else n - 9
    }
}
