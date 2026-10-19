; Hostile stars (spec section 7): spawn timer, steering, spin, player contact, boost hurl and its explosion,
; explosion kills. Slot i uses sprite i + 1.
; Position is the top-left of the 12x12 collision box plus a 1/16 px fraction. The box sits at pixel (4,4) of
; the sprite frame. A hostile appears with its box on the box of the star it came from (tile pixels 2-13).

%import math
%import video
%import player
%import stars
%import explode
%import score

hostiles {
    const ubyte MAX = 6
    const ubyte BOX = 12                ; collision box size [TUNE]
    const ubyte BOX_INSET = 4
    const uword MAX_X = 320 - BOX
    const ubyte MAX_Y = 192 - BOX
    const ubyte FAR = 5                 ; spawn: a star outside the 9x9 tiles around the player
    const ubyte TURN_FRAMES = 4         ; [TUNE] one heading step towards the player every 4 frames
    const ubyte SPIN_DELAY = 3          ; [TUNE] game frames per picture (1 while hurled)
    const ubyte SPIN_FRAMES = 6
    const ubyte COLOR = 2               ; red
    const ubyte FRAME_0 = assets.SPR_HOSTILE_0      ; first spin frame (for the assembly in draw())
    ; [TUNE] hurl: 6 px/f for 16 frames (96 px)
    const byte HURL_SPEED = 96
    const byte HURL_DIAG = 68
    const ubyte HURL_FRAMES = 16
    const ubyte HURL_FREE_FRAMES = 8    ; [TUNE] flies through hostiles for the first 8 frames (48 px)
    const ubyte OFF_FRAMES = 7          ; at a playfield edge it flies on this long, out of sight, then is gone
    ; [TUNE] respawn push (spec section 8): hostiles whose centre is inside the box around the playfield centre
    ; (px 160, py 96), 80 px left and right and 64 px up and down, fly straight out at 6 px/f until outside it
    const byte PUSH_SPEED = 96
    const ubyte PUSH_HALF_W = 80
    const ubyte PUSH_HALF_H = 64

    ; slot states
    const ubyte FREE = 0
    const ubyte CHASE = 1
    const ubyte HURLED = 2

    ; [TUNE] speed per galaxy 1-21 (then it stays at 29), 1/16 px per frame
    ; galaxy 1 = 50% of the player's 24, galaxy 21 = 120%, linear (designer, 2026-10-18: was galaxy 11)
    ubyte[21] galaxy_speed = [12, 13, 14, 15, 15, 16, 17, 18, 19, 20, 20, 21, 22, 23, 24, 25, 25, 26, 27, 28, 29]
    ; cos of the 16 headings x 127. Heading 0 = right, counting clockwise on screen (4 = down).
    byte[16] cos16 = [127, 117, 90, 49, 0, -49, -90, -117, -127, -117, -90, -49, 0, 49, 90, 117]
    byte[16] head_vx                    ; built at galaxy start from the speed
    byte[16] head_vy
    byte[16] push_vx                    ; the 16 headings at PUSH_SPEED
    byte[16] push_vy

    uword[MAX] x
    ubyte[MAX] y
    ubyte[MAX] x_frac
    ubyte[MAX] y_frac
    ubyte[MAX] state
    ubyte[MAX] heading                  ; 0-15
    bool[MAX] pushing                   ; CHASE: being pushed out of the respawn box
    ubyte[MAX] push_dir                 ; heading of the push
    ubyte[MAX] flight                   ; HURLED: frames of flight left
    ubyte[MAX] off_edge                 ; HURLED: frames left flying off the playfield (no explosion)
    byte[MAX] hurl_vx
    byte[MAX] hurl_vy
    ubyte[MAX] anim_frame
    ubyte[MAX] anim_timer
    bool[MAX] spin_ccw
    ubyte used                          ; slots not FREE
    ubyte flying                        ; HURLED slots
    uword interval                      ; spawn interval in frames
    uword spawn_timer                   ; frames to the next spawn; at 0 it waits for a free slot
    ubyte turn_clock
    bool @shared move_edge              ; move(): result

    ; debug readouts
    ubyte spawned                       ; warnings started
    ubyte kills                         ; hostiles destroyed (hurls and explosions)
    ubyte blasts                        ; hurl explosions
    ubyte pushes                        ; respawn pushes started
    uword hurl_x                        ; box x at the last hurl
    uword blast_x                       ; box x where the last hurled hostile exploded

    sub start_galaxy(ubyte g) {
        ubyte i
        for i in 0 to MAX - 1 {
            state[i] = FREE
            video.hide_sprite(i + 1)
        }
        used = 0
        flying = 0
        ; max(50, 300 - 12.5 * (g - 1)) frames: 6 s in galaxy 1, a quarter second less per galaxy, 1 s from
        ; galaxy 21 on (rounded up to whole frames)
        interval = 50
        if g < 21
            interval = 300 - ((((g - 1) as uword) * 25) >> 1)
        spawn_timer = interval
        if g > len(galaxy_speed)
            g = len(galaxy_speed)
        set_speed(galaxy_speed[g - 1])
        ubyte d
        for d in 0 to 15 {
            push_vx[d] = scale(PUSH_SPEED as ubyte, cos16[d])
            push_vy[d] = scale(PUSH_SPEED as ubyte, cos16[(d - 4) & 15])
        }
    }

    sub set_speed(ubyte speed) {
        ; Velocity table for the 16 headings (galaxy start, so multiply and divide are fine here).
        ubyte d
        for d in 0 to 15 {
            head_vx[d] = scale(speed, cos16[d])
            head_vy[d] = scale(speed, cos16[(d - 4) & 15])      ; sin = cos 90 degrees earlier
        }
    }

    sub scale(ubyte speed, byte c) -> byte {
        ; speed * c / 127, rounded
        ubyte m = c as ubyte
        if c < 0
            m = (-c) as ubyte
        byte v = lsb(((speed as uword) * m + 63) / 127) as byte
        if c < 0
            return -v
        return v
    }

    ; ---- per frame ----

    sub update() {
        ; Spawn timer, then every hostile moves: chasing ones steer, hurled ones fly and may explode.
        spawn()
        turn_clock++
        ubyte i
        if player.safe == 0 {
            for i in 0 to MAX - 1 {
                when state[i] {
                    CHASE -> chase(i)
                    HURLED -> fly(i)
                }
            }
        } else {
            for i in 0 to MAX - 1 {
                when state[i] {
                    CHASE -> chase_safe(i)
                    HURLED -> fly(i)
                }
            }
        }
    }

    sub spawn() {
        if spawn_timer != 0 {
            spawn_timer--
            if spawn_timer != 0
                return
        }
        if used + stars.warnings >= MAX
            return
        ubyte s = stars.pick_hostile()
        if s == 255
            return
        stars.start_warning(s)
        spawned++
        spawn_timer = interval
    }

    sub appear(ubyte c, ubyte r) {
        ; Called by stars when a warning ends. A slot is free: warnings count towards MAX.
        ubyte i
        for i in 0 to MAX - 1 {
            if state[i] == FREE {
                x[i] = ((c as uword) << 4) + 2
                y[i] = (r << 4) + 2
                x_frac[i] = 0
                y_frac[i] = 0
                heading[i] = aim(i)
                pushing[i] = false
                anim_frame[i] = 0
                anim_timer[i] = 0
                spin_ccw[i] = false
                state[i] = CHASE
                used++
                return
            }
        }
    }

    sub chase(ubyte i) {
        ; Turns are spread over the 4 frames by slot number.
        if (turn_clock + i) & (TURN_FRAMES - 1) == 0
            turn(i)
        byte vx = head_vx[heading[i]]
        void move(i, vx, head_vy[heading[i]])
        if vx < 0
            spin_ccw[i] = true
        else if vx > 0
            spin_ccw[i] = false
        spin(i, SPIN_DELAY)
    }

    sub chase_safe(ubyte i) {
        ; Instead of chase() while the player is safe after reappearing: a hostile being pushed out of the
        ; respawn box flies on (the push ends well within the safe time), the others hold still, still turning
        ; towards the player. A separate routine, so normal frames pay nothing for it.
        if pushing[i] {
            byte vx = push_vx[push_dir[i]]
            if move(i, vx, push_vy[push_dir[i]]) or not in_push_box(i)
                pushing[i] = false
            if vx < 0
                spin_ccw[i] = true
            else if vx > 0
                spin_ccw[i] = false
        } else if (turn_clock + i) & (TURN_FRAMES - 1) == 0
            turn(i)
        spin(i, SPIN_DELAY)
    }

    sub push_out() {
        ; The player has just reappeared in the centre: chasing hostiles in the box start their push, straight
        ; away from the player (who is at the centre).
        ubyte i
        for i in 0 to MAX - 1 {
            if state[i] == CHASE and in_push_box(i) {
                pushing[i] = true
                push_dir[i] = (aim(i) + 8) & 15
                pushes++
            }
        }
    }

    sub in_push_box(ubyte i) -> bool {
        ; The hostile's centre (box + 6) strictly inside the respawn box.
        uword cx = x[i] + 6
        ubyte cy = y[i] + 6
        return cx > 160 - PUSH_HALF_W and cx < 160 + PUSH_HALF_W and cy > 96 - PUSH_HALF_H and cy < 96 + PUSH_HALF_H
    }

    sub turn(ubyte i) {
        ; One step towards the player's direction, the shorter way round (clockwise when exactly behind).
        ubyte d = (aim(i) - heading[i]) & 15
        if d == 0
            return
        if d <= 8
            heading[i] = (heading[i] + 1) & 15
        else
            heading[i] = (heading[i] - 1) & 15
    }

    sub aim(ubyte i) -> ubyte {
        ; Heading (0-15) from this hostile to the player. Both boxes have their centre 6 px in, so the
        ; top-left corners give the direction.
        uword ax
        bool left = player.x < x[i]
        if left
            ax = x[i] - player.x
        else
            ax = player.x - x[i]
        ubyte ay
        bool up = player.y < y[i]
        if up
            ay = y[i] - player.y
        else
            ay = player.y - y[i]
        ; angle from the x axis in 22.5 degree steps; boundaries at tan 11.25, 33.75, 56.25, 78.75 degrees
        ; (about 1/5, 2/3, 3/2, 5)
        uword ay_w = ay
        ubyte step = 4
        if (ay_w << 2) + ay_w < ax
            step = 0
        else if (ay_w << 1) + ay_w < ax << 1
            step = 1
        else if ay_w << 1 < (ax << 1) + ax
            step = 2
        else if ay_w < (ax << 2) + ax
            step = 3
        if left
            step = 8 - step
        if up
            step = (16 - step) & 15
        return step
    }

    asmsub move(ubyte i @X, byte vx @A, byte vy @Y) clobbers(X, Y) -> bool @A {
        ; Slot X moves by vx, vy (1/16 px), clamped to the playfield as player.move does. Returns true when the
        ; box is at an edge it moved towards. Assembly: called up to 6 times per frame.
        %asm {{
_t = P8ZP_SCRATCH_B1
_vy = P8ZP_SCRATCH_REG
            sty  _vy
            ldy  #0
            sty  p8b_hostiles.p8v_move_edge
            ; ---- x: t = frac + vx, keep t & 15, move t >> 4 (arithmetic) pixels ----
            clc
            adc  p8b_hostiles.p8v_x_frac,x
            sta  _t
            and  #15
            sta  p8b_hostiles.p8v_x_frac,x
            lda  _t
            cmp  #$80
            ror  a
            cmp  #$80
            ror  a
            cmp  #$80
            ror  a
            cmp  #$80
            ror  a
            beq  _y
            bmi  _x_neg
            clc
            adc  p8b_hostiles.p8v_x_lsb,x
            sta  p8b_hostiles.p8v_x_lsb,x
            bcc  +
            inc  p8b_hostiles.p8v_x_msb,x
+           lda  p8b_hostiles.p8v_x_lsb,x
            cmp  #<p8b_hostiles.p8c_MAX_X
            lda  p8b_hostiles.p8v_x_msb,x
            sbc  #>p8b_hostiles.p8c_MAX_X
            bcc  _y
            lda  #<p8b_hostiles.p8c_MAX_X
            sta  p8b_hostiles.p8v_x_lsb,x
            lda  #>p8b_hostiles.p8c_MAX_X
            sta  p8b_hostiles.p8v_x_msb,x
            jmp  _x_stop
_x_neg
            clc
            adc  p8b_hostiles.p8v_x_lsb,x
            sta  p8b_hostiles.p8v_x_lsb,x
            lda  p8b_hostiles.p8v_x_msb,x
            adc  #$ff
            sta  p8b_hostiles.p8v_x_msb,x
            bmi  _x_zero
            ora  p8b_hostiles.p8v_x_lsb,x
            bne  _y
_x_zero
            lda  #0
            sta  p8b_hostiles.p8v_x_lsb,x
            sta  p8b_hostiles.p8v_x_msb,x
_x_stop
            lda  #0
            sta  p8b_hostiles.p8v_x_frac,x
            lda  #1
            sta  p8b_hostiles.p8v_move_edge
            ; ---- y, the same with a byte coordinate ----
_y
            lda  _vy
            clc
            adc  p8b_hostiles.p8v_y_frac,x
            sta  _t
            and  #15
            sta  p8b_hostiles.p8v_y_frac,x
            lda  _t
            cmp  #$80
            ror  a
            cmp  #$80
            ror  a
            cmp  #$80
            ror  a
            cmp  #$80
            ror  a
            beq  _done
            bmi  _y_neg
            clc
            adc  p8b_hostiles.p8v_y,x
            cmp  #p8b_hostiles.p8c_MAX_Y
            bcs  _y_max
            sta  p8b_hostiles.p8v_y,x
            jmp  _done
_y_max
            lda  #p8b_hostiles.p8c_MAX_Y
            sta  p8b_hostiles.p8v_y,x
            jmp  _y_stop
_y_neg
            ; y + (256 - n): carry set when y >= n
            clc
            adc  p8b_hostiles.p8v_y,x
            bcc  _y_zero
            beq  _y_zero
            sta  p8b_hostiles.p8v_y,x
            jmp  _done
_y_zero
            lda  #0
            sta  p8b_hostiles.p8v_y,x
_y_stop
            lda  #0
            sta  p8b_hostiles.p8v_y_frac,x
            lda  #1
            sta  p8b_hostiles.p8v_move_edge
_done
            lda  p8b_hostiles.p8v_move_edge
            rts
        }}
    }

    sub spin(ubyte i, ubyte delay) {
        ; Clockwise plays the frames forward.
        anim_timer[i]++
        if anim_timer[i] < delay
            return
        anim_timer[i] = 0
        if spin_ccw[i] {
            if anim_frame[i] == 0
                anim_frame[i] = SPIN_FRAMES
            anim_frame[i]--
        } else {
            anim_frame[i]++
            if anim_frame[i] == SPIN_FRAMES
                anim_frame[i] = 0
        }
    }

    ; ---- hurl (spec section 7) ----

    sub check_player() {
        ; Player box against each chasing hostile: destroyed by the invincible player, hurled while boosting
        ; (also while safe), else a lost life unless the player is safe. Nothing while the player is dying.
        if player.dying != 0
            return
        ubyte i
        for i in 0 to MAX - 1 {
            if state[i] == CHASE and player.x < x[i] + BOX and x[i] < player.x + player.BOX
                    and player.y < y[i] + BOX and y[i] < player.y + player.BOX {
                if player.invincible != 0 {
                    free(i)
                    sound.play(sound.HURL)
                    destroyed()
                } else if player.boosted
                    hurl(i)
                else if player.hurtable()
                    player.hurt()
            }
        }
    }

    sub hurl(ubyte i) {
        ; Direction: the player's movement, or straight away from the player when they aren't moving.
        ; Nearest of 8 directions: an axis counts when it is at least half the other (as player.bounce).
        byte dx = player.vx
        byte dy = player.vy
        if dx == 0 and dy == 0 {
            ; centre to centre (same 6 px inset); the boxes touch, so the difference fits a byte
            dx = (lsb(x[i]) - lsb(player.x)) as byte
            dy = (y[i] - player.y) as byte
        }
        ubyte ax = dx as ubyte
        if dx < 0
            ax = (-dx) as ubyte
        ubyte ay = dy as ubyte
        if dy < 0
            ay = (-dy) as ubyte
        bool use_x = ax << 1 > ay
        bool use_y = ay << 1 > ax
        byte speed = HURL_SPEED
        if use_x and use_y
            speed = HURL_DIAG
        hurl_vx[i] = 0
        hurl_vy[i] = 0
        if use_x {
            hurl_vx[i] = speed
            if dx < 0
                hurl_vx[i] = -speed
        }
        if use_y {
            hurl_vy[i] = speed
            if dy < 0
                hurl_vy[i] = -speed
        }
        if not use_x and not use_y
            hurl_vx[i] = HURL_SPEED     ; dead centre: to the right
        state[i] = HURLED
        flight[i] = HURL_FRAMES
        off_edge[i] = 0
        flying++
        hurl_x = x[i]
        ; the player bounces straight back, opposite the hurl, as off a stationary star
        player.bounce(-hurl_vx[i], -hurl_vy[i])
        sound.play(sound.HURL)
        destroyed()
    }

    sub fly(ubyte i) {
        ; A hurled hostile is harmless and can't be hit. It flies through stationary stars, and through hostiles
        ; for the first HURL_FREE_FRAMES; after that it explodes on touching a chasing hostile. Otherwise it
        ; explodes at the end of the flight. At a playfield edge it flies on off the screen and is gone with no
        ; explosion (its kill was scored at the hurl).
        ; Frame time: when an explosion already started this frame, it waits in place for the next frame.
        if off_edge[i] != 0 {
            ; whole pixels, no clamp: the coordinates wrap a little past the edges, where the border hides it
            x[i] += ((hurl_vx[i] >> 4) as word) as uword
            y[i] += (hurl_vy[i] >> 4) as ubyte
            spin(i, 1)
            off_edge[i]--
            if off_edge[i] == 0 {
                free(i)
                flying--
            }
            return
        }
        if flight[i] != 0 {
            bool edge = move(i, hurl_vx[i], hurl_vy[i])
            spin(i, 1)
            flight[i]--
            if edge {
                off_edge[i] = OFF_FRAMES
                return
            }
            if flight[i] <= HURL_FRAMES - HURL_FREE_FRAMES and touches_hostile(i)
                flight[i] = 0
        }
        if flight[i] == 0 and explode.starts == 0
            blast(i)
    }

    sub touches_hostile(ubyte i) -> bool {
        ; Boxes of equal size overlap when both corner differences are in -11..11 (unsigned: d + 11 < 23).
        uword hx = x[i]
        ubyte hy = y[i]
        ubyte j
        for j in 0 to MAX - 1 {
            if state[j] == CHASE {
                ubyte dy = hy - y[j]
                if dy + BOX - 1 < BOX * 2 - 1 {
                    uword dx = hx - x[j]
                    if dx + BOX - 1 < BOX * 2 - 1
                        return true
                }
            }
        }
        return false
    }

    sub blast(ubyte i) {
        ; A normal explosion on the tile under the box centre. Not a supernova: no points of its own.
        free(i)
        flying--
        blasts++
        sound.play(sound.SUPERNOVA)     ; the same explosion sound
        blast_x = x[i]
        explode.start(lsb((x[i] + 6) >> 4), (y[i] + 6) >> 4)
    }

    ; ---- kills ----

    sub check_explosions() {
        ; Chasing hostiles whose centre is in a running explosion's core are destroyed.
        if explode.live == 0
            return
        repeat {
            ubyte i = explosion_hit()
            if i == 255
                break
            free(i)
            destroyed()
        }
    }

    asmsub explosion_hit() clobbers(X, Y) -> ubyte @A {
        ; The first chasing hostile whose centre is in a running explosion's core (explode.hits), or 255.
        ; Assembly: up to 6 hostiles x 8 explosions every frame.
        %asm {{
            ldx  #0
_slot
            lda  p8b_hostiles.p8v_state,x
            cmp  #p8b_hostiles.p8c_CHASE
            bne  _next
            ; centre of the box: x + 6, y + 6
            lda  p8b_hostiles.p8v_x_lsb,x
            clc
            adc  #p8b_hostiles.p8c_BOX / 2
            sta  p8b_explode.p8v_obj_x
            lda  p8b_hostiles.p8v_x_msb,x
            adc  #0
            sta  p8b_explode.p8v_obj_x+1
            lda  p8b_hostiles.p8v_y,x
            clc
            adc  #p8b_hostiles.p8c_BOX / 2
            sta  p8b_explode.p8v_obj_y
            ldy  #p8b_explode.p8c_MAX - 1
_expl
            lda  p8b_explode.p8v_timer,y
            beq  _nexpl
            jsr  p8b_explode.p8s_hits
            bcc  _nexpl
            txa
            rts
_nexpl
            dey
            bpl  _expl
_next
            inx
            cpx  #p8b_hostiles.p8c_MAX
            bne  _slot
            lda  #255
            rts
        }}
    }

    sub destroyed() {
        ; A hostile hurled or killed: the next chain step, and one star fewer to clear.
        stars.left--
        kills++
        score.chain_kill()
    }

    sub free(ubyte i) {
        state[i] = FREE
        used--
        video.hide_sprite(i + 1)
    }

    asmsub draw() clobbers(A, X, Y) {
        ; Sprite shadows of the hostiles in use (sprite = slot + 1), as video.set_sprite does: the frame starts
        ; BOX_INSET px up and left of the box, hardware x = px + 24, y = py + 58. FREE slots were hidden by free().
        ; Assembly: video.set_sprite costs about 250 cycles a call.
        %asm {{
            ldx  #0
_slot
            lda  p8b_hostiles.p8v_state,x
            beq  _next
            ldy  _sprite,x
            lda  p8b_hostiles.p8v_anim_frame,x
            clc
            adc  #p8b_hostiles.p8c_FRAME_0
            sta  p8b_video.p8v_spr_ptr,y
            lda  #p8b_hostiles.p8c_COLOR
            sta  p8b_video.p8v_spr_col,y
            lda  p8b_hostiles.p8v_y,x
            clc
            adc  #58 - p8b_hostiles.p8c_BOX_INSET
            sta  p8b_video.p8v_spr_y,y
            lda  p8b_hostiles.p8v_x_lsb,x
            clc
            adc  #24 - p8b_hostiles.p8c_BOX_INSET
            sta  p8b_video.p8v_spr_x,y
            lda  p8b_hostiles.p8v_x_msb,x
            adc  #0
            beq  _low
            lda  p8b_video.p8v_spr_msb
            ora  p8b_video.p8v_sprite_bit,y
            sta  p8b_video.p8v_spr_msb
            jmp  _enable
_low
            lda  p8b_video.p8v_sprite_bit,y
            eor  #255
            and  p8b_video.p8v_spr_msb
            sta  p8b_video.p8v_spr_msb
_enable
            lda  p8b_video.p8v_spr_ena
            ora  p8b_video.p8v_sprite_bit,y
            sta  p8b_video.p8v_spr_ena
_next
            inx
            cpx  #p8b_hostiles.p8c_MAX
            bne  _slot
            rts
_sprite
            .byte  1, 2, 3, 4, 5, 6
            ; !notreached!
        }}
    }
}
