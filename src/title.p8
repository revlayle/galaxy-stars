; Title and game-over screens (spec section 11).
; Title: GALAXY STARS, the player star spinning under it, PRESS FIRE blinking and the session high score, over
; faint background specks. Fire starts a game and seeds the RNG.

%import video
%import input
%import score
%import stars

title {
    const ubyte TITLE_ROW = 5
    const ubyte FIRE_ROW = 16
    const ubyte HIGH_ROW = 19
    const ubyte TITLE_COLOR = 7         ; yellow [art phase]
    const ubyte TEXT_COLOR = 1
    const ubyte BLINK_FRAMES = 25       ; PRESS FIRE on 25 frames, off 25
    const ubyte SPECKS = 40             ; [art phase] background specks
    ; the spinning star: playfield coordinates of the sprite's top-left (art centre on px 160, char row 10)
    const uword STAR_X = 150
    const ubyte STAR_Y = 62

    sub run() {
        ; Returns when fire is pressed, with the RNG seeded.
        video.clear_screen()
        video.hide_sprites()
        repeat SPECKS {
            ; anywhere but the text rows
            ubyte r
            do {
                r = stars.rand_below(25)
            } until r != TITLE_ROW and r != FIRE_ROW and r != HIGH_ROW
            uword a = video.row_addr(r) + stars.rand_below(40)
            @(a) = video.speck_char[stars.rand_below(video.SPECK_KINDS)]
            @(a + video.COLOR_RAM - video.SCREEN) = video.SPECK_COLOR
        }
        video.message(TITLE_ROW, 14, sc:"galaxy stars", TITLE_COLOR)
        video.message(HIGH_ROW, 10, sc:"high score", TEXT_COLOR)
        uword hs = video.row_addr(HIGH_ROW) + 21
        video.put_score(hs, score.high_hi, score.high_mid, score.high_lo)
        sys.memset(hs + video.COLOR_RAM - video.SCREEN, 8, TEXT_COLOR)
        main.test_stage(main.STAGE_TITLE)

        ubyte blink = 0
        ubyte frame = 0
        ubyte spin = 0
        repeat {
            video.wait_frame()
            input.read()
            if input.pressed & input.FIRE != 0
                break
            spin++
            if spin == player.SPIN_DELAY {
                spin = 0
                frame++
                if frame == player.SPIN_FRAMES
                    frame = 0
            }
            video.set_sprite(0, assets.SPR_PLAYER_0 + frame, player.COLOR, STAR_X, STAR_Y)
            if blink == 0
                video.message(FIRE_ROW, 15, sc:"press fire", TEXT_COLOR)
            else if blink == BLINK_FRAMES
                video.message(FIRE_ROW, 15, sc:"press fire", video.COLOR_BG)
            blink++
            if blink == BLINK_FRAMES * 2
                blink = 0
        }
        video.hide_sprites()
        stars.seed()
    }

    sub game_over() {
        ; GAME OVER and the high score over the frozen playfield; fire after 1 s returns to the title.
        score.update_high()
        video.message(10, 15, sc:"game over", TEXT_COLOR)
        video.message(13, 10, sc:"high score", TEXT_COLOR)
        uword hs = video.row_addr(13) + 21
        sys.memset(hs - 1, 1, video.CHAR_SPACE)
        video.put_score(hs, score.high_hi, score.high_mid, score.high_lo)
        sys.memset(hs - 1 + video.COLOR_RAM - video.SCREEN, 9, TEXT_COLOR)
        main.test_stage(main.STAGE_GAME_OVER)
        repeat 50 {
            video.wait_frame()
            input.read()
        }
        do {
            video.wait_frame()
            input.read()
        } until input.pressed & input.FIRE != 0
    }
}
