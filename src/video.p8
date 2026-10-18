; VIC setup (bank 3), charset and sprite upload, tile drawing, HUD, sprite shadows and the frame IRQ.
; Adapted from Smashy Smashy. Never use txt.* routines: they are hard-wired to the $0400 screen.

%import gen_assets

video {
    ; ---- colors ----
    const ubyte COLOR_BORDER = 0
    const ubyte COLOR_BG = 0            ; $D021, art symbol '.' in chars
    const ubyte COLOR_CHAR_MC1 = 11     ; $D022, art symbol '2' in chars (dark grey) [art phase]
    const ubyte COLOR_CHAR_MC2 = 12     ; $D023, art symbol '3' in chars (grey) [art phase]
    const ubyte COLOR_HUD = 1           ; hi-res text, must be 0-7
    const ubyte MC = 8                  ; color RAM bit 3: the cell is multicolor

    ; ---- memory (spec section 3) ----
    const uword SCREEN = $C000
    const uword SPRITE_PTRS = $C3F8
    const uword COLOR_RAM = $D800
    const uword CHARSET = $E000
    const uword SPRITE_DATA = $E800
    const ubyte HUD_FONT_CHARS = 64     ; ROM screen codes 0-63: @, A-Z, space, digits, punctuation
    const ubyte CHAR_SPACE = 32

    ; ---- tile map (spec section 4) ----
    const ubyte MAP_W = 20
    const ubyte MAP_H = 12
    &ubyte[MAP_W * MAP_H] tiles = $C400     ; 0 = empty, 1 + i = stationary star i
    &ubyte[MAP_W * MAP_H] specks = $C500    ; 0 = none, else (speck kind + 1) << 2 | char (0 TL, 1 TR, 2 BL, 3 BR)
    ubyte[MAP_H] row_start = [0, 20, 40, 60, 80, 100, 120, 140, 160, 180, 200, 220]
    ; screen address of the top-left char of tile column 0 in each tile row (char row 1 + 2*row)
    uword[MAP_H] tile_row_addr = [SCREEN + 40, SCREEN + 120, SCREEN + 200, SCREEN + 280,
                                  SCREEN + 360, SCREEN + 440, SCREEN + 520, SCREEN + 600,
                                  SCREEN + 680, SCREEN + 760, SCREEN + 840, SCREEN + 920]
    ubyte[4] quad_offset = [0, 1, 40, 41]

    ; star kind -> top-left char and color (the tiles star_0, star_1, ... in assets/tiles.txt)
    ubyte[] star_char = [assets.TILE_STAR_0_TL, assets.TILE_STAR_1_TL, assets.TILE_STAR_2_TL, assets.TILE_STAR_3_TL,
                         assets.TILE_STAR_4_TL, assets.TILE_STAR_5_TL, assets.TILE_STAR_6_TL, assets.TILE_STAR_7_TL]
    ubyte[len(star_char)] star_color = [assets.TILE_STAR_0_COLOR, assets.TILE_STAR_1_COLOR,
                                        assets.TILE_STAR_2_COLOR, assets.TILE_STAR_3_COLOR,
                                        assets.TILE_STAR_4_COLOR, assets.TILE_STAR_5_COLOR,
                                        assets.TILE_STAR_6_COLOR, assets.TILE_STAR_7_COLOR]
    const ubyte STAR_KINDS = len(star_char)
    ubyte[] speck_char = [assets.CHAR_SPECK_0, assets.CHAR_SPECK_1, assets.CHAR_SPECK_2,
                          assets.CHAR_SPECK_3, assets.CHAR_SPECK_4]
    const ubyte SPECK_KINDS = len(speck_char)
    const ubyte SPECK_COLOR = assets.CHAR_SPECK_0_COLOR | MC

    sub init() {
        c64.SPENA = 0
        sys.memset(SCREEN, 1000, CHAR_SPACE)
        sys.memset(COLOR_RAM, 1000, COLOR_HUD)

        ; HUD font from the character ROM. With CHAREN=0 the ROM replaces I/O at $D000, so no IRQs meanwhile.
        sys.set_irqd()
        c64.banks(%010)
        sys.memcopy($D000, CHARSET, (HUD_FONT_CHARS as uword) * 8)
        c64.banks(%110)
        sys.clear_irqd()

        ; CPU writes to $E000-$FFFF reach the RAM under the KERNAL ROM
        sys.memcopy(&chars_bin, CHARSET + (assets.FIRST_CHAR as uword) * 8, (assets.CHAR_COUNT as uword) * 8)
        sys.memcopy(&sprites_bin, SPRITE_DATA, (assets.SPRITE_COUNT as uword) * 64)

        ubyte i
        for i in 0 to STAR_KINDS - 1
            star_color[i] |= MC

        ; VIC bank 3: $DD00 bits 0-1 = %00. Screen at +$0000, charset at +$2000.
        c64.CIA2DDRA |= %00000011
        c64.CIA2PRA &= %11111100
        c64.VMCSB = $08
        cbm.HIBASE = $C0

        c64.SCROLX |= %00010000         ; multicolor chars
        c64.SPMC = 0                    ; hi-res sprites
        c64.EXTCOL = COLOR_BORDER
        c64.BGCOL0 = COLOR_BG
        c64.BGCOL1 = COLOR_CHAR_MC1
        c64.BGCOL2 = COLOR_CHAR_MC2
    }

    sub draw_tile(ubyte col, ubyte row) {
        ubyte idx = row_start[row] + col
        ubyte t = tiles[idx]
        ^^ubyte @zp scr = tile_row_addr[row] + (col << 1)
        ubyte ch
        ubyte co
        if t != 0 {
            ch = star_char[stars.kind[t - 1]]
            co = stars.shown[t - 1]
            scr[0] = ch
            scr[1] = ch + 1
            scr[40] = ch + 2
            scr[41] = ch + 3
        } else {
            scr[0] = CHAR_SPACE
            scr[1] = CHAR_SPACE
            scr[40] = CHAR_SPACE
            scr[41] = CHAR_SPACE
            co = SPECK_COLOR
            ubyte s = specks[idx]
            if s != 0
                scr[quad_offset[s & 3]] = speck_char[(s >> 2) - 1]
        }
        scr += COLOR_RAM - SCREEN
        scr[0] = co
        scr[1] = co
        scr[40] = co
        scr[41] = co
    }

    sub draw_quad(ubyte col, ubyte row, ubyte ch, ubyte co) {
        ; Chars ch to ch+3 (TL, TR, BL, BR) in one color over a tile, without touching the tile map.
        ^^ubyte @zp scr = tile_row_addr[row] + (col << 1)
        scr[0] = ch
        scr[1] = ch + 1
        scr[40] = ch + 2
        scr[41] = ch + 3
        scr += COLOR_RAM - SCREEN
        scr[0] = co
        scr[1] = co
        scr[40] = co
        scr[41] = co
    }

    sub draw_playfield() {
        ubyte row
        ubyte col
        for row in 0 to MAP_H - 1 {
            for col in 0 to MAP_W - 1
                draw_tile(col, row)
        }
    }

    ; ---- HUD (char row 0, spec section 2) ----
    ;  SCORE 00000000          T60   x1   *3      (T, x and * are the icon chars)
    const ubyte HUD_SCORE_COL = 7       ; 8 digits
    const ubyte HUD_TIME_COL = 27       ; icon, then 2 digits
    const ubyte HUD_MULT_COL = 32       ; icon, then 1 digit
    const ubyte HUD_LIVES_COL = 36      ; icon, then 1 digit

    sub draw_hud() {
        ; Labels and icons. The values are drawn by the hud_* routines.
        sys.memset(SCREEN, 40, CHAR_SPACE)
        sys.memset(COLOR_RAM, 40, COLOR_HUD)
        hud_text(1, sc:"score")
        hud_icon(HUD_TIME_COL, assets.CHAR_TIME, assets.CHAR_TIME_COLOR)
        hud_icon(HUD_MULT_COL, assets.CHAR_MULT, assets.CHAR_MULT_COLOR)
        hud_icon(HUD_LIVES_COL, assets.CHAR_LIVES, assets.CHAR_LIVES_COLOR)
    }

    sub hud_text(ubyte col, str text) {
        ^^ubyte @zp scr = SCREEN + col
        ubyte i = 0
        while text[i] != 0 {
            scr[i] = text[i]
            i++
        }
    }

    sub hud_icon(ubyte col, ubyte ch, ubyte color) {
        @(SCREEN + col) = ch
        @(COLOR_RAM + col) = color
    }

    sub hud_score(ubyte bcd_hi, ubyte bcd_mid, ubyte bcd_lo) {
        ; Score in hundreds, 6 BCD digits, shown with a fixed "00": 8 digits.
        if main.DEBUG_HUD
            return                      ; the debug readouts use the HUD row
        put_bcd2(SCREEN + HUD_SCORE_COL, bcd_hi)
        put_bcd2(SCREEN + HUD_SCORE_COL + 2, bcd_mid)
        put_bcd2(SCREEN + HUD_SCORE_COL + 4, bcd_lo)
        put_bcd2(SCREEN + HUD_SCORE_COL + 6, 0)
    }

    sub hud_time(ubyte bcd) {
        if main.DEBUG_HUD
            return                      ; the debug readouts use the HUD row
        put_bcd2(SCREEN + HUD_TIME_COL + 1, bcd)
    }

    sub hud_mult(ubyte n) {
        if main.DEBUG_HUD
            return                      ; the debug readouts use the HUD row
        put_digit(SCREEN + HUD_MULT_COL + 1, n)
    }

    sub hud_lives(ubyte n) {
        if main.DEBUG_HUD
            return                      ; the debug readouts use the HUD row
        put_digit(SCREEN + HUD_LIVES_COL + 1, n)
    }

    sub put_bcd2(uword addr, ubyte bcd) {
        put_digit(addr, bcd >> 4)
        put_digit(addr + 1, bcd & 15)
    }

    sub put_digit(uword addr, ubyte n) {
        ; Only writes when the digit on screen differs.
        ubyte ch = '0' as ubyte + n
        if @(addr) != ch
            @(addr) = ch
    }

    ; ---- sprites and frame IRQ (spec section 1) ----
    ; Game code writes these shadows; the frame IRQ copies them to the VIC at the start of the next frame.
    const uword FRAME_IRQ_LINE = 251    ; first line of the bottom border (PAL)
    ubyte[8] spr_ptr
    ubyte[8] spr_col
    ubyte[8] spr_x
    ubyte[8] spr_y
    ubyte spr_msb
    ubyte spr_ena
    bool frame_ready
    ubyte frames                        ; counts frame IRQs

    sub start_frame_irq() {
        sys.set_rasterirq(&frame_irq, FRAME_IRQ_LINE)
    }

    sub frame_irq() -> bool {
        ; Runs in the IRQ: no virtual registers, nothing slow.
        ; Unrolled copy of the 8 sprites' pointer, color, x and y (lda/sta pairs, about 250 cycles).
        %asm {{
            .for _n := 0, _n < 8, _n += 1
            lda  p8b_video.p8v_spr_ptr+_n
            sta  p8b_video.p8c_SPRITE_PTRS+_n
            lda  p8b_video.p8v_spr_col+_n
            sta  c64.SPCOL+_n
            lda  p8b_video.p8v_spr_x+_n
            sta  c64.SPXY+_n*2
            lda  p8b_video.p8v_spr_y+_n
            sta  c64.SPXY+_n*2+1
            .endfor
        }}
        c64.MSIGX = spr_msb
        c64.SPENA = spr_ena
        frame_ready = true
        frames++
        return false                    ; no KERNAL IRQ: the game reads the keyboard matrix itself
    }

    sub wait_frame() {
        while not frame_ready {
        }
        frame_ready = false
    }

    ubyte[8] sprite_bit = [1, 2, 4, 8, 16, 32, 64, 128]

    sub set_sprite(ubyte n, ubyte frame, ubyte color, uword px, ubyte py) {
        ; Playfield coordinates of the sprite's top-left -> hardware position (spec section 2).
        ubyte bit = sprite_bit[n]
        spr_ptr[n] = frame
        spr_col[n] = color
        px += 24
        spr_x[n] = lsb(px)
        spr_y[n] = py + 50 + 8
        if msb(px) != 0
            spr_msb |= bit
        else
            spr_msb &= ~bit
        spr_ena |= bit
    }

    sub hide_sprite(ubyte n) {
        spr_ena &= ~sprite_bit[n]
    }

chars_bin:
    %asmbinary "build/chars.bin"
sprites_bin:
    %asmbinary "build/sprites.bin"
}
