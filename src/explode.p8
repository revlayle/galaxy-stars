; Explosions (spec section 6): the list, drawing over the 3x3 tiles, and the area checks.
; An explosion covers the 3x3 tiles around its centre tile, clipped to the playfield, for FRAMES frames.
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
    &ubyte[video.MAP_W * video.MAP_H] cover = $C600

    ubyte[MAX] col
    ubyte[MAX] row
    ubyte[MAX] timer                    ; frames left, 0 = free slot
    ubyte started                       ; explosions started (debug readout)
    ubyte starts                        ; explosions started this frame
    ubyte live                          ; explosions running
    const ubyte QUEUE = 16
    ubyte[QUEUE] queue_col              ; centres of ended explosions whose tiles are still to restore
    ubyte[QUEUE] queue_row
    ubyte queued
    ubyte[9] caught_stars               ; stars in the area of the explosion being started (a hurl's centre tile can hold one)

    ; area of the current slot, set by area()
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

    sub area(ubyte s) {
        area_at(col[s], row[s])
    }

    sub area_at(ubyte c, ubyte r) {
        ; The 3x3 tiles around tile (c, r), clipped to the playfield, in c0-c1, r0-r1.
        c0 = c
        if c0 != 0
            c0--
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
        ubyte s = free_slot()
        col[s] = c
        row[s] = r
        timer[s] = FRAMES
        started++
        starts++
        live++
        area(s)
        ubyte n = 0
        ubyte tr
        ubyte tc
        for tr in r0 to r1 {
            for tc in c0 to c1 {
                ubyte idx = video.row_start[tr] + tc
                cover[idx]++
                ; the art is stored tile by tile, row by row, 4 chars each
                ubyte part = ((tr - r + 1) * 3 + tc - c + 1) << 2
                video.draw_quad(tc, tr, assets.TILE_EXPLODE_0_TL + part, COLOR)
                ubyte t = video.tiles[idx]
                if t != 0 {
                    caught_stars[n] = t - 1
                    n++
                }
            }
        }
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
        area_at(c, r)
        ubyte tr
        ubyte tc
        for tr in r0 to r1 {
            for tc in c0 to c1 {
                ubyte idx = video.row_start[tr] + tc
                cover[idx]--
                if cover[idx] == 0
                    video.draw_tile(tc, tr)
            }
        }
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
        ; Not while the player is dying or safe after reappearing.
        if live == 0 or not player.hurtable()
            return
        ; The area is whole tiles, so box overlap is the same as the player's tile range overlapping it.
        ubyte pc0 = lsb(player.x >> 4)
        ubyte pc1 = lsb((player.x + player.BOX - 1) >> 4)
        ubyte pr0 = player.y >> 4
        ubyte pr1 = (player.y + player.BOX - 1) >> 4
        ubyte s
        for s in 0 to MAX - 1 {
            if timer[s] != 0 {
                area(s)
                if pc0 <= c1 and c0 <= pc1 and pr0 <= r1 and r0 <= pr1 {
                    player.hurt()
                    return
                }
            }
        }
    }
}
