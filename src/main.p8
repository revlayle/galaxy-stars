; Galaxy Stars, a C64 action game. Phase 2: player movement over a random test galaxy
; (HUD with placeholder values; stars are not solid yet).

%import video
%import input
%import stars
%import player
%zeropage basicsafe
%memtop $C000

main {
    const ubyte TEST_STARS = 15
    ; Self-test switches: keep false / 0 in builds for the designer.
    const bool DEBUG_HUD = false        ; test readouts in place of the HUD row
    const ubyte TEST = 0                ; scripted test (needs input.SCRIPTED): 1 move, 2 boost, 3 clamp, 4 spin

    sub start() {
        video.init()
        video.start_frame_irq()
        stars.seed()
        stars.place(TEST_STARS)
        video.draw_playfield()
        video.draw_hud()
        video.hud_score(0, 0, 0)
        video.hud_time($60)
        video.hud_mult(1)
        video.hud_lives(3)
        player.init()
        player.draw()
        if input.SCRIPTED
            select_script()

        repeat {
            video.wait_frame()
            input.read()
            player.update()
            player.draw()
            if DEBUG_HUD
                debug_hud()
        }
    }

    ; ---- self-tests ----
    ; Scripts are (frames, joystick bits) pairs, see input.p8. U=1 D=2 L=4 R=8 F=16.
    ubyte[] script_move = [50, 0, 100, 8, 0, 0]
    ; right to x=304; boost left (75 frames), extra press at boost frame 41, presses 11 and 24 frames
    ; after the boost (cooldown, ignored), then 26 frames after (accepted)
    ubyte[] script_boost = [50, 0, 100, 8,
                            1, 4 | 16, 39, 4, 1, 4 | 16, 34, 4,
                            10, 0, 1, 16, 12, 0, 1, 16, 1, 0, 1, 16, 0, 0]
    ; push into every edge and corner, partly boosting
    ubyte[] script_clamp = [50, 0, 150, 1, 1, 4 | 16, 250, 4, 150, 2, 1, 8 | 16, 250, 8,
                            200, 1 | 4, 1, 2 | 8 | 16, 200, 2 | 8, 150, 1 | 8, 0, 0]
    ; each phase 150 frames: right, up, left, down, right+boost
    ubyte[] script_spin = [50, 0, 150, 8, 150, 1, 150, 4, 150, 2, 1, 8 | 16, 149, 8, 0, 0]

    sub select_script() {
        when TEST {
            1 -> input.script = &script_move
            2 -> input.script = &script_boost
            3 -> input.script = &script_clamp
            4 -> input.script = &script_spin
        }
    }

    uword dbg_frames
    ubyte dbg_boosted                   ; frames with the boost running
    ubyte dbg_prev_boosts
    uword dbg_boost_start               ; frame number of the last boost start
    uword dbg_min_x = $FFFF
    uword dbg_max_x
    ubyte dbg_min_y = 255
    ubyte dbg_max_y
    ubyte[6] dbg_history                ; last 6 spin pictures, oldest first
    ubyte dbg_prev_anim
    ubyte dbg_gap                       ; frames between the last two picture changes
    ubyte dbg_gap_count

    sub debug_hud() {
        ; Hex readouts in the HUD row. Common: x, y, frames; then fields for the selected TEST.
        if dbg_frames == 0
            sys.memset(video.SCREEN, 40, video.CHAR_SPACE)
        dbg_frames++
        if player.boost_left != 0 or player.cooldown == player.COOLDOWN_FRAMES
            dbg_boosted++               ; includes the boost's last frame (boost_left just reached 0)
        if player.boosts != dbg_prev_boosts {
            dbg_prev_boosts = player.boosts
            dbg_boost_start = dbg_frames
        }
        if player.x < dbg_min_x
            dbg_min_x = player.x
        if player.x > dbg_max_x
            dbg_max_x = player.x
        if player.y < dbg_min_y
            dbg_min_y = player.y
        if player.y > dbg_max_y
            dbg_max_y = player.y
        dbg_gap_count++
        if player.anim_frame != dbg_prev_anim {
            dbg_prev_anim = player.anim_frame
            dbg_gap = dbg_gap_count
            dbg_gap_count = 0
            ubyte i
            for i in 0 to 4
                dbg_history[i] = dbg_history[i + 1]
            dbg_history[5] = player.anim_frame
        }

        video.hud_text(0, sc:"x")
        hex_word(1, player.x)
        video.hud_text(6, sc:"y")
        hex_byte(7, player.y)
        video.hud_text(10, sc:"n")
        hex_word(11, dbg_frames)
        when TEST {
            3 -> {
                hex_word(16, dbg_min_x)
                hex_word(21, dbg_max_x)
                hex_byte(26, dbg_min_y)
                hex_byte(29, dbg_max_y)
            }
            4 -> {
                hex_digit(16, player.anim_frame)
                @(video.SCREEN + 17) = if player.spin_ccw '-' as ubyte else '+' as ubyte
                ubyte j
                for j in 0 to 5
                    hex_digit(19 + j, dbg_history[j])
                hex_digit(26, dbg_gap)
            }
            else -> {
                video.hud_text(16, sc:"b")
                hex_byte(17, player.boosts)
                video.hud_text(20, sc:"l")
                hex_byte(21, player.boost_left)
                video.hud_text(24, sc:"c")
                hex_byte(25, player.cooldown)
                video.hud_text(28, sc:"f")
                hex_byte(29, dbg_boosted)
                video.hud_text(32, sc:"s")
                hex_word(33, dbg_boost_start)
            }
        }
    }

    sub hex_byte(ubyte col, ubyte value) {
        hex_digit(col, value >> 4)
        hex_digit(col + 1, value & 15)
    }

    sub hex_word(ubyte col, uword value) {
        hex_byte(col, msb(value))
        hex_byte(col + 2, lsb(value))
    }

    sub hex_digit(ubyte col, ubyte n) {
        ; screen codes: '0'-'9' = 48-57, 'a'-'f' = 1-6
        @(video.SCREEN + col) = if n < 10 n + 48 else n - 9
    }
}
