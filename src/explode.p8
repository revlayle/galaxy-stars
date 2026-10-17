; Explosions (spec section 6): the list, drawing over the 3x3 tiles, and the area checks.
; An explosion covers the 3x3 tiles around its centre tile, clipped to the playfield, for FRAMES frames.
; `cover` counts the explosions over each tile: star color changes skip covered tiles, and a tile is
; redrawn from the map only when its last explosion ends.
; Stars caught by one explosion explode one after another: in random order, each STAGGER frames after the last.

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
    bool[MAX] hit_player                ; this explosion already took a life (phase 3: no respawn yet)
    ubyte started                       ; explosions started (debug readout)
    ubyte[8] caught_stars               ; stars in the area of the explosion being started

    ; area of the current slot, set by area()
    ubyte c0
    ubyte c1
    ubyte r0
    ubyte r1

    sub clear() {
        sys.memset(&cover, len(cover), 0)
        sys.memset(&timer, MAX, 0)
    }

    sub area(ubyte s) {
        c0 = col[s]
        if c0 != 0
            c0--
        c1 = col[s] + 1
        if c1 == video.MAP_W
            c1--
        r0 = row[s]
        if r0 != 0
            r0--
        r1 = row[s] + 1
        if r1 == video.MAP_H
            r1--
    }

    sub start(ubyte c, ubyte r) {
        ubyte s = free_slot()
        col[s] = c
        row[s] = r
        timer[s] = FRAMES
        hit_player[s] = false
        started++
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
                    caught_stars[n] = t - 1     ; at most 8: the centre tile was cleared
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
        timer[s] = 0
        area(s)
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
    }

    sub check_player() {
        ; The area is whole tiles, so box overlap is the same as the player's tile range overlapping it.
        ubyte pc0 = lsb(player.x >> 4)
        ubyte pc1 = lsb((player.x + player.BOX - 1) >> 4)
        ubyte pr0 = player.y >> 4
        ubyte pr1 = (player.y + player.BOX - 1) >> 4
        ubyte s
        for s in 0 to MAX - 1 {
            if timer[s] != 0 and not hit_player[s] {
                area(s)
                if pc0 <= c1 and c0 <= pc1 and pr0 <= r1 and r0 <= pr1 {
                    hit_player[s] = true
                    score.lose_life()
                }
            }
        }
    }
}
