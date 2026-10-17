; Stationary stars (spec sections 4, 6 and 10). Phase 1: random placement and background specks only.

%import math
%import video

stars {
    const ubyte MAX = 45
    ; tiles kept free around the player's start (spec section 10)
    const ubyte FREE_COL = 8            ; columns 8-11
    const ubyte FREE_ROW = 4            ; rows 4-7
    const ubyte SPECK_ONE_IN = 4        ; about one empty tile in four has a speck [TUNE]

    ubyte[MAX] col
    ubyte[MAX] row
    ubyte[MAX] kind
    ubyte count

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

    sub place(ubyte n) {
        ; n stars on random free tiles outside the start area, each with a random kind; then the specks.
        sys.memset(&video.tiles, len(video.tiles), 0)
        count = n
        ubyte i
        ubyte c
        ubyte r
        for i in 0 to n - 1 {
            do {
                c = rand_below(video.MAP_W)
                r = rand_below(video.MAP_H)
            } until video.tiles[video.row_start[r] + c] == 0 and not in_free_area(c, r)
            col[i] = c
            row[i] = r
            kind[i] = rand_below(video.STAR_KINDS)
            video.tiles[video.row_start[r] + c] = i + 1
        }
        place_specks()
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
}
