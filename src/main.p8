; Galaxy Stars, a C64 action game. Phase 4: galaxy 1 with star hits, supernovas, chain reactions,
; hostile stars (spawn, chase, boost hurl), score with hostile chains, multiplier, lives (count only)
; and the galaxy timer.

%import video
%import input
%import stars
%import player
%import explode
%import score
%import hostiles
%zeropage basicsafe
%memtop $C000

main {
    ; Self-test switches: keep false / 0 in builds for the designer.
    const bool DEBUG_HUD = false        ; test readouts in place of the HUD row
    ; scripted test (needs input.SCRIPTED): 1 move, 2 boost, 3 clamp, 4 spin (no stars),
    ; 5 three hits, 6 boosted hit, 7 chain reaction, 8 caught in an explosion, 9 chain with multiplier log,
    ; 10 one explosion catching 5 stars (staggered),
    ; 11 hostile spawns in galaxy 1, 12 hostile spawns in galaxy 11 (then a few boosts), 13 contact death,
    ; 14 hurl in the open, 15 hurl into another hostile, 16 hurl explosion next to a star,
    ; 17 supernova kills 2 hostiles, 18 hurl into a stationary star
    const ubyte TEST = 0

    sub start() {
        video.init()
        video.start_frame_irq()
        stars.seed()
        video.draw_hud()
        score.new_game()
        if TEST == 12
            score.galaxy = 11
        explode.clear()
        if TEST == 0 or TEST == 11 or TEST == 12
            stars.place(stars.for_galaxy(score.galaxy))
        else
            test_layout()
        video.draw_playfield()
        score.start_galaxy()
        hostiles.start_galaxy(score.galaxy)
        player.init()
        player.draw()
        if TEST != 0 and TEST <= 10
            hostiles.spawn_timer = $FFFF    ; tests from before the hostiles: none spawn
        if TEST >= 13
            test_hostiles()
        if input.SCRIPTED
            select_script()

        repeat {
            video.wait_frame()
            input.read()
            score.update()              ; first: a multiplier raised this frame keeps its full time
            player.update()
            hostiles.update()
            stars.player_contact()
            hostiles.check_player()
            explode.check_player()
            hostiles.check_explosions()
            stars.update()
            explode.update()
            ; the hostile chain lives while an explosion, a countdown it started, or a hurl is going on
            if explode.live == 0 and hostiles.flying == 0 and stars.blast_countdowns == 0
                score.chain = 0
            player.draw()
            hostiles.draw()
            if DEBUG_HUD {
                ; the next frame IRQ came during this frame's work (not counted after a readout redraw,
                ; which can start the frame late)
                if video.frame_ready and not dbg_drew
                    dbg_missed++
                dbg_prev_drew = dbg_drew
                dbg_drew = false
                debug_hud()
            }
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

    ; star 0 at tile (12,5), right of the start: hold right for 3 hits, then back off left
    ubyte[] script_hits = [50, 0, 150, 8, 60, 4, 0, 0]
    ; one boosted hit on star 0, then back off left
    ubyte[] script_boost_hit = [50, 0, 1, 8 | 16, 30, 8, 60, 4, 0, 0]
    ; boosted hit, then stay next to the star (caught when it explodes)
    ubyte[] script_caught = [50, 0, 1, 8 | 16, 10, 8, 0, 0]
    ubyte[] script_still = [0, 0]
    ; stand still while 6 hostiles gather, then boost right, left and up into them
    ubyte[] script_gather = [250, 0, 250, 0, 100, 0, 1, 8 | 16, 40, 8, 60, 0, 1, 4 | 16, 60, 4, 60, 0,
                             1, 1 | 16, 40, 1, 0, 0]
    ; wait for the hostile from tile (15,5) to come close, then boost right into it for 8 frames
    ubyte[] script_hurl = [120, 0, 1, 8 | 16, 7, 8, 0, 0]

    sub test_layout() {
        stars.clear()
        when TEST {
            5, 6, 8 -> stars.add(12, 5, 0)
            7, 9 -> {
                ; 0-1 next to each other, 2 diagonal to 1, 3 two tiles from 2 (outside its explosion)
                stars.add(12, 5, 0)
                stars.add(13, 5, 1)
                stars.add(14, 6, 2)
                stars.add(16, 6, 3)
            }
            10 -> {
                ; star 0 is hit; stars 1-5 around it are caught by its explosion
                stars.add(12, 5, 0)
                stars.add(11, 4, 1)
                stars.add(12, 4, 2)
                stars.add(13, 4, 3)
                stars.add(13, 5, 4)
                stars.add(13, 6, 5)
            }
            13, 14 -> stars.add(15, 5, 0)
            15 -> {
                stars.add(15, 5, 0)
                stars.add(18, 5, 1)
            }
            16 -> {
                stars.add(15, 5, 0)
                stars.add(18, 4, 1)         ; in the area where the hurl ends, out of the flight path
            }
            17 -> {
                stars.add(12, 5, 0)         ; hit by the player
                stars.add(12, 4, 1)         ; hostiles that stand still in its explosion area
                stars.add(13, 6, 2)
            }
            18 -> {
                stars.add(15, 5, 0)
                stars.add(17, 5, 1)         ; in the flight path
            }
        }
        stars.place_specks()
    }

    sub test_hostiles() {
        ; No timed spawns: the test picks which stars turn hostile.
        hostiles.spawn_timer = $FFFF
        when TEST {
            15 -> {
                stars.start_warning(0)
                stars.start_warning(1)
            }
            17 -> {
                stars.start_warning(1)
                stars.start_warning(2)
                hostiles.set_speed(0)
            }
            else -> stars.start_warning(0)
        }
    }

    sub select_script() {
        when TEST {
            1 -> input.script = &script_move
            2 -> input.script = &script_boost
            3 -> input.script = &script_clamp
            4 -> input.script = &script_spin
            5 -> input.script = &script_hits
            6, 7, 9, 10 -> input.script = &script_boost_hit
            8 -> input.script = &script_caught
            11, 13 -> input.script = &script_still
            12 -> input.script = &script_gather
            14, 15, 16, 18 -> input.script = &script_hurl
            17 -> input.script = &script_boost_hit
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
    ubyte[6] dbg_state                  ; last seen state of stars 0-5
    uword[6] dbg_cd_frame               ; frame each of stars 0-5 entered its countdown
    uword[6] dbg_nova_frame             ; frame each went supernova
    ubyte dbg_prev_mult = 1
    uword[6] dbg_mult_frame             ; frames of the first 6 multiplier changes
    ubyte dbg_mult_changes
    ubyte dbg_prev_spawned
    uword[6] dbg_spawn_frame            ; frames of the last 6 spawns (warning starts), oldest first
    ubyte dbg_max_active
    ubyte dbg_max_lines                 ; most raster lines a frame's work took
    ubyte dbg_missed                    ; frames where the work took longer than a frame
    bool dbg_drew                       ; the readouts were redrawn this frame
    bool dbg_prev_drew
    ubyte dbg_prev_blasts
    uword dbg_blast_frame

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

        if TEST >= 11 {
            hostile_readouts()
            return
        }
        if TEST >= 5 {
            star_readouts()
            return
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

    sub star_readouts() {
        ; TEST 5-8: n frames | state+hits of stars 0-3 | star 0 countdown frame | star 0 supernova frame |
        ;           lives | score (hundreds) | mult | bounces
        ; TEST 9:   score | mult | frames of the first 6 multiplier changes
        ; TEST 10:  supernova frames of stars 0-5 | frames
        ubyte i
        for i in 0 to 5 {
            if i < stars.count and stars.state[i] != dbg_state[i] {
                dbg_state[i] = stars.state[i]
                if dbg_state[i] == stars.COUNTDOWN
                    dbg_cd_frame[i] = dbg_frames
                if dbg_state[i] == stars.GONE
                    dbg_nova_frame[i] = dbg_frames
            }
        }
        if score.mult != dbg_prev_mult {
            dbg_prev_mult = score.mult
            if dbg_mult_changes < len(dbg_mult_frame) {
                dbg_mult_frame[dbg_mult_changes] = dbg_frames
                dbg_mult_changes++
            }
        }
        if TEST == 10 {
            for i in 0 to 5
                hex_word(i * 5, dbg_nova_frame[i])
            hex_word(31, dbg_frames)
            return
        }
        if TEST == 9 {
            hex_byte(0, score.points_hi)
            hex_byte(2, score.points_mid)
            hex_byte(4, score.points_lo)
            hex_digit(7, score.mult)
            for i in 0 to 5
                hex_word(9 + i * 5, dbg_mult_frame[i])
            return
        }
        hex_word(0, dbg_frames)
        for i in 0 to 3 {
            if i < stars.count {
                hex_digit(5 + i * 3, stars.state[i])
                hex_digit(6 + i * 3, stars.hits[i])
            }
        }
        hex_word(17, dbg_cd_frame[0])
        hex_word(22, dbg_nova_frame[0])
        hex_digit(27, score.lives)
        hex_byte(29, score.points_hi)
        hex_byte(31, score.points_mid)
        hex_byte(33, score.points_lo)
        hex_digit(36, score.mult)
        hex_byte(38, player.bounces)
    }

    sub hostile_readouts() {
        ; TEST 11-12: frames of the last 6 spawns | max hostiles+warnings | now | max raster lines per frame |
        ;             frames that took too long
        ; TEST 13-18: frames | lives | score (hundreds) | mult | chain | hurl x | blast x | blast frame |
        ;             state+hits of star 1 | hostile slots used | kills
        ubyte i
        if hostiles.spawned != dbg_prev_spawned {
            dbg_prev_spawned = hostiles.spawned
            for i in 0 to 4
                dbg_spawn_frame[i] = dbg_spawn_frame[i + 1]
            dbg_spawn_frame[5] = dbg_frames
        }
        ubyte active = hostiles.used + stars.warnings
        if active > dbg_max_active
            dbg_max_active = active
        if hostiles.blasts != dbg_prev_blasts {
            dbg_prev_blasts = hostiles.blasts
            dbg_blast_frame = dbg_frames
        }
        ; work starts at the frame IRQ (line 251); PAL has 312 lines
        uword line = c64.RASTER
        if c64.SCROLY & $80 != 0
            line += 256
        if line >= video.FRAME_IRQ_LINE
            line -= video.FRAME_IRQ_LINE
        else
            line += 312 - video.FRAME_IRQ_LINE
        if line > 255
            line = 255
        if dbg_frames > 2 {
            if lsb(line) > dbg_max_lines
                dbg_max_lines = lsb(line)
        }

        if dbg_frames & 7 != 0
            return                      ; redraw every 8th frame, so the readouts take little frame time
        dbg_drew = true
        if TEST <= 12 {
            for i in 0 to 5
                hex_word(i * 5, dbg_spawn_frame[i])
            hex_digit(30, dbg_max_active)
            hex_digit(32, active)
            hex_byte(34, dbg_max_lines)
            hex_byte(37, dbg_missed)
            return
        }
        hex_word(0, dbg_frames)
        hex_digit(5, score.lives)
        hex_byte(7, score.points_hi)
        hex_byte(9, score.points_mid)
        hex_byte(11, score.points_lo)
        hex_digit(14, score.mult)
        hex_digit(16, score.chain)
        hex_word(18, hostiles.hurl_x)
        hex_word(23, hostiles.blast_x)
        hex_word(28, dbg_blast_frame)
        if stars.count > 1 {
            hex_digit(33, stars.state[1])
            hex_digit(34, stars.hits[1])
        }
        hex_digit(36, hostiles.used)
        hex_digit(38, hostiles.kills)
    }

    sub hex_byte(uword col, ubyte value) {
        hex_digit(col, value >> 4)
        hex_digit(col + 1, value & 15)
    }

    sub hex_word(uword col, uword value) {
        hex_byte(col, msb(value))
        hex_byte(col + 2, lsb(value))
    }

    sub hex_digit(uword col, ubyte n) {
        ; screen codes: '0'-'9' = 48-57, 'a'-'f' = 1-6
        @(video.SCREEN + col) = if n < 10 n + 48 else n - 9
    }
}
