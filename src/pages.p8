; Attract pages: HOW TO PLAY and SCORING, shown after the title (main.attract). The game's multicolor mode, so
; tiles and sprites look as in play; text in hi-res cells from the HUD font. All page text is in the tables
; below. Graphics are centred on pixel column 32, text starts at column 9. Adapted from Smashy Smashy.

%import video
%import input
%import score
%import player
%import hostiles
%import quasar

pages {
    ; [TUNE] frames each page is shown
    const uword HOW_FRAMES = 500        ; 10 s
    const uword SCORING_FRAMES = 600    ; 12 s
    const ubyte HEAD_COLOR = 7          ; page titles, yellow
    const ubyte TEXT_COLOR = 1
    const ubyte TEXT_COL = 9
    const uword SPR_X = 22              ; sprites' art centre (frame pixel 10) on pixel column 32

    ; ---- HOW TO PLAY: text lines (char row, column, text) ----
    ubyte[] how_row = [1, 3, 4, 6, 7, 11, 12, 16, 17, 19, 20, 23]
    ubyte[] how_col = [14, TEXT_COL, TEXT_COL, TEXT_COL, TEXT_COL, TEXT_COL, TEXT_COL, TEXT_COL, TEXT_COL,
                       TEXT_COL, TEXT_COL, 0]
    uword[] how_text = [
        sc:"how to play",
        sc:"move with the stick",
        sc:"fire to boost",
        sc:"ram stars to make them go",
        sc:"supernova: 3 bumps or 1 boost",
        sc:"hit stars swell, then explode",
        sc:"get clear before they blow",
        sc:"hurl hostiles with a boost",
        sc:"don't let them touch you",
        sc:"grab a quasar for 8 seconds",
        sc:"of invincibility",
        sc:"clear all stars to reach the next galaxy"
    ]
    ; sprites: player rows 3-4, hostile rows 16-17, quasar rows 19-20 (art centred on the line pair)
    const ubyte HOW_PLAYER_Y = 3 * 8 - 10
    const ubyte HOW_HOSTILE_Y = 16 * 8 - 10
    const ubyte HOW_QUASAR_Y = 19 * 8 - 10

    ; ---- SCORING ----
    ubyte[] score_row = [1, 4, 5, 8, 12, 15, 18]
    ubyte[] score_col = [16, TEXT_COL, TEXT_COL, TEXT_COL, TEXT_COL, TEXT_COL, TEXT_COL]
    uword[] score_text = [
        sc:"scoring",
        sc:"supernova",
        sc:"and multiplier +1",
        sc:"hostile chain",
        sc:"time bonus 100 per second",
        sc:"all points x multiplier",
        sc:"extra life every"
    ]
    const ubyte SCORE_HOSTILE_Y = 8 * 8 - 10
    const ubyte ICON_COL = 4

    sub how_to_play() -> bool {
        ; Show HOW TO PLAY for HOW_FRAMES frames. True if fire was pressed.
        start_page()
        ubyte i
        for i in 0 to len(how_row) - 1
            video.message(how_row[i], how_col[i], how_text[i], if i == 0 HEAD_COLOR else TEXT_COLOR)
        put_tile(6, 3, video.star_char[1], video.star_color[1])
        put_tile(11, 0, assets.TILE_SWELL_0_TL, assets.TILE_SWELL_0_COLOR | video.MC)
        ; the explosion's burst frame, 3 x 3 tiles at char rows 9-14, columns 2-7
        ubyte ty
        ubyte tx
        ubyte ch = assets.TILE_EXPLODE_1_TL
        for ty in 0 to 2 {
            for tx in 0 to 2 {
                put_tile(9 + ty * 2, 2 + tx * 2, ch, assets.TILE_EXPLODE_1_COLOR | video.MC)
                ch += 4
            }
        }
        video.set_sprite(0, assets.SPR_PLAYER_0, player.COLOR, SPR_X, HOW_PLAYER_Y)
        video.set_sprite(1, assets.SPR_HOSTILE_0, hostiles.COLOR, SPR_X, HOW_HOSTILE_Y)
        video.set_sprite(7, assets.SPR_QUASAR_0, quasar.COLOR, SPR_X, HOW_QUASAR_Y)
        return wait(HOW_FRAMES)
    }

    sub scoring() -> bool {
        ; Show SCORING for SCORING_FRAMES frames. True if fire was pressed. The values come from the score
        ; tables and constants, so they stay right after tuning.
        start_page()
        ubyte i
        for i in 0 to len(score_row) - 1
            video.message(score_row[i], score_col[i], score_text[i], if i == 0 HEAD_COLOR else TEXT_COLOR)
        put_tile(4, 3, video.star_char[5], video.star_color[5])
        put_value(4, TEXT_COL + 10, score.base_mid[score.T_SUPERNOVA], score.base_lo[score.T_SUPERNOVA])
        ; the hostile chain steps on one line
        ubyte col = TEXT_COL
        for i in 1 to score.CHAIN_STEPS
            col += put_value(9, col, score.base_mid[i], score.base_lo[i]) + 1
        put_char(12, ICON_COL, assets.CHAR_TIME, assets.CHAR_TIME_COLOR)
        put_char(15, ICON_COL, assets.CHAR_MULT, assets.CHAR_MULT_COLOR)
        put_char(18, ICON_COL, assets.CHAR_LIVES, assets.CHAR_LIVES_COLOR)
        put_value(18, TEXT_COL + 17, msb(score.EXTRA_LIFE_EVERY), lsb(score.EXTRA_LIFE_EVERY))
        video.set_sprite(1, assets.SPR_HOSTILE_0, hostiles.COLOR, SPR_X, SCORE_HOSTILE_Y)
        return wait(SCORING_FRAMES)
    }

    sub start_page() {
        ; Empty screen in the game's multicolor mode, switched in the border.
        video.hide_sprites()
        video.wait_frame()
        video.clear_screen()
        video.game_mode()
    }

    sub wait(uword frames) -> bool {
        ; Wait the given frames or until fire (true), spinning the page's sprites; then hide them.
        bool fire = false
        ubyte spin = 0
        ubyte frame = 0
        ubyte q_delay = 0
        ubyte q_frame = 0
        repeat frames {
            video.wait_frame()
            input.read()
            if input.pressed & input.FIRE != 0 {
                fire = true
                break
            }
            spin++
            if spin == player.SPIN_DELAY {
                spin = 0
                frame++
                if frame == player.SPIN_FRAMES
                    frame = 0
                video.spr_ptr[0] = assets.SPR_PLAYER_0 + frame
                video.spr_ptr[1] = assets.SPR_HOSTILE_0 + frame
            }
            q_delay++
            if q_delay == quasar.ANIM_DELAY {
                q_delay = 0
                q_frame = (q_frame + 1) & (quasar.ANIM_FRAMES - 1)
                video.spr_ptr[7] = assets.SPR_QUASAR_0 + q_frame
            }
        }
        video.hide_sprites()
        return fire
    }

    sub put_tile(ubyte row, ubyte col, ubyte ch, ubyte color) {
        ; A 2x2-char tile (chars ch to ch + 3: TL, TR, BL, BR) at any char position.
        ^^ubyte @zp scr = video.row_addr(row) + col
        scr[0] = ch
        scr[1] = ch + 1
        scr[40] = ch + 2
        scr[41] = ch + 3
        scr += video.COLOR_RAM - video.SCREEN
        scr[0] = color
        scr[1] = color
        scr[40] = color
        scr[41] = color
    }

    sub put_char(ubyte row, ubyte col, ubyte ch, ubyte color) {
        uword a = video.row_addr(row) + col
        @(a) = ch
        @(a + video.COLOR_RAM - video.SCREEN) = color
    }

    sub put_value(ubyte row, ubyte col, ubyte bcd_mid, ubyte bcd_lo) -> ubyte {
        ; Points given in BCD hundreds, without leading zeros, in the text color. Returns the width.
        uword a = video.row_addr(row) + col
        ubyte n = video.put_hundreds(a, bcd_mid, bcd_lo)
        sys.memset(a + video.COLOR_RAM - video.SCREEN, n, TEXT_COLOR)
        return n
    }
}
