; Galaxy Stars, a C64 action game. Phase 5: the game flow: title, galaxy start, play, galaxy clear with the
; time bonus, the next galaxy, losing a life with respawn, game over, pause and the session high score.

%import video
%import input
%import stars
%import player
%import explode
%import score
%import hostiles
%import title
%import prof
%import quasar
%zeropage basicsafe
%memtop $C000

main {
    ; Self-test switches: keep false / 0 in builds for the designer.
    const bool DEBUG_HUD = false        ; test readouts in place of the HUD row
    const bool PROFILE = false          ; frame-time breakdown on char rows 21-24 (prof.p8)
    ; scripted test (needs input.SCRIPTED): 1 move, 2 boost, 3 clamp, 4 spin (no stars),
    ; 5 three hits, 6 boosted hit, 7 chain reaction, 8 caught in an explosion, 9 chain with multiplier log,
    ; 10 one explosion catching 5 stars (staggered),
    ; 11 hostile spawns in galaxy 1, 12 hostile spawns in galaxy 21, the hardest (then a few boosts), 13 contact death,
    ; 14 hurl in the open, 15 hurl into another hostile, 16 hurl explosion next to a star,
    ; 17 supernova kills 2 hostiles, 18 hurl into a stationary star.
    ; Game flow (phase 5): 19 full loop (title, galaxy 1 cleared, galaxy 2 lost, game over, title),
    ; 20 clear bonus and extra life, 21 extra life thresholds (no play, needs DEBUG_HUD), 22 pause,
    ; 23 death and respawn (DEBUG_HUD), 24 boost hurl while safe (DEBUG_HUD), 25 explosion while safe (DEBUG_HUD),
    ; 26 respawn push and hold, top hostile speed (DEBUG_HUD),
    ; 27 hurl of a hostile that touches a star, 28 hurl off the playfield edge (readouts as tests 13-18),
    ; 29 boost into a star from a one-tile gap between two stars, 30 the same vertically,
    ; 31 lone explosions in column 0 and row 0: their tiles are restored afterwards (readouts as tests 5-8),
    ; 32 map of an explosion's round core (explode.hits), no play
    ; Quasar (phase 6, quasar.ALWAYS is on for these; DEBUG_HUD): 33 quasar appears and burns out,
    ; 34 pickup and invincibility (speed, stars, hostile, explosion, fire, glow), 35 one quasar per galaxy (2 galaxies)
    const ubyte TEST = 0
    const bool OLD_TEST = TEST != 0 and (TEST < 19 or (TEST >= 27 and TEST <= 31) or TEST == 33 or TEST == 34)  ; one galaxy, never ends
    const bool NO_DEATH = TEST == 11 or TEST == 12  ; spawn and frame time tests: the player can't be hurt

    ; [TUNE] game flow
    const ubyte START_FRAMES = 100      ; GALAXY nn for 2 s while the stars appear, one per frame
    const ubyte CLEAR_FRAMES = 150      ; GALAXY CLEAR and the time bonus for 3 s
    const ubyte MSG_COLOR = 1
    const ubyte START_ROW = 9           ; GALAXY nn, above the player
    const ubyte START_COL = 15
    str galaxy_text = sc:"galaxy 00"

    ; test_stage() arguments
    const ubyte STAGE_TITLE = 0
    const ubyte STAGE_PLAY = 1
    const ubyte STAGE_GAME_OVER = 2

    sub start() {
        video.init()
        score.init()
        video.start_frame_irq()
        if OLD_TEST
            old_test()
        if TEST == 21
            extra_life_test()
        if TEST == 32
            core_map_test()

        repeat {
            if TEST == 0 or TEST == 19
                title.run()             ; seeds the RNG
            else
                stars.seed()
            new_game()
            repeat {
                galaxy_start()
                if not play()
                    break
                galaxy_clear()
            }
            title.game_over()
        }
    }

    sub new_game() {
        video.clear_screen()
        video.draw_hud()
        score.new_game()
        if TEST == 20 {
            score.points_mid = $04      ; 49,900: the supernova reaches 50,000
            score.points_lo = $99
        }
    }

    sub galaxy_start() {
        ; GALAXY nn for 2 s while the stars appear in random order; no control, the timer doesn't run.
        explode.clear()
        if TEST == 0 or TEST == 22 or (TEST == 19 and score.galaxy != 1)
            stars.place(stars.for_galaxy(score.galaxy))
        else
            test_layout()
        stars.hide_for_reveal()
        video.draw_playfield()
        score.start_galaxy()
        hostiles.start_galaxy(score.galaxy)
        quasar.start_galaxy()
        player.init()
        player.draw()
        ubyte g = score.galaxy
        if g > 99
            g = 99
        galaxy_text[7] = '0' as ubyte + g / 10
        galaxy_text[8] = '0' as ubyte + g % 10
        repeat START_FRAMES {
            video.wait_frame()
            input.read()
            stars.reveal_next()
            video.message(START_ROW, START_COL, galaxy_text, MSG_COLOR)     ; again over a star drawn under it
        }
        while stars.revealed < stars.count
            stars.reveal_next()
        video.restore_tiles(START_ROW, START_COL, len(galaxy_text))
    }

    sub play() -> bool {
        ; PLAYING. True when the galaxy is clear, false when the last life is lost (after its death effect).
        ; When the last star is destroyed the timer and multiplier stop; play goes on until the explosions and
        ; hurls are over (the player can still be hurt) and a death effect has ended.
        test_stage(STAGE_PLAY)
        if PROFILE
            prof.init()
        repeat {
            video.wait_frame()
            if PROFILE
                prof.start()
            input.read()
            if input.pressed & input.STOP != 0
                pause()
            if stars.left != 0 or OLD_TEST
                score.update()          ; first: a multiplier raised this frame keeps its full time
            if PROFILE
                prof.mark(0)
            player.update()
            if PROFILE
                prof.mark(1)
            hostiles.update()
            if PROFILE
                prof.mark(2)
            if player.dying == 0
                stars.player_contact()
            if PROFILE
                prof.mark(3)
            hostiles.check_player()
            if PROFILE
                prof.mark(4)
            explode.check_player()
            if PROFILE
                prof.mark(5)
            hostiles.check_explosions()
            if PROFILE
                prof.mark(6)
            stars.update()
            if PROFILE
                prof.mark(7)
            explode.update()
            quasar.update()
            if PROFILE
                prof.mark(8)
            ; the hostile chain lives while an explosion, a countdown it started, a hurl or invincibility is going on
            if explode.live == 0 and hostiles.flying == 0 and stars.blast_countdowns == 0 and player.invincible == 0
                score.chain = 0
            player.draw()
            hostiles.draw()
            quasar.draw()
            score.flush()
            if PROFILE {
                prof.mark(9)
                prof.end_frame()
            }
            if TEST != 0
                test_frame()
            if player.gone
                return false
            if not OLD_TEST and stars.left == 0 and explode.live == 0 and explode.queued == 0
                    and hostiles.flying == 0 and player.dying == 0
                return true
        }
    }

    sub pause() {
        ; Run/Stop again resumes. Everything is frozen meanwhile, the timer too. PAUSED in the free HUD columns.
        video.message(0, 18, sc:"paused", MSG_COLOR)
        do {
            video.wait_frame()
            input.read()
        } until input.pressed & input.STOP != 0
        sys.memset(video.SCREEN + 18, 6, video.CHAR_SPACE)
        video.hud_invincible(player.inv_secs)      ; the countdown shares the PAUSED columns
        input.pressed = 0               ; the resume press is not a game input
    }

    sub galaxy_clear() {
        ; GALAXY CLEAR and the time bonus (added now, then the multiplier is x1) for 3 s; then the next galaxy.
        score.time_bonus()
        quasar.start_galaxy()           ; a quasar still shown (or about to appear) goes
        player.invincible = 0           ; and invincibility ends
        player.inv_secs = 0
        video.hud_invincible(0)
        video.message(10, 14, sc:"galaxy clear", MSG_COLOR)
        video.message(12, 12, sc:"time bonus", MSG_COLOR)
        uword a = video.row_addr(12) + 23
        ubyte n = video.put_hundreds(a, score.bonus_mid, score.bonus_lo)
        sys.memset(a + video.COLOR_RAM - video.SCREEN, n, MSG_COLOR)
        repeat CLEAR_FRAMES {
            video.wait_frame()
            input.read()
            if TEST != 0
                test_frame()
        }
        if score.galaxy != 255
            score.galaxy++
    }

    sub old_test() {
        ; Tests 1-18 (phases 2-4): one galaxy set up by the test, never cleared.
        stars.seed()
        video.draw_hud()
        score.new_game()
        if TEST == 12
            score.galaxy = 21
        explode.clear()
        if TEST == 11 or TEST == 12
            stars.place(stars.for_galaxy(score.galaxy))
        else
            test_layout()
        video.draw_playfield()
        score.start_galaxy()
        hostiles.start_galaxy(score.galaxy)
        quasar.start_galaxy()
        player.init()
        player.draw()
        if TEST == 5 or TEST == 8 or TEST == 34
            player.y = 82                   ; lined up with the star's box (y 82-93): straight bounces back
        if TEST == 29 {
            player.x = 209                  ; box x 209-221 in the gap: star boxes end at 205 and start at 226
            player.y = 82                   ; lined up with the stars' boxes (y 82-93)
        }
        if TEST == 30 {
            player.x = 161                  ; lined up with the stars' boxes (x 162-173)
            player.y = 81                   ; box y 81-93 in the gap: star boxes end at 77 and start at 98
        }
        if TEST == 31 {
            stars.start_countdown(0)
            stars.start_countdown(1)
            stars.timer[1] = 150            ; a separate explosion, after the first one has ended
        }
        if TEST <= 10 or TEST >= 29
            hostiles.spawn_timer = $FFFF    ; tests from before the hostiles: none spawn
        if TEST >= 13 and TEST < 29
            test_hostiles()
        if TEST == 34 {
            stars.start_warning(3)          ; a hostile that stands still at the right edge
            hostiles.set_speed(0)
        }
        if input.SCRIPTED
            select_script()
        void play()
        repeat {
            video.wait_frame()
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
    ; test 17: boosted hit on star 0, let go during the bounce, then back off left (away from the hostiles)
    ubyte[] script_hit_back = [50, 0, 1, 8 | 16, 9, 8, 10, 0, 60, 4, 0, 0]
    ; boosted hit, then stay next to the star (caught when it explodes)
    ubyte[] script_caught = [50, 0, 1, 8 | 16, 10, 8, 0, 0]
    ; test 8: boosted hit, then keep pushing into the star until it explodes (well inside its core)
    ubyte[] script_caught_close = [50, 0, 1, 8 | 16, 200, 8, 0, 0]
    ubyte[] script_still = [0, 0]
    ; stand still while 6 hostiles gather, then boost right, left and up into them
    ubyte[] script_gather = [250, 0, 250, 0, 100, 0, 1, 8 | 16, 40, 8, 60, 0, 1, 4 | 16, 60, 4, 60, 0,
                             1, 1 | 16, 40, 1, 0, 0]
    ; wait for the hostile from tile (15,5) to come close, then boost right into it for 8 frames
    ubyte[] script_hurl = [120, 0, 1, 8 | 16, 7, 8, 0, 0]
    ; test 28: move right 60 px, wait for the hostile from tile (19,5), then boost right into it
    ubyte[] script_edge = [50, 0, 40, 8, 50, 0, 1, 8 | 16, 7, 8, 0, 0]
    ; test 29: boost right into star 1, keep pushing right, then up out of the gap
    ubyte[] script_gap = [50, 0, 1, 8 | 16, 9, 8, 30, 1, 0, 0]
    ; test 30: boost up into star 1, keep pushing up, then left out of the gap
    ubyte[] script_gap_v = [50, 0, 1, 1 | 16, 9, 1, 30, 4, 0, 0]
    ; test 34: boosted hit on star 0, back off left and wait for its quasar; then right into the quasar and on
    ; through stars 1 and 2 to the hostile at the edge; a fire press there (does nothing while invincible); keep
    ; pushing right until the invincibility is over
    ubyte[] script_quasar = [50, 0, 1, 8 | 16, 30, 8, 60, 4, 100, 0, 150, 8, 1, 8 | 16, 250, 8, 250, 8, 0, 0]

    sub test_layout() {
        stars.clear()
        when TEST {
            5, 6, 8, 19, 20, 33 -> stars.add(12, 5, 0)
            34 -> {
                stars.add(12, 5, 0)         ; hit by the player: leaves the quasar
                stars.add(15, 5, 1)         ; in the path after the pickup
                stars.add(17, 5, 2)
                stars.add(19, 5, 3)         ; turns hostile and stands still at the right edge
            }
            7, 9 -> {
                ; 0-1 next to each other, 2 diagonal to 1, 3 two tiles from 2 (outside its explosion)
                stars.add(12, 5, 0)
                stars.add(13, 5, 1)
                stars.add(14, 6, 2)
                stars.add(16, 6, 3)
            }
            10, 35 -> {
                ; star 0 is hit; stars 1-5 around it are caught by its explosion
                stars.add(12, 5, 0)
                stars.add(11, 4, 1)
                stars.add(12, 4, 2)
                stars.add(13, 4, 3)
                stars.add(13, 5, 4)
                stars.add(13, 6, 5)
            }
            13, 14, 23, 24, 26 -> stars.add(15, 5, 0)
            25 -> {
                stars.add(12, 5, 0)         ; hit by the player, who is caught in its explosion
                stars.add(10, 7, 1)         ; its explosion covers the centre while the player is safe
            }
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
                stars.add(12, 4, 1)         ; hostiles that stand still in its explosion's core (above it and
                stars.add(13, 5, 2)         ; right of it; a diagonal neighbour is outside the round core)
            }
            29 -> {
                stars.add(12, 5, 0)         ; the player starts in the empty tile (13,5) between them
                stars.add(14, 5, 1)
            }
            31 -> {
                stars.add(0, 5, 0)          ; explodes in column 0
                stars.add(5, 0, 1)          ; explodes in row 0
            }
            30 -> {
                stars.add(10, 6, 0)         ; the player starts in the empty tile (10,5) between them
                stars.add(10, 4, 1)
            }
            28 -> stars.add(19, 5, 0)       ; turns hostile; hurled right near the edge
            27 -> {
                stars.add(15, 5, 0)         ; turns hostile
                stars.add(12, 5, 1)         ; the hostile is over it when it is hurled
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
            8 -> input.script = &script_caught_close
            11, 13 -> input.script = &script_still
            12 -> input.script = &script_gather
            14, 15, 16, 18, 27 -> input.script = &script_hurl
            28 -> input.script = &script_edge
            29 -> input.script = &script_gap
            30 -> input.script = &script_gap_v
            17 -> input.script = &script_hit_back
            33 -> input.script = &script_boost_hit
            34 -> input.script = &script_quasar
        }
    }

    ; ---- game flow self-tests (19-25) ----
    ubyte[] script_title = [60, 0, 1, 16, 0, 0]
    ; still until a hostile moves, Run/Stop (32), 100 frames paused, Run/Stop
    ubyte[] script_pause = [250, 0, 170, 0, 1, 32, 99, 0, 1, 32, 0, 0]
    ; test 24: after the first respawn, boost towards where the hostile is pushed (direction filled in then)
    ubyte[] script_safe_boost = [1, 16, 40, 0, 0, 0]
    ; push heading in 8ths (0 right, clockwise) -> joystick bits
    ubyte[8] octant_joy = [8, 8 | 2, 2, 4 | 2, 4, 4 | 1, 1, 8 | 1]
    const ubyte SAFE_BLAST = 220        ; test 25: frame star 1 explodes, while the player is safe

    ubyte title_visits
    bool fl_boost_set
    uword fl_frames                     ; frames since the galaxy's play started
    ubyte fl_prev_deaths
    ubyte fl_prev_respawns
    uword[3] fl_death                   ; frames of the first 3 deaths
    uword[2] fl_respawn                 ; frames of the first 2 respawns
    uword fl_star1_gone
    ubyte fl_q_shows                    ; test 35
    uword[2] fl_q_frame
    ; test 26: hostile slot 0 after the first respawn
    uword fl_push_end                   ; frame its push ended
    uword fl_push_x                     ; box position then
    ubyte fl_push_y
    bool fl_push_inside                 ; still in the respawn box then (should be false)
    ubyte fl_hold_moves                 ; frames it moved during the safety after the push
    ubyte fl_chase_moves                ; frames it moved after the safety (until the next death)
    uword fl_last_x
    ubyte fl_last_y

    sub set_script(uword s) {
        input.script = s
        input.script_pos = 0
        input.script_left = 0
    }

    sub test_stage(ubyte stage) {
        ; Game flow tests: the script for each screen.
        if not input.SCRIPTED or OLD_TEST
            return
        when stage {
            STAGE_TITLE -> {
                ; the first title starts a game, the second stays
                if title_visits == 0
                    set_script(&script_title)
                else
                    set_script(&script_still)
                title_visits++
            }
            STAGE_PLAY -> {
                fl_frames = 0
                when TEST {
                    19 -> {
                        if score.galaxy == 1
                            set_script(&script_boost_hit)
                        else
                            set_script(&script_still)
                    }
                    20, 35 -> set_script(&script_boost_hit)
                    22 -> set_script(&script_pause)
                    23, 24 -> {
                        set_script(&script_still)
                        test_hostiles()
                    }
                    26 -> {
                        set_script(&script_still)
                        test_hostiles()
                        hostiles.set_speed(hostiles.galaxy_speed[len(hostiles.galaxy_speed) - 1])  ; 1.8 px/f: back at the centre in 2 s without the hold
                    }
                    25 -> {
                        set_script(&script_caught)
                        hostiles.spawn_timer = $FFFF
                        stars.start_countdown(1)
                        stars.timer[1] = SAFE_BLAST
                    }
                }
            }
            STAGE_GAME_OVER -> set_script(&script_title)
        }
    }

    sub test_frame() {
        ; Called every frame of play (and of the galaxy clear screen) in test builds.
        if OLD_TEST {
            if DEBUG_HUD {
                ; the next frame IRQ came during this frame's work (not counted after a readout redraw,
                ; which can start the frame late, nor on the first frame, which starts late after the setup)
                if video.frame_ready and not dbg_drew and dbg_frames != 0
                    dbg_missed++
                dbg_prev_drew = dbg_drew
                dbg_drew = false
                debug_hud()
            }
            return
        }
        fl_frames++
        if player.deaths != fl_prev_deaths {
            if fl_prev_deaths < len(fl_death)
                fl_death[fl_prev_deaths] = fl_frames
            fl_prev_deaths = player.deaths
        }
        if player.respawns != fl_prev_respawns {
            if fl_prev_respawns < len(fl_respawn)
                fl_respawn[fl_prev_respawns] = fl_frames
            fl_prev_respawns = player.respawns
        }
        if TEST == 24 and player.respawns == 1 and not fl_boost_set {
            ubyte joy = octant_joy[((hostiles.push_dir[0] + 1) & 15) >> 1]
            script_safe_boost[1] = joy | input.FIRE
            script_safe_boost[3] = joy
            set_script(&script_safe_boost)
            fl_boost_set = true
        }
        if TEST == 35 and quasar.shows != fl_q_shows {
            if fl_q_shows < len(fl_q_frame)
                fl_q_frame[fl_q_shows] = fl_frames
            fl_q_shows = quasar.shows
        }
        if TEST == 25 and fl_star1_gone == 0 and stars.state[1] == stars.GONE
            fl_star1_gone = fl_frames
        if TEST == 26 and hostiles.state[0] == hostiles.CHASE {
            uword hx = hostiles.x[0]
            ubyte hy = hostiles.y[0]
            if player.respawns == 1 and player.deaths == 1 {
                bool moved = hx != fl_last_x or hy != fl_last_y
                if fl_push_end == 0 {
                    if not hostiles.pushing[0] {
                        fl_push_end = fl_frames
                        fl_push_x = hx
                        fl_push_y = hy
                        fl_push_inside = hostiles.in_push_box(0)
                    }
                } else if moved {
                    if player.safe != 0
                        fl_hold_moves++
                    else
                        fl_chase_moves++
                }
            }
            fl_last_x = hx
            fl_last_y = hy
        }
        if DEBUG_HUD and fl_frames & 7 == 0
            flow_readouts()
    }

    sub flow_readouts() {
        ; frames | lives | dying | safe | death 1 | respawn 1 | death 2 | respawn 2 |
        ; test 25: frame star 1 exploded, else kills and hostiles in use | deaths
        sys.memset(video.SCREEN, 40, video.CHAR_SPACE)
        if TEST == 35 {
            ; frames | galaxy | quasars shown in total | appeared this galaxy | frames shown (in this galaxy's
            ; frame count) of the first two | supernovas (stars gone) this galaxy
            hex_word(0, fl_frames)
            hex_byte(5, score.galaxy)
            hex_digit(8, quasar.shows)
            hex_digit(10, quasar.appeared as ubyte)
            hex_word(12, fl_q_frame[0])
            hex_word(17, fl_q_frame[1])
            ubyte gone = 0
            ubyte k
            for k in 0 to stars.count - 1 {
                if stars.state[k] == stars.GONE
                    gone++
            }
            hex_digit(22, gone)
            hex_digit(24, stars.left)
            return
        }
        if TEST == 26 {
            ; frames | death 1 | respawn 1 | push end | box x, y then | inside | moves while held | moves after |
            ; pushes | deaths
            hex_word(0, fl_frames)
            hex_word(5, fl_death[0])
            hex_word(10, fl_respawn[0])
            hex_word(15, fl_push_end)
            hex_word(20, fl_push_x)
            hex_byte(25, fl_push_y)
            hex_digit(28, fl_push_inside as ubyte)
            hex_byte(30, fl_hold_moves)
            hex_byte(33, fl_chase_moves)
            hex_digit(36, hostiles.pushes)
            hex_digit(38, player.deaths)
            return
        }
        hex_word(0, fl_frames)
        hex_digit(5, score.lives)
        hex_byte(7, player.dying)
        hex_byte(10, player.safe)
        hex_word(13, fl_death[0])
        hex_word(18, fl_respawn[0])
        hex_word(23, fl_death[1])
        hex_word(28, fl_respawn[1])
        if TEST == 25
            hex_word(33, fl_star1_gone)
        else {
            hex_digit(33, hostiles.kills)
            hex_digit(35, hostiles.used)
        }
        hex_digit(38, player.deaths)
    }

    ubyte[17] core_row

    sub core_map_test() {
        ; Test 32: explode.hits() for centre offsets -32..32 px in steps of 4 around an explosion centred on
        ; (160, 96): '*' hit, '.' miss, from char row 2, column 4 (17 x 17). The 3x3 tiles reach +-24 px.
        video.clear_screen()
        explode.core_x[0] = 160
        explode.core_y[0] = 96
        ubyte gy
        ubyte gx
        for gy in 0 to 16 {
            explode.obj_y = 96 - 32 + gy * 4
            for gx in 0 to 16 {
                explode.obj_x = 160 - 32 + (gx as uword) * 4
                core_row[gx] = '.' as ubyte
                if explode.hits(0)
                    core_row[gx] = '*' as ubyte
            }
            uword a = video.row_addr(2 + gy) + 4
            for gx in 0 to 16
                @(a + gx * 2) = core_row[gx]
        }
        repeat {
        }
    }

    sub extra_life_test() {
        ; Test 21: extra life thresholds without play. Readouts: lives, next threshold (BCD hundreds) after
        ; each step; then the score and the no-more-lives flag; then 8 chain kills (score in hundreds).
        video.draw_hud()
        score.new_game()
        sys.memset(video.SCREEN, 40, video.CHAR_SPACE)
        score.add($00, $06)             ; 60,000: lives 3 -> 6, next 80,000
        hex_digit(0, score.lives)
        hex_byte(2, score.next_hi)
        hex_byte(4, score.next_mid)
        hex_byte(6, score.next_lo)
        score.mult = 9
        score.add($00, $10)             ; 9 x 100,000: 960,000, lives 9 (the cap), next 980,000
        hex_digit(9, score.lives)
        hex_byte(11, score.next_hi)
        hex_byte(13, score.next_mid)
        hex_byte(15, score.next_lo)
        hex_byte(18, score.points_hi)
        hex_byte(20, score.points_mid)
        hex_byte(22, score.points_lo)
        score.points_hi = $99           ; 99,999,800 + 100: the score stops at its maximum
        score.points_mid = $99
        score.points_lo = $98
        score.mult = 1
        score.add($01, $00)
        hex_digit(25, score.lives)
        hex_byte(27, score.points_hi)
        hex_byte(29, score.points_mid)
        hex_byte(31, score.points_lo)
        hex_digit(34, score.no_more_lives as ubyte)
        ; chain cap: 8 kills at x1 = 500 + 1000 + 2000 + 4000 + 8000 + 16000 x 3 = 63,500 (hundreds BCD 0635)
        score.points_hi = 0
        score.points_mid = 0
        score.points_lo = 0
        score.chain = 0
        repeat 8
            score.chain_kill()
        hex_byte(36, score.points_mid)
        hex_byte(38, score.points_lo)
        repeat {
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

        if TEST == 33 or TEST == 34 {
            quasar_readouts()
            return
        }
        if TEST >= 11 and TEST < 29 {
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

    ubyte q_prev_shows
    uword q_appear                      ; frame the quasar appeared
    uword q_end                         ; frame it burnt out or was picked up
    uword q_inv_end                     ; frame the invincibility ended
    bool q_prev_inv
    uword q_pick_x                      ; player box x at the pickup
    ubyte q_dx10                        ; px moved in the 10 frames after the pickup
    ubyte q_prev_color
    ubyte q_color_gap                   ; frames between the last two player color changes
    ubyte q_color_count
    ubyte q_gap_early                   ; that gap at 300 frames of invincibility left (fast glow)
    ubyte q_gap_late                    ; and at 10 left (slow glow)
    uword[3] q_nova                     ; frames stars 1-3 went GONE (3: turned hostile)
    uword q_kill                        ; frame of the first hostile kill
    ubyte q_prev_kills
    ubyte q_min_lives = 9
    ubyte q_blink_hidden                ; frames the quasar sprite was hidden while shown (blinking)

    sub quasar_readouts() {
        ; TEST 33-34. Row 0: frames | shows pickups | appear frame | end frame | invincibility end frame | lives |
        ; score (hundreds) | chain | kills | boosts.
        ; Row 24: pickup x | dx in 10 frames | color gap fast, slow | stars 1, 2 gone frames | kill frame |
        ; min lives | frames hidden blinking
        if dbg_frames == 1 {
            sys.memset(video.row_addr(24), 40, video.CHAR_SPACE)
            sys.memset(video.row_addr(24) + video.COLOR_RAM - video.SCREEN, 40, 1)
        }
        if quasar.shows != q_prev_shows {
            q_prev_shows = quasar.shows
            q_appear = dbg_frames
        }
        if quasar.life != 0 and video.spr_ena & 128 == 0
            q_blink_hidden++
        if quasar.shows != 0 and quasar.life == 0 and q_end == 0
            q_end = dbg_frames
        bool inv = player.invincible != 0
        if inv and not q_prev_inv
            q_pick_x = player.x
        if q_prev_inv and not inv
            q_inv_end = dbg_frames
        q_prev_inv = inv
        if player.invincible == player.INVINCIBLE_FRAMES - 10
            q_dx10 = lsb(player.x - q_pick_x)
        q_color_count++
        if player.color != q_prev_color {
            q_prev_color = player.color
            q_color_gap = q_color_count
            q_color_count = 0
        }
        if player.invincible == 300
            q_gap_early = q_color_gap
        if player.invincible == 10
            q_gap_late = q_color_gap
        ubyte i
        for i in 1 to 3 {
            if i < stars.count and stars.state[i] == stars.GONE and q_nova[i - 1] == 0
                q_nova[i - 1] = dbg_frames
        }
        if hostiles.kills != q_prev_kills {
            q_prev_kills = hostiles.kills
            if q_kill == 0
                q_kill = dbg_frames
        }
        if score.lives < q_min_lives
            q_min_lives = score.lives

        if dbg_frames & 7 != 0
            return
        dbg_drew = true
        hex_word(0, dbg_frames)
        hex_digit(5, quasar.shows)
        hex_digit(6, quasar.pickups)
        hex_word(8, q_appear)
        hex_word(13, q_end)
        hex_word(18, q_inv_end)
        hex_digit(23, score.lives)
        hex_byte(25, score.points_hi)
        hex_byte(27, score.points_mid)
        hex_byte(29, score.points_lo)
        hex_digit(32, score.chain)
        hex_digit(34, hostiles.kills)
        hex_byte(36, player.boosts)
        uword r = 24 * 40
        hex_word(r + 0, q_pick_x)
        hex_byte(r + 5, q_dx10)
        hex_digit(r + 8, q_gap_early)
        hex_digit(r + 10, q_gap_late)
        hex_word(r + 12, q_nova[0])
        hex_word(r + 17, q_nova[1])
        hex_word(r + 22, q_kill)
        hex_digit(r + 27, q_min_lives)
        hex_byte(r + 29, q_blink_hidden)
        hex_digit(r + 32, quasar.appeared as ubyte)
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
