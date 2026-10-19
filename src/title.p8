; Title and game-over screens (spec section 11).
; Title: GALAXY STARS in big letters made of star chars. The stars fly in from off the screen (7 sprites, one
; star each) in random order and each becomes its logo char where it lands, with a short white sparkle. Then
; the logo twinkles (random chars flash white) and a color band rolls through it. The player star spins under
; the logo, PRESS FIRE blinks, the session high score below. Hi-res character mode, so the logo chars can use
; all 16 colors. Shown until fire (true) or for SHOW_FRAMES after the logo is built (false).

%import video
%import input
%import score
%import stars

title {
    ; [TUNE]
    const uword SHOW_FRAMES = 400       ; 8 s after the logo is built
    const ubyte FLY_FRAMES = 8          ; frames a star takes from off the screen to its place
    const ubyte FLIERS = 7              ; sprites 1-7 (sprite 0 is the player star)
    const ubyte SPARKLE_FRAMES = 2      ; a landed star flashes white this long
    const ubyte SWEEP_FRAMES = 3        ; the color band moves one step every 3 frames
    const ubyte TWINKLES = 3            ; chars flashing white at a time (at most)
    const ubyte TWINKLE_ON = 3          ; frames a twinkle stays white
    const ubyte TWINKLE_GAP = 16        ; then a random wait of 0-15 frames
    const ubyte FLASH_COLOR = 1         ; white
    ubyte[2] fly_color = [1, 7]         ; white and yellow fliers, alternating
    ; colors by (column + row - phase) & 15: yellow, with a band of orange, white and light blue rolling through
    ubyte[16] sweep = [7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 1, 14, 1, 8, 7]

    const ubyte FIRE_ROW = 19
    const ubyte FIRE_COL = 15
    const ubyte HIGH_ROW = 22
    const ubyte HIGH_COL = 10
    const ubyte TEXT_COLOR = 1
    const ubyte BLINK_FRAMES = 25       ; PRESS FIRE on 25 frames, off 25
    const ubyte SPECKS = 40
    ; the spinning star: playfield coordinates of the sprite's top-left (art centre on px 160, between the logo
    ; and PRESS FIRE)
    const uword STAR_X = 150
    const ubyte STAR_Y = 118

    ; ---- the logo ----
    ; Letter shapes, 3 x 5: '#' = a star char, '.' = empty, rows separated by spaces.
    str sh_g = ".## #.. #.# #.# .##"
    str sh_a = ".#. #.# ### #.# #.#"
    str sh_l = "#.. #.. #.. #.. ###"
    str sh_x = "#.# #.# .#. #.# #.#"
    str sh_y = "#.# #.# .#. .#. .#."
    str sh_s = ".## #.. .#. ..# ##."
    str sh_t = "### .#. .#. .#. .#."
    str sh_r = "##. #.# ##. #.# #.#"
    const ubyte LETTERS = 11
    uword[LETTERS] l_shape = [&sh_g, &sh_a, &sh_l, &sh_a, &sh_x, &sh_y,   &sh_s, &sh_t, &sh_a, &sh_r, &sh_s]
    ubyte[LETTERS] l_col = [8, 12, 16, 20, 24, 28,   10, 14, 18, 22, 26]    ; both words centred
    ubyte[LETTERS] l_row = [3, 3, 3, 3, 3, 3,   10, 10, 10, 10, 10]

    const ubyte MAX_CELLS = 128
    ubyte cells                         ; star chars in the logo (parsed once)
    uword[MAX_CELLS] cell_off           ; screen offset (row * 40 + column)
    ubyte[MAX_CELLS] cell_col
    ubyte[MAX_CELLS] cell_row
    ubyte[MAX_CELLS] cell_base          ; (column + row) & 15, for the color band
    ubyte[MAX_CELLS] order              ; landing order, shuffled every time

    ; flying stars, one per sprite 1-7
    ubyte[FLIERS] f_cell                ; target cell, 255 = idle
    ubyte[FLIERS] f_left                ; frames until it lands
    word[FLIERS] f_x                    ; hardware sprite position
    word[FLIERS] f_y
    word[FLIERS] f_dx                   ; step per frame
    word[FLIERS] f_dy
    ubyte[FLIERS] sp_cell               ; the cell this flier landed on last, flashing white
    ubyte[FLIERS] sp_left
    ubyte next_cell                     ; next index in order to launch
    ubyte landed

    ubyte[TWINKLES] tw_cell
    ubyte[TWINKLES] tw_on
    ubyte[TWINKLES] tw_wait
    ubyte phase                         ; color band position

    sub parse_logo() {
        ubyte k
        for k in 0 to LETTERS - 1 {
            uword s = l_shape[k]
            ubyte i = 0
            ubyte r = 0
            ubyte c = 0
            while @(s + i) != 0 {
                when @(s + i) {
                    ' ' -> {
                        r++
                        c = 0
                    }
                    '#' -> {
                        ubyte row = l_row[k] + r
                        ubyte col = l_col[k] + c
                        cell_off[cells] = (row as uword) * 40 + col
                        cell_col[cells] = col
                        cell_row[cells] = row
                        cell_base[cells] = (col + row) & 15
                        cells++
                        c++
                    }
                    else -> c++
                }
                i++
            }
        }
    }

    sub run() -> bool {
        ; Returns true when fire is pressed, false when the title's time is up.
        if cells == 0
            parse_logo()
        video.hide_sprites()
        video.wait_frame()
        video.clear_screen()
        video.title_mode()
        ubyte i
        uword a
        ; every logo char is on the screen from the start, black (unseen) until its star lands
        for i in 0 to cells - 1 {
            a = video.SCREEN + cell_off[i]
            @(a) = assets.CHAR_LOGO
            @(a + video.COLOR_RAM - video.SCREEN) = video.COLOR_BG
        }
        repeat SPECKS {
            ; on empty cells, but not the text rows
            ubyte r
            do {
                r = stars.rand_below(25)
            } until r != FIRE_ROW and r != HIGH_ROW
            a = video.row_addr(r) + stars.rand_below(40)
            if @(a) == video.CHAR_SPACE {
                @(a) = video.speck_char[stars.rand_below(video.SPECK_KINDS)]
                @(a + video.COLOR_RAM - video.SCREEN) = video.SPECK_COLOR
            }
        }
        video.message(HIGH_ROW, HIGH_COL, sc:"high score", TEXT_COLOR)
        uword hs = video.row_addr(HIGH_ROW) + HIGH_COL + 11
        video.put_score(hs, score.high_hi, score.high_mid, score.high_lo)
        sys.memset(hs + video.COLOR_RAM - video.SCREEN, 8, TEXT_COLOR)

        ; shuffle the landing order
        for i in 0 to cells - 1
            order[i] = i
        for i in cells - 1 downto 1 {
            ubyte j = stars.rand_below(i + 1)
            ubyte t = order[i]
            order[i] = order[j]
            order[j] = t
        }
        next_cell = 0
        landed = 0
        phase = 0
        for i in 0 to FLIERS - 1 {
            f_cell[i] = 255
            sp_left[i] = 0
        }
        for i in 0 to TWINKLES - 1 {
            tw_on[i] = 0
            tw_wait[i] = stars.rand_below(TWINKLE_GAP)
        }
        main.test_stage(main.STAGE_TITLE)

        bool built = false
        ubyte launch_t = 0              ; the fliers start one frame apart
        ubyte sweep_t = SWEEP_FRAMES
        uword shown = 0
        ubyte blink = 0
        ubyte frame = 0
        ubyte spin = 0
        bool fire = false
        repeat {
            video.wait_frame()
            input.read()
            if input.pressed & input.FIRE != 0 {
                fire = true
                break
            }
            if not built {
                for i in 0 to FLIERS - 1 {
                    if sp_left[i] != 0 {
                        sp_left[i]--
                        if sp_left[i] == 0
                            recolor(sp_cell[i])
                    }
                    if f_cell[i] != 255 {
                        f_left[i]--
                        if f_left[i] == 0 {
                            land(i)
                            launch(i)
                        } else {
                            f_x[i] += f_dx[i]
                            f_y[i] += f_dy[i]
                            put_flier(i)
                        }
                    }
                }
                if launch_t < FLIERS {
                    launch(launch_t)
                    launch_t++
                }
                if landed == cells {
                    built = true
                    for i in 0 to FLIERS - 1 {
                        if sp_left[i] != 0
                            built = false
                    }
                }
            } else {
                sweep_t--
                if sweep_t == 0 {
                    sweep_t = SWEEP_FRAMES
                    phase++
                    sweep_all()
                }
                twinkle()
                shown++
                if shown == SHOW_FRAMES
                    break
            }

            spin++
            if spin == player.SPIN_DELAY {
                spin = 0
                frame++
                if frame == player.SPIN_FRAMES
                    frame = 0
            }
            video.set_sprite(0, assets.SPR_PLAYER_0 + frame, player.COLOR, STAR_X, STAR_Y)
            if blink == 0
                video.message(FIRE_ROW, FIRE_COL, sc:"press fire", TEXT_COLOR)
            else if blink == BLINK_FRAMES
                video.message(FIRE_ROW, FIRE_COL, sc:"press fire", video.COLOR_BG)
            blink++
            if blink == BLINK_FRAMES * 2
                blink = 0
        }
        video.hide_sprites()
        return fire
    }

    sub recolor(ubyte c) {
        @(video.COLOR_RAM + cell_off[c]) = sweep[(cell_base[c] - phase) & 15]
    }

    asmsub sweep_all() clobbers(A, X, Y) {
        ; Recolor every logo char from the color band. Assembly: done before the beam reaches the logo.
        %asm {{
_p = P8ZP_SCRATCH_W1
            ldx  #0
-           lda  p8v_cell_off_lsb,x
            sta  _p
            lda  p8v_cell_off_msb,x
            clc
            adc  #>p8b_video.p8c_COLOR_RAM      ; COLOR_RAM is $D800: its low byte is 0
            sta  _p+1
            lda  p8v_cell_base,x
            sec
            sbc  p8v_phase
            and  #15
            tay
            lda  p8v_sweep,y
            ldy  #0
            sta  (_p),y
            inx
            cpx  p8v_cells
            bne  -
            rts
        }}
    }

    sub launch(ubyte n) {
        ; Send flier n to the next cell in the order, from a random point just off a screen edge (hidden by
        ; the border); idle and hidden when every cell has had its star.
        if next_cell == cells {
            f_cell[n] = 255
            video.hide_sprite(n + 1)
            return
        }
        ubyte c = order[next_cell]
        next_cell++
        f_cell[n] = c
        f_left[n] = FLY_FRAMES
        ; the sprite's art centre (frame pixel 10, 10) on the centre of the char
        word tx = (cell_col[c] as word) * 8 + 24 + 4 - 10
        word ty = (cell_row[c] as word) * 8 + 50 + 4 - 10
        word sx
        word sy
        when stars.rand_below(4) {
            0 -> {
                sx = 0                  ; left: the art is in the border's 24 px
                sy = (stars.rand_below(222) as word) + 29
            }
            1 -> {
                sx = 344                ; right
                sy = (stars.rand_below(222) as word) + 29
            }
            2 -> {
                sx = (stars.rand_below(173) as word) * 2
                sy = 29                 ; top: the art ends above line 50
            }
            else -> {
                sx = (stars.rand_below(173) as word) * 2
                sy = 250                ; bottom: the art starts in the bottom border
            }
        }
        f_x[n] = sx
        f_y[n] = sy
        f_dx[n] = (tx - sx) / FLY_FRAMES
        f_dy[n] = (ty - sy) / FLY_FRAMES
        put_flier(n)
    }

    sub put_flier(ubyte n) {
        ubyte s = n + 1
        ubyte bit = video.sprite_bit[s]
        uword x = f_x[n] as uword
        video.spr_ptr[s] = assets.SPR_FLY
        video.spr_col[s] = fly_color[n & 1]
        video.spr_x[s] = lsb(x)
        video.spr_y[s] = lsb(f_y[n] as uword)
        if msb(x) != 0
            video.spr_msb |= bit
        else
            video.spr_msb &= ~bit
        video.spr_ena |= bit
    }

    sub land(ubyte n) {
        ubyte c = f_cell[n]
        @(video.COLOR_RAM + cell_off[c]) = FLASH_COLOR
        sp_cell[n] = c
        sp_left[n] = SPARKLE_FRAMES
        landed++
    }

    sub twinkle() {
        ; A few random logo chars flash white; after the color band's recolor, so they stay white.
        ubyte n
        for n in 0 to TWINKLES - 1 {
            if tw_on[n] != 0 {
                tw_on[n]--
                if tw_on[n] == 0
                    recolor(tw_cell[n])
                else
                    @(video.COLOR_RAM + cell_off[tw_cell[n]]) = FLASH_COLOR
            } else if tw_wait[n] != 0
                tw_wait[n]--
            else {
                tw_cell[n] = stars.rand_below(cells)
                tw_on[n] = TWINKLE_ON
                tw_wait[n] = stars.rand_below(TWINKLE_GAP)
                @(video.COLOR_RAM + cell_off[tw_cell[n]]) = FLASH_COLOR
            }
        }
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
