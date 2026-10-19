; Demo play in the attract cycle (spec section 11): a game in galaxy 3-5 played by a simple pilot, with DEMO on
; the HUD, for 30 s, until the pilot loses a life or after GALAXY CLEAR. Fire on the real joystick starts a game. The high score isn't
; touched (only the game over updates it).
; The pilot writes joystick bits in place of the stick (input.read() calls steer() while input.pilot is on). It
; looks at the game's own state each frame: away from nearby countdown stars, explosions and stars turning
; hostile; a boost into a close hostile (away from it during the cooldown); else to the nearest safe star, with a
; boost into it. It doesn't have to play well, only look busy and mostly safe.
; Frame time: the threats are checked by tile before any distance is measured, and the search for the next star
; looks at SCAN_PER_FRAME stars per frame.

%import input
%import video
%import player
%import stars
%import hostiles
%import explode
%import score

demo {
    ; [TUNE]
    const uword PLAY_FRAMES = 1500      ; 30 s of play
    const ubyte FIRST_GALAXY = 3        ; a random galaxy 3-5
    const ubyte GALAXIES = 3
    const ubyte HUD_COL = 16            ; DEMO in the free HUD columns, before the invincibility field (20-21)
    ; [TUNE] pilot distances between centres in px (the longer axis plus half the shorter, as explode.hits)
    const ubyte FLEE_COUNTDOWN = 44     ; an explosion's core reaches 22
    const ubyte FLEE_BLAST = 40
    const ubyte FLEE_WARNING = 32       ; a hostile appears there
    const ubyte FLEE_HOSTILE = 52
    const ubyte HURL_REACH = 44         ; boost into a hostile this close
    const ubyte HURL_UNLESS = 12        ; but not when a blast threat is this far inside its flee distance
    const ubyte BOOST_REACH = 72        ; boost into the target star this close
    const ubyte BOOST_FLEE = 16         ; boost away from a threat this far inside its flee distance
    const ubyte NEAR_TILES = 3          ; threats are only measured within this many tiles
    const ubyte SCAN_PER_FRAME = 2
    const ubyte HOLD_FRAMES = 8         ; walking to a star: a new stick direction is held at least this long

    bool on                             ; a demo game is running
    bool quit                           ; fire on the real joystick: start a game
    uword frames_left
    ; self-test 40
    uword late                          ; frames whose work overran
    ubyte max_lines                     ; most raster lines steer() took
    ubyte die_blast                     ; at the death: nearest explosion, nearest hostile (px)
    ubyte die_host
    uword turns                         ; stick direction changes (outside knockbacks and the death)
    ubyte last_dir

    ubyte target                        ; star the pilot heads for, 255 = none
    ubyte scan_i                        ; next star the search looks at
    ubyte scan_best                     ; nearest safe star so far in this pass, 255 = none
    ubyte scan_best_d
    ubyte hold_dir                      ; stick direction being held, and frames it must still be held
    ubyte hold_left
    bool reacting                       ; think() is fleeing or going for a hostile this frame: no hold
    bool fired                          ; fire was in the last bits: a new press needs a frame without it
    uword @shared pcx                   ; player's centre (dist() reads them)
    ubyte @shared pcy
    ubyte @shared pcol                  ; and its tile (find_near() reads them)
    ubyte @shared prow
    ubyte @shared d_ax                  ; dist(): distance along each axis and the direction
    ubyte @shared d_ay
    bool @shared d_left
    bool @shared d_up
    const ubyte MAX_NEAR = 8          ; frame time: at most this many are weighed
    ubyte[MAX_NEAR] @shared near_list   ; find_near(): nearby threats
    ubyte @shared n_near
    ubyte urgency                       ; threat(): the most any threat is inside its flee distance
    word wx                             ; flee direction: the threats' pushes added up
    word wy

    sub run() -> bool {
        ; One demo game. True if fire was pressed.
        video.hide_sprites()
        video.wait_frame()
        video.clear_screen()
        video.game_mode()
        main.new_game()
        video.hud_text(HUD_COL, sc:"demo")
        score.galaxy = FIRST_GALAXY + stars.rand_below(GALAXIES)
        if main.TEST == 40 and main.DEMO_GALAXY != 0
            score.galaxy = main.DEMO_GALAXY
        on = true
        quit = false
        frames_left = PLAY_FRAMES
        if main.TEST == 40 and main.DEMO_GALAXY != 0
            frames_left = main.DEMO_FRAMES
        target = 255
        scan_i = 0
        scan_best = 255
        scan_best_d = 255
        fired = false
        hold_dir = 0
        hold_left = 0
        input.start_pilot()
        main.test_stage(main.STAGE_DEMO)
        main.galaxy_start()             ; stops early on fire
        ; play stops on fire, at the time limit or when the death effect has played; a cleared galaxy shows
        ; GALAXY CLEAR and ends the demo too
        if not quit and main.play()
            main.galaxy_clear()
        input.stop_pilot()
        on = false
        video.hide_sprites()
        bool fire = quit
        quit = false                    ; galaxy_start() checks it in every game
        return fire
    }

    sub over() -> bool {
        ; End of each play frame.
        if main.TEST == 40 {
            if video.frame_ready
                late++
            if player.dying == player.DIE_FRAMES {
                death_readout()
                if FREEZE_AT_DEATH
                    freeze()
            }
        }
        frames_left--
        return quit or frames_left == 0 or player.dying == 1
    }

    sub steer() -> ubyte {
        ; This frame's joystick bits. Fire only as a new press.
        uword line0
        if main.TEST == 40
            line0 = raster_line()
        ubyte bits = think()
        ; Smooth movement: walking to a star, a new direction is kept at least HOLD_FRAMES frames (also the last
        ; flee direction once the threats are out of range). Fleeing and going for a hostile react at once, as
        ; does a boost: holding a direction there led the pilot into explosions.
        ubyte dir = bits & 15
        if dir != hold_dir {
            if hold_left != 0 and bits & input.FIRE == 0 and not reacting {
                bits = (bits & ~15) | hold_dir
                hold_left--
            } else {
                hold_dir = dir
                hold_left = HOLD_FRAMES
            }
        } else if hold_left != 0
            hold_left--
        if reacting
            hold_left = HOLD_FRAMES     ; the last flee direction is kept after the threats are out of range
        if fired
            bits &= ~input.FIRE
        fired = bits & input.FIRE != 0
        if main.TEST == 40 {
            if bits & 15 != last_dir and player.knock_left == 0 and player.dying == 0
                turns++
            last_dir = bits & 15
            uword line1 = raster_line()
            if line1 < line0
                line1 += 312
            line1 -= line0
            if line1 > 255
                line1 = 255
            if lsb(line1) > max_lines
                max_lines = lsb(line1)
        }
        return bits
    }

    sub think() -> ubyte {
        urgency = 0
        reacting = false
        if player.dying != 0
            return 0
        pcx = player.x + player.BOX / 2
        pcy = player.y + player.BOX / 2
        pcol = lsb(pcx >> 4)
        prow = pcy >> 4
        scan()
        if target != 255 and stars.state[target] != stars.IDLE {
            target = 255
            if scan_best != 255 and stars.state[scan_best] == stars.IDLE
                target = scan_best
        }
        bool can_boost = player.boost_left == 0 and player.cooldown == 0 and player.invincible == 0
            and player.knock_left == 0
        ubyte i
        if player.invincible == 0 {
            ; threats near the player: countdown stars, stars turning hostile, explosions
            urgency = 0
            wx = 0
            wy = 0
            find_near()
            ubyte k = 0
            while k < n_near {
                i = near_list[k]
                if i & 128 == 0 {
                    uword sx = ((stars.col[i] as uword) << 4) + 8
                    ubyte sy = (stars.row[i] << 4) + 8
                    if stars.state[i] == stars.COUNTDOWN
                        threat(sx, sy, FLEE_COUNTDOWN)
                    else
                        threat(sx, sy, FLEE_WARNING)
                } else {
                    i &= 127
                    threat(explode.core_x[i], explode.core_y[i], FLEE_BLAST)
                }
                k++
            }
            ; the nearest chasing hostile: boost into it, or keep away from it
            ubyte near_h = 255
            ubyte near_d = 255
            for i in 0 to hostiles.MAX - 1 {
                if hostiles.state[i] == hostiles.CHASE {
                    ubyte d = dist(hostiles.x[i] + hostiles.BOX / 2, hostiles.y[i] + hostiles.BOX / 2)
                    if d < near_d {
                        near_d = d
                        near_h = i
                    }
                }
            }
            if near_h != 255 {
                uword hx = hostiles.x[near_h] + hostiles.BOX / 2
                ubyte hy = hostiles.y[near_h] + hostiles.BOX / 2
                if near_d < HURL_REACH and urgency < HURL_UNLESS and (can_boost or player.boost_left != 0) {
                    reacting = true
                    if can_boost
                        return toward(hx, hy) | input.FIRE
                    return toward(hx, hy)
                }
                if player.boost_left == 0
                    threat(hx, hy, FLEE_HOSTILE)
            }
            if urgency != 0 {
                reacting = true
                if can_boost and urgency >= BOOST_FLEE
                    return flee() | input.FIRE  ; escape at boost speed; a hostile touched meanwhile is hurled
                return flee()
            }
        }
        if target == 255
            return toward(160, 96)      ; nothing safe to go for yet: towards the centre
        uword tx = ((stars.col[target] as uword) << 4) + 8
        ubyte ty = (stars.row[target] << 4) + 8
        ubyte td = dist(tx, ty)
        ubyte bits = dir_bits()
        if can_boost and td < BOOST_REACH
            bits |= input.FIRE
        return bits
    }

    asmsub find_near() clobbers(A, X, Y) {
        ; Into near_list (n_near): countdown and warning stars, then running explosions (slot + 128), on tiles
        ; within NEAR_TILES of the player's tile (pcol, prow). Assembly: it runs over every star each frame.
        %asm {{
            ldy  #0
            ldx  #0
_star
            cpx  p8b_stars.p8v_count
            bcs  _blasts
            lda  p8b_stars.p8v_state,x
            cmp  #p8b_stars.p8c_COUNTDOWN
            beq  +
            cmp  #p8b_stars.p8c_WARNING
            bne  _next_star
+           lda  p8b_stars.p8v_col,x
            sec
            sbc  p8b_demo.p8v_pcol
            clc
            adc  #p8b_demo.p8c_NEAR_TILES
            cmp  #p8b_demo.p8c_NEAR_TILES * 2 + 1
            bcs  _next_star
            lda  p8b_stars.p8v_row,x
            sec
            sbc  p8b_demo.p8v_prow
            clc
            adc  #p8b_demo.p8c_NEAR_TILES
            cmp  #p8b_demo.p8c_NEAR_TILES * 2 + 1
            bcs  _next_star
            txa
            sta  p8b_demo.p8v_near_list,y
            iny
            cpy  #p8b_demo.p8c_MAX_NEAR
            beq  _done
_next_star
            inx
            bne  _star
_blasts
            ldx  #0
_blast
            lda  p8b_explode.p8v_timer,x
            beq  _next_blast
            lda  p8b_explode.p8v_col,x
            sec
            sbc  p8b_demo.p8v_pcol
            clc
            adc  #p8b_demo.p8c_NEAR_TILES
            cmp  #p8b_demo.p8c_NEAR_TILES * 2 + 1
            bcs  _next_blast
            lda  p8b_explode.p8v_row,x
            sec
            sbc  p8b_demo.p8v_prow
            clc
            adc  #p8b_demo.p8c_NEAR_TILES
            cmp  #p8b_demo.p8c_NEAR_TILES * 2 + 1
            bcs  _next_blast
            txa
            ora  #128
            sta  p8b_demo.p8v_near_list,y
            iny
            cpy  #p8b_demo.p8c_MAX_NEAR
            beq  _done
_next_blast
            inx
            cpx  #p8b_explode.p8c_MAX
            bne  _blast
_done
            sty  p8b_demo.p8v_n_near
            rts
        }}
    }

    sub threat(uword cx, ubyte cy, ubyte reach) {
        ; A threat closer than `reach` pushes the flee direction away from it, harder the closer it is.
        ubyte d = dist(cx, cy)
        if d >= reach
            return
        ubyte u = reach - d
        if u > urgency
            urgency = u
        ubyte b = dir_bits()            ; towards it, from the dist() above
        if b == 0
            b = input.DOWN              ; on top of it: flee up
        if b & input.LEFT != 0
            wx += u as word
        if b & input.RIGHT != 0
            wx -= u as word
        if b & input.UP != 0
            wy += u as word
        if b & input.DOWN != 0
            wy -= u as word
    }

    sub flee() -> ubyte {
        ; The added-up push (wx, wy) as joystick bits. Into a playfield edge: along it.
        uword ax = wx as uword
        ubyte h = input.RIGHT
        if wx < 0 {
            ax = (-wx) as uword
            h = input.LEFT
        }
        uword ay = wy as uword
        ubyte v = input.DOWN
        if wy < 0 {
            ay = (-wy) as uword
            v = input.UP
        }
        ubyte bits = 0
        if ax != 0 and ax << 1 >= ay
            bits = h
        if ay != 0 and ay << 1 >= ax
            bits |= v
        if bits == 0
            bits = input.UP             ; pushes that cancel out
        bool h_blocked = false
        bool v_blocked = false
        if (bits & input.LEFT != 0 and player.x < 2) or (bits & input.RIGHT != 0 and player.x >= player.MAX_X - 1) {
            bits &= ~(input.LEFT | input.RIGHT)
            h_blocked = true
        }
        if (bits & input.UP != 0 and player.y < 2) or (bits & input.DOWN != 0 and player.y >= player.MAX_Y - 1) {
            bits &= ~(input.UP | input.DOWN)
            v_blocked = true
        }
        if h_blocked and bits & (input.UP | input.DOWN) == 0 {
            if wy < 0 or (wy == 0 and pcy >= 96)
                bits |= input.UP
            else
                bits |= input.DOWN
        }
        if v_blocked and bits & (input.LEFT | input.RIGHT) == 0 {
            if wx < 0 or (wx == 0 and pcx >= 160)
                bits |= input.LEFT
            else
                bits |= input.RIGHT
        }
        return bits
    }

    sub scan() {
        ; The search for the next target, up to SCAN_PER_FRAME stars per frame: the nearest IDLE star with no
        ; countdown, warning or explosion on its own or a neighbouring tile. A finished pass sets the target.
        repeat SCAN_PER_FRAME {
            if scan_i >= stars.count {
                target = scan_best
                scan_i = 0
                scan_best = 255
                scan_best_d = 255
            }
            ubyte i = scan_i
            scan_i++
            if stars.state[i] == stars.IDLE {
                ubyte d = dist(((stars.col[i] as uword) << 4) + 8, (stars.row[i] << 4) + 8)
                if d <= scan_best_d {
                    if safe_spot(stars.col[i], stars.row[i]) {
                        scan_best_d = d
                        scan_best = i
                    }
                    break                       ; frame time: one tile check per frame
                }
            }
        }
    }

    sub safe_spot(ubyte c, ubyte r) -> bool {
        ; No explosion over tile (c, r) or its 8 neighbours, and no countdown or warning star on them.
        ubyte c0 = c
        if c0 != 0
            c0--
        ubyte c1 = c
        if c1 != video.MAP_W - 1
            c1++
        ubyte r0 = r
        if r0 != 0
            r0--
        ubyte r1 = r
        if r1 != video.MAP_H - 1
            r1++
        ubyte rr
        for rr in r0 to r1 {
            ubyte idx = video.row_start[rr]
            idx += c0
            repeat c1 - c0 + 1 {
                if explode.cover[idx] != 0
                    return false
                ubyte t = video.tiles[idx]
                if t != 0 {
                    ubyte s = stars.state[t - 1]
                    if s == stars.COUNTDOWN or s == stars.WARNING
                        return false
                }
                idx++
            }
        }
        return true
    }

    asmsub dist(uword cx @AY, ubyte cy @X) -> ubyte @A {
        ; From the player's centre (pcx, pcy) to (cx, cy): the longer axis plus half the shorter, 255 at most.
        ; Also leaves the distance along each axis (255 at most) in d_ax, d_ay and the direction in d_left, d_up,
        ; for dir_bits().
        %asm {{
            sec
            sbc  p8b_demo.p8v_pcx
            sta  p8b_demo.p8v_d_ax
            tya
            sbc  p8b_demo.p8v_pcx+1
            ldy  #0
            bcs  +                      ; cx >= pcx: A is the high byte
            iny                         ; to the left: negate the 16-bit difference
            eor  #255
            sta  P8ZP_SCRATCH_B1
            lda  p8b_demo.p8v_d_ax
            eor  #255
            clc
            adc  #1
            sta  p8b_demo.p8v_d_ax
            lda  P8ZP_SCRATCH_B1
            adc  #0
+           sty  p8b_demo.p8v_d_left
            cmp  #0
            beq  +
            lda  #255                   ; 256 or more apart
            sta  p8b_demo.p8v_d_ax
+           ldy  #0
            txa
            sec
            sbc  p8b_demo.p8v_pcy
            bcs  +
            iny                         ; above: negate
            eor  #255
            adc  #1                     ; carry is clear
+           sty  p8b_demo.p8v_d_up
            sta  p8b_demo.p8v_d_ay
            cmp  p8b_demo.p8v_d_ax
            bcs  +
            lsr  a                      ; x is longer: ax + ay / 2
            clc
            adc  p8b_demo.p8v_d_ax
            bcc  _done
            lda  #255
            rts
+           lda  p8b_demo.p8v_d_ax      ; y is longer: ay + ax / 2
            lsr  a
            clc
            adc  p8b_demo.p8v_d_ay
            bcc  _done
            lda  #255
_done
            rts
        }}
    }

    sub dir_bits() -> ubyte {
        ; Joystick bits towards the point of the last dist(), nearest of 8 directions: an axis counts when it is
        ; at least half the other (as player.bounce).
        ubyte bits = 0
        if d_ax != 0 and (d_ax as uword) << 1 >= d_ay {
            bits = input.RIGHT
            if d_left
                bits = input.LEFT
        }
        if d_ay != 0 and (d_ay as uword) << 1 >= d_ax {
            if d_up
                bits |= input.UP
            else
                bits |= input.DOWN
        }
        return bits
    }

    sub toward(uword cx, ubyte cy) -> ubyte {
        void dist(cx, cy)
        return dir_bits()
    }

    ; ---- self-test 40 ----

    sub death_readout() {
        pcx = player.x + player.BOX / 2
        pcy = player.y + player.BOX / 2
        die_blast = 255
        die_host = 255
        ubyte i
        for i in 0 to explode.MAX - 1 {
            if explode.timer[i] != 0
                die_blast = min(die_blast, dist(explode.core_x[i], explode.core_y[i]))
        }
        for i in 0 to hostiles.MAX - 1 {
            if hostiles.state[i] == hostiles.CHASE
                die_host = min(die_host, dist(hostiles.x[i] + hostiles.BOX / 2, hostiles.y[i] + hostiles.BOX / 2))
        }
    }

    const bool FREEZE_AT_DEATH = false  ; self-test 40: stop at the first death, pilot state on the HUD row

    sub freeze() {
        ; HUD row: hold frames left, held dir | reacting | urgency | knockback, boost,
        ; cooldown | player x, y | game number
        player.draw()
        hostiles.draw()
        sys.memset(video.SCREEN, 40, video.CHAR_SPACE)
        main.hex_byte(0, hold_left)
        main.hex_byte(2, hold_dir)
        main.hex_digit(5, reacting as ubyte)
        main.hex_byte(8, urgency)
        main.hex_byte(13, player.knock_left)
        main.hex_byte(15, player.boost_left)
        main.hex_byte(17, player.cooldown)
        main.hex_word(20, player.x)
        main.hex_byte(24, player.y)
        main.hex_byte(27, last_dir)
        main.hex_word(30, wx as uword)
        main.hex_word(35, wy as uword)
        ; row 24: the nearby threats (star index, or explosion slot + $80), their tile and distance
        uword r = 24 * 40
        sys.memset(video.SCREEN + r, 40, video.CHAR_SPACE)
        sys.memset(video.COLOR_RAM + r, 40, 1)
        main.hex_digit(r, n_near)
        ubyte k = 0
        while k < n_near {
            ubyte i = near_list[k]
            uword a = r + 2 + (k as uword) * 5
            main.hex_byte(a, i)
            if i & 128 == 0
                main.hex_byte(a + 2, dist(((stars.col[i] as uword) << 4) + 8, (stars.row[i] << 4) + 8))
            else
                main.hex_byte(a + 2, dist(explode.core_x[i & 127], explode.core_y[i & 127]))
            k++
            if k == 7
                break
        }
        repeat {
        }
    }

    sub raster_line() -> uword {
        ubyte lo
        ubyte hi
        do {
            hi = c64.SCROLY & $80
            lo = c64.RASTER
        } until hi == c64.SCROLY & $80
        return mkword(hi >> 7, lo)
    }
}
