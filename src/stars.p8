; Stationary stars (spec sections 4, 6 and 10): placement, background specks, player hits, countdowns.

%import math
%import video
%import player
%import explode
%import score

stars {
    const ubyte MAX = 45
    ; tiles kept free around the player's start (spec section 10)
    const ubyte FREE_COL = 8            ; columns 8-11
    const ubyte FREE_ROW = 4            ; rows 4-7
    const ubyte SPECK_ONE_IN = 4        ; about one empty tile in four has a speck [TUNE]

    ; states (spec section 4); WARNING is used from phase 4
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
    ; [art phase] hit feedback colors, indexed by the star's own color: hits 1 and 2.
    ; Mostly yellow then white; yellow and white stars use white/yellow then cyan.
    ubyte[8] hit1_color = [7, 7, 7, 7, 7, 7, 7, 1]
    ubyte[8] hit2_color = [1, 3, 1, 1, 1, 1, 1, 3]
    ; countdown flash: white and black (the star's glow stays) [art phase]
    const ubyte FLASH_ON = 1
    const ubyte FLASH_OFF = 0

    ubyte[MAX] col
    ubyte[MAX] row
    ubyte[MAX] kind
    ubyte[MAX] state
    ubyte[MAX] hits
    ubyte[MAX] timer
    ubyte[MAX] no_hit                   ; frames before this star can count a hit again
    ubyte[MAX] shown                    ; color RAM value it is drawn with (MC bit included)
    ubyte count
    ubyte left                          ; stars not destroyed yet (spec section 4; hostiles add in phase 4)

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
        ; min(45, 15 + 2 * (g - 1)) stars
        if g >= 16
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
        video.tiles[video.row_start[r] + c] = i + 1
        count++
        left++
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
        if no_hit[i] != 0
            return
        no_hit[i] = NO_HIT_FRAMES
        if state[i] != COUNTDOWN {
            if player.boost_left != 0
                hit(i, BOOST_HITS)
            else
                hit(i, 1)
        }
        player.bounce(dx, dy)
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

    sub caught(ubyte i, ubyte extra) -> bool {
        ; The star's tile is in an explosion: straight to a full countdown plus `extra` frames, unless one
        ; is running. Returns true when a countdown started.
        if state[i] != IDLE and state[i] != WARNING
            return false
        start_countdown(i)
        timer[i] += extra
        return true
    }

    sub start_countdown(ubyte i) {
        state[i] = COUNTDOWN
        hits[i] = HITS_TO_NOVA
        timer[i] = COUNTDOWN_FRAMES
        set_color(i, FLASH_ON)
    }

    sub set_color(ubyte i, ubyte co) {
        ; Recolors the star's tile, unless an explosion is drawn over it (draw_tile uses `shown` later).
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

    sub update() {
        ; Once per frame: supernovas whose countdown ended, then hit lockouts, countdown timers and flashing.
        ; Two passes, so a countdown started by an explosion in the first pass also counts this frame:
        ; every countdown lasts COUNTDOWN_FRAMES frames, including the frame it started.
        ubyte i = 0
        while i < count {
            if state[i] == COUNTDOWN and timer[i] == 0
                supernova(i)
            i++
        }
        i = 0
        while i < count {
            if no_hit[i] != 0
                no_hit[i]--
            if state[i] == COUNTDOWN {
                timer[i]--
                ubyte phase = timer[i] >> 3
                if timer[i] <= FAST_FLASH
                    phase = timer[i] >> 1
                if phase & 1 == 0
                    set_color(i, FLASH_ON)
                else
                    set_color(i, FLASH_OFF)
            }
            i++
        }
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
    }
}
