; Stationary stars (spec sections 4, 6 and 10): placement, background specks, player hits, countdowns.

%import math
%import video
%import player
%import explode
%import score
%import hostiles
%import quasar

stars {
    const ubyte MAX = 55                ; [TUNE] stars at most (designer, 2026-10-18: was 45)
    ; tiles kept free around the player's start (spec section 10)
    const ubyte FREE_COL = 8            ; columns 8-11
    const ubyte FREE_ROW = 4            ; rows 4-7
    const ubyte SPECK_ONE_IN = 4        ; about one empty tile in four has a speck [TUNE]

    ; states (spec section 4)
    const ubyte IDLE = 0
    const ubyte WARNING = 1
    const ubyte COUNTDOWN = 2
    const ubyte GONE = 3

    const ubyte HITS_TO_NOVA = 3
    const ubyte BOOST_HITS = 3
    const ubyte COUNTDOWN_FRAMES = 100  ; 2 s
    const ubyte FAST_FLASH = 25         ; [TUNE] last half second flashes faster
    const ubyte NO_HIT_FRAMES = 10      ; [TUNE] a star counts one hit per contact
    const ubyte STAGGER = 6             ; [TUNE] extra countdown frames per further star caught by one explosion
    ; Hit feedback (spec section 12): the star's own color only, indexed by its own color: hits 1 and 2.
    ; Mostly yellow then white; yellow and white stars use white/yellow then cyan.
    ubyte[8] hit1_color = [7, 7, 7, 7, 7, 7, 7, 1]
    ubyte[8] hit2_color = [1, 3, 1, 1, 1, 1, 1, 3]
    ; Countdown: every kind turns into the shared swelling star, alternating its two frames (big and white,
    ; small and yellow) every 8 frames; in the last half second the big one flashes white and yellow every 2 frames
    ; (colors only: frame time, many stars can be in their last half second at once).
    const ubyte SWELL_BIG = assets.TILE_SWELL_1_TL
    const ubyte SWELL_BIG_COLOR = 1
    const ubyte SWELL_SMALL = assets.TILE_SWELL_0_TL
    const ubyte SWELL_SMALL_COLOR = 7
    ; turning hostile (spec section 7): flashes red for 1 s, alternating with its own color every 4 frames
    const ubyte WARNING_FRAMES = 50
    const ubyte WARNING_COLOR = 2

    ubyte[MAX] col
    ubyte[MAX] row
    ubyte[MAX] kind
    ubyte[MAX] state
    ubyte[MAX] hits
    ubyte[MAX] timer
    ubyte[MAX] no_hit                   ; frames before this star can count a hit again
    ubyte[MAX] shown                    ; color RAM value it is drawn with (MC bit included)
    ubyte[MAX] shown_char               ; top-left char it is drawn with (its kind, or the swelling star)
    bool[MAX] from_blast                ; COUNTDOWN started by an explosion (keeps the hostile chain alive)
    ubyte count
    ubyte left                          ; stars not destroyed yet: stationary stars plus active hostiles
    ubyte warnings                      ; stars in WARNING
    ubyte blast_countdowns              ; stars in a COUNTDOWN started by an explosion, counted by update()
    bool novas_due                      ; a countdown reached 0: update() makes it go supernova next frame
    ubyte[MAX] @shared pick_far         ; pick_hostile() candidates, filled by scan_idle()
    ubyte[MAX] @shared pick_any
    ubyte @shared n_far
    ubyte @shared n_any
    ubyte[MAX] reveal_order             ; galaxy start: stars in the order they appear
    ubyte revealed
    ubyte stops                         ; knockbacks stopped by a second star (debug readout)

    sub seed() {
        cx16.r0 = mkword(c64.RASTER, c64.CIA1TAH)
        math.rndseed(mkword(c64.CIA1TAL, c64.RASTER), cx16.r0)
    }

    sub rand_below(ubyte n) -> ubyte {
        ; Random 0 to n-1 (n >= 1). Masks math.rnd() and retries out-of-range values: under 2 tries on
        ; average, and much faster than math.randrange(), which does a 16-bit multiply.
        ubyte mask = 255
        if n <= 2
            mask = 1
        else if n <= 4
            mask = 3
        else if n <= 8
            mask = 7
        else if n <= 16
            mask = 15
        else if n <= 32
            mask = 31
        else if n <= 64
            mask = 63
        else if n <= 128
            mask = 127
        ubyte r
        do {
            r = math.rnd() & mask
        } until r < n
        return r
    }

    sub for_galaxy(ubyte g) -> ubyte {
        ; min(55, 15 + 2 * (g - 1)) stars: 55 from galaxy 21
        if g >= 21
            return MAX
        return 13 + (g << 1)
    }

    sub place(ubyte n) {
        ; n stars on random free tiles outside the start area, each with a random kind; then the specks.
        clear()
        ubyte c
        ubyte r
        repeat n {
            do {
                c = rand_below(video.MAP_W)
                r = rand_below(video.MAP_H)
            } until video.tiles[video.row_start[r] + c] == 0 and not in_free_area(c, r)
            add(c, r, rand_below(video.STAR_KINDS))
        }
        place_specks()
    }

    sub clear() {
        sys.memset(&video.tiles, len(video.tiles), 0)
        count = 0
        left = 0
        warnings = 0
        blast_countdowns = 0
        novas_due = false
    }

    sub add(ubyte c, ubyte r, ubyte k) {
        ; One star on a free tile (placement and self-tests).
        ubyte i = count
        col[i] = c
        row[i] = r
        kind[i] = k
        state[i] = IDLE
        hits[i] = 0
        timer[i] = 0
        no_hit[i] = 0
        shown[i] = video.star_color[k]
        shown_char[i] = video.star_char[k]
        video.tiles[video.row_start[r] + c] = i + 1
        count++
        left++
    }

    sub hide_for_reveal() {
        ; Galaxy start: take the placed stars off the map (the specks stay) and shuffle the order they come back.
        sys.memset(&video.tiles, len(video.tiles), 0)
        ubyte i = 0
        while i < count {
            reveal_order[i] = i
            i++
        }
        ubyte j = count
        while j > 1 {
            i = rand_below(j)
            j--
            ubyte tmp = reveal_order[i]
            reveal_order[i] = reveal_order[j]
            reveal_order[j] = tmp
        }
        revealed = 0
    }

    sub reveal_next() {
        ; The next star back on the map and the screen (nothing when all are back).
        if revealed >= count
            return
        ubyte i = reveal_order[revealed]
        revealed++
        ubyte idx = video.row_start[row[i]]
        idx += col[i]                   ; two steps: see supernova()
        video.tiles[idx] = i + 1
        video.draw_tile(col[i], row[i])
    }

    sub in_free_area(ubyte c, ubyte r) -> bool {
        return c - FREE_COL < 4 and r - FREE_ROW < 4    ; unsigned wrap: below the start also counts as outside
    }

    sub place_specks() {
        ; Decoration only: specks live on the screen and in video.specks, not in the tile map.
        ubyte i
        for i in 0 to len(video.specks) - 1 {
            video.specks[i] = 0
            if video.tiles[i] == 0 and rand_below(SPECK_ONE_IN) == 0
                video.specks[i] = (rand_below(video.SPECK_KINDS) + 1) << 2 | rand_below(4)
        }
    }

    ; ---- hits, countdowns, explosions (spec section 6) ----

    sub player_contact() {
        ; Player box against the 12x12 boxes (tile pixels 2-13) of the stars in the tiles it overlaps.
        uword px = player.x
        ubyte py = player.y
        ubyte c0 = lsb(px >> 4)
        ubyte c1 = lsb((px + player.BOX - 1) >> 4)
        ubyte r0 = py >> 4
        ubyte r1 = (py + player.BOX - 1) >> 4
        ubyte r
        ubyte c
        for r in r0 to r1 {
            for c in c0 to c1 {
                ubyte t = video.tiles[video.row_start[r] + c]
                if t != 0 {
                    uword sx = ((c as uword) << 4) + 2
                    ubyte sy = (r << 4) + 2
                    if px <= sx + 11 and sx <= px + player.BOX - 1 and py <= sy + 11 and sy <= py + player.BOX - 1
                        touch(t - 1, (lsb(px) - lsb(sx)) as byte, (py - sy) as byte)
                }
            }
        }
    }

    sub touch(ubyte i, byte dx, byte dy) {
        ; dx, dy: player box minus star box (both corners); equal sizes but one, so close to centre minus centre.
        ; A different star touched during a knockback that started in an earlier frame stops the knockback there:
        ; no second bounce, so the player can't be trapped bouncing between two stars. The touch still counts.
        ; The invincible player passes through and the star explodes at once.
        if player.invincible != 0 {
            blow(i)
            return
        }
        if player.knock_left != 0 and player.knock_left < player.KNOCK_FRAMES and i != player.knock_star {
            player.knock_left = 0
            stops++
            if no_hit[i] == 0 {
                no_hit[i] = NO_HIT_FRAMES
                if state[i] != COUNTDOWN {
                    if player.boosted
                        hit(i, BOOST_HITS)
                    else
                        hit(i, 1)
                }
            }
            return
        }
        if no_hit[i] != 0
            return
        no_hit[i] = NO_HIT_FRAMES
        if state[i] != COUNTDOWN {
            if player.boosted
                hit(i, BOOST_HITS)
            else
                hit(i, 1)
        }
        player.bounce(dx, dy)
        player.knock_star = i
    }

    sub hit(ubyte i, ubyte n) {
        hits[i] += n
        if hits[i] >= HITS_TO_NOVA
            start_countdown(i)
        else if hits[i] == 1
            set_color(i, hit1_color[video.star_color[kind[i]] & 7])
        else
            set_color(i, hit2_color[video.star_color[kind[i]] & 7])
    }

    sub blow(ubyte i) {
        ; Touched by the invincible player: a supernova with no countdown. update() sets it off this frame, or
        ; the next when an explosion has already started this frame (frame time).
        if state[i] != COUNTDOWN
            start_countdown(i)
        timer[i] = 0
        novas_due = true
    }

    sub caught(ubyte i, ubyte extra) -> bool {
        ; The star's tile is in an explosion: straight to a full countdown plus `extra` frames, unless one
        ; is running. Returns true when a countdown started.
        if state[i] != IDLE and state[i] != WARNING
            return false
        start_countdown(i)
        timer[i] += extra
        from_blast[i] = true
        return true
    }

    sub start_countdown(ubyte i) {
        ; Also ends a warning: the star goes supernova instead of hostile.
        if state[i] == WARNING
            warnings--
        state[i] = COUNTDOWN
        from_blast[i] = false
        hits[i] = HITS_TO_NOVA
        timer[i] = COUNTDOWN_FRAMES
        set_look(i, SWELL_BIG, SWELL_BIG_COLOR)
    }

    sub set_color(ubyte i, ubyte co) {
        ; Recolors the star's tile (its chars stay), unless an explosion is drawn over it.
        co |= video.MC
        if shown[i] == co
            return
        shown[i] = co
        ubyte c = col[i]
        ubyte r = row[i]
        if explode.cover[video.row_start[r] + c] == 0 {
            ^^ubyte @zp p = video.tile_row_addr[r] + (c << 1) + (video.COLOR_RAM - video.SCREEN)
            p[0] = co
            p[1] = co
            p[40] = co
            p[41] = co
        }
    }

    sub set_look(ubyte i, ubyte ch, ubyte co) {
        ; Redraws the star's tile with chars ch.. and color co, unless an explosion is drawn over it (draw_tile
        ; uses `shown_char` and `shown` later). Nothing when both are unchanged.
        co |= video.MC
        if shown[i] == co and shown_char[i] == ch
            return
        shown[i] = co
        shown_char[i] = ch
        ubyte c = col[i]
        ubyte r = row[i]
        if explode.cover[video.row_start[r] + c] == 0 {
            ^^ubyte @zp p = video.tile_row_addr[r] + (c << 1)
            p[0] = ch
            p[1] = ch + 1
            p[40] = ch + 2
            p[41] = ch + 3
            p += video.COLOR_RAM - video.SCREEN
            p[0] = co
            p[1] = co
            p[40] = co
            p[41] = co
        }
    }

    sub update() {
        ; Once per frame: supernovas whose countdown ended last frame, then hit lockouts, warnings, countdown
        ; timers and flashing. Supernovas go first, so a countdown started by their explosion also counts this
        ; frame: every countdown lasts COUNTDOWN_FRAMES frames, including the frame it started.
        ubyte i
        ; At most one explosion start per frame here (frame time): a further supernova waits a frame.
        if novas_due {
            novas_due = false
            i = 0
            while i < count {
                if state[i] == COUNTDOWN and timer[i] == 0 {
                    if explode.starts != 0 {
                        novas_due = true
                        break
                    }
                    supernova(i)
                }
                i++
            }
        }
        i = 0
        blast_countdowns = 0
        repeat {
            i = next_busy(i)
            if i == 255
                break
            if state[i] == WARNING
                warning(i)
            else {
                if from_blast[i]
                    blast_countdowns++
                ubyte t = timer[i]
                if t != 0 {
                    t--
                    timer[i] = t
                    if t == 0
                        novas_due = true
                }
                if t <= FAST_FLASH {
                    ; last half second: the big swell, flashing by color
                    ubyte co = SWELL_BIG_COLOR
                    if (t >> 1) & 1 != 0
                        co = SWELL_SMALL_COLOR
                    if shown_char[i] != SWELL_BIG
                        set_look(i, SWELL_BIG, co)
                    else
                        set_color(i, co)
                } else if (t >> 3) & 1 == 0 {
                    ; a countdown star's color goes with its swell frame here, so the char tells if the look changes
                    if shown_char[i] != SWELL_BIG
                        set_look(i, SWELL_BIG, SWELL_BIG_COLOR)
                } else if shown_char[i] != SWELL_SMALL
                    set_look(i, SWELL_SMALL, SWELL_SMALL_COLOR)
            }
            i++
        }
    }

    asmsub next_busy(ubyte from @X) clobbers(X) -> ubyte @A {
        ; From star `from` on: counts down the hit lockouts (no_hit) and returns the first star in WARNING or
        ; COUNTDOWN (its lockout counted down too), or 255 when there is none. Assembly: it runs over every star
        ; each frame.
        %asm {{
-           cpx  p8b_stars.p8v_count
            bcs  _none
            lda  p8b_stars.p8v_no_hit,x
            beq  +
            dec  p8b_stars.p8v_no_hit,x
+           lda  p8b_stars.p8v_state,x
            cmp  #p8b_stars.p8c_WARNING
            beq  _found
            cmp  #p8b_stars.p8c_COUNTDOWN
            beq  _found
            inx
            bne  -
_none
            lda  #255
            rts
_found
            txa
            rts
        }}
    }

    sub start_warning(ubyte i) {
        state[i] = WARNING
        timer[i] = WARNING_FRAMES
        warnings++
        set_color(i, WARNING_COLOR)
    }

    sub warning(ubyte i) {
        ; Flashing, then the tile is cleared and a hostile star takes its place (`left` stays the same).
        timer[i]--
        if timer[i] == 0 {
            state[i] = GONE
            warnings--
            ubyte idx = video.row_start[row[i]]
            idx += col[i]
            video.tiles[idx] = 0
            if explode.cover[idx] == 0
                video.draw_tile(col[i], row[i])
            hostiles.appear(col[i], row[i])
        } else if (timer[i] >> 2) & 1 == 0
            set_color(i, WARNING_COLOR)
        else
            set_color(i, video.star_color[kind[i]])
    }

    sub pick_hostile() -> ubyte {
        ; A random IDLE star outside the 9x9 tiles around the player (the tile under the player's centre),
        ; else any IDLE star. 255 = none.
        scan_idle(lsb((player.x + 6) >> 4), (player.y + 6) >> 4)
        if n_far != 0
            return pick_far[rand_below(n_far)]
        if n_any != 0
            return pick_any[rand_below(n_any)]
        return 255
    }

    asmsub scan_idle(ubyte pc @A, ubyte pr @Y) clobbers(A, X, Y) {
        ; IDLE stars into pick_any (n_any), and those at least hostiles.FAR tiles from tile (pc, pr) in either
        ; direction into pick_far (n_far). Assembly: it runs over every star.
        %asm {{
_pc = P8ZP_SCRATCH_B1
_pr = P8ZP_SCRATCH_REG
            sta  _pc
            sty  _pr
            lda  #0
            sta  p8b_stars.p8v_n_far
            sta  p8b_stars.p8v_n_any
            ldx  #0
_loop
            cpx  p8b_stars.p8v_count
            bcs  _done
            lda  p8b_stars.p8v_state,x
            cmp  #p8b_stars.p8c_IDLE
            bne  _next
            txa
            ldy  p8b_stars.p8v_n_any
            sta  p8b_stars.p8v_pick_any,y
            inc  p8b_stars.p8v_n_any
            lda  p8b_stars.p8v_col,x
            sec
            sbc  _pc
            bcs  +
            eor  #255
            adc  #1                     ; carry is clear: negate
+           cmp  #p8b_hostiles.p8c_FAR
            bcs  _far
            lda  p8b_stars.p8v_row,x
            sec
            sbc  _pr
            bcs  +
            eor  #255
            adc  #1
+           cmp  #p8b_hostiles.p8c_FAR
            bcc  _next
_far
            txa
            ldy  p8b_stars.p8v_n_far
            sta  p8b_stars.p8v_pick_far,y
            inc  p8b_stars.p8v_n_far
_next
            inx
            jmp  _loop
_done
            rts
        }}
    }

    sub supernova(ubyte i) {
        state[i] = GONE
        left--
        ; Two steps: prog8c 12.3.4 gets row_start[row[i]] + col[i] wrong in one expression (loses col[i]).
        ubyte idx = video.row_start[row[i]]
        idx += col[i]
        video.tiles[idx] = 0
        score.supernova()
        explode.start(col[i], row[i])   ; draws over the tile; it is restored as empty space afterwards
        quasar.chance(col[i], row[i])
    }
}
