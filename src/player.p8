; Player (spec section 5): 8-direction movement, boost with cooldown, playfield clamp, spin animation,
; boost glow, the knockback after hitting a star (spec section 6), and losing a life: the death effect,
; respawn in the centre and the safe time (spec section 8), and invincibility after a quasar pickup (spec section 9).
; Position is the top-left of the 13x13 collision box in playfield pixels plus a 1/16 px fraction.
; The box sits at pixel (4,4) of the 24x21 sprite frame (centred in the 21x21 art).

%import input
%import video
%import score
%import hostiles

player {
    const ubyte BOX = 13                ; collision box size [TUNE]
    const ubyte BOX_INSET = 4           ; box offset inside the sprite frame
    const uword MAX_X = 320 - BOX       ; box clamped to the playfield
    const ubyte MAX_Y = 192 - BOX
    ; start: art centre (frame pixel 10,10) on the playfield centre px 160, py 96
    const uword START_X = 160 - 10 + BOX_INSET
    const ubyte START_Y = 96 - 10 + BOX_INSET

    ; [TUNE] speeds in 1/16 px per frame; diagonals are each axis at 181/256
    const byte SPEED = 24
    const byte SPEED_DIAG = 17
    const byte BOOST_SPEED = 60
    const byte BOOST_DIAG = 42
    const ubyte BOOST_FRAMES = 75
    const ubyte COOLDOWN_FRAMES = 25
    ; [TUNE] knockback after hitting a star: 3 px/f for 6 frames, no joystick control
    const byte KNOCK_SPEED = 48
    const byte KNOCK_DIAG = 34
    const ubyte KNOCK_FRAMES = 6

    ; [TUNE] animation
    const ubyte SPIN_FRAMES = 6
    const ubyte SPIN_DELAY = 3          ; game frames per picture at normal speed (1 while boosting)
    const ubyte COLOR = 7               ; yellow
    ubyte[4] glow_colors = [1, 7, 8, 7] ; boost glow: white, yellow, orange, yellow, every 2 frames
    ; losing a life (spec section 8)
    const ubyte DIE_FRAMES = 50         ; 1 s death effect, the player stays where it was hit
    const ubyte SAFE_FRAMES = 100       ; 2 s after reappearing: hostiles and explosions can't hurt
    const ubyte SAFE_BLINK = 4          ; [TUNE] the sprite is shown 4 frames, hidden 4
    ; death effect: the sprite flashes through these, one every 2 frames, spinning fast at full size for the first
    ; 20 frames, then shrinks away in 3 steps of 10 frames (SPR_DIE_0-2) [TUNE]
    ubyte[4] die_colors = [1, 2, 7, 0]
    const ubyte SHRINK_START = 30
    ; invincibility (spec section 9): 8 s; the color cycles every 2 frames, every 8 in the last second [TUNE]
    const uword INVINCIBLE_FRAMES = 400
    const ubyte INVINCIBLE_SECS = INVINCIBLE_FRAMES / 50    ; HUD countdown
    const ubyte INVINCIBLE_SLOW = 50
    ; [art phase] white, yellow, light green, cyan, light blue, purple, light red, orange
    ubyte[8] invincible_colors = [1, 7, 13, 3, 14, 4, 10, 8]

    ; joystick bits (input.UP/DOWN/LEFT/RIGHT = bits 0-3) -> axis speeds. Opposite directions cancel.
    byte[16] dir_vx = [0, 0, 0, 0, -SPEED, -SPEED_DIAG, -SPEED_DIAG, -SPEED,
                       SPEED, SPEED_DIAG, SPEED_DIAG, SPEED, 0, 0, 0, 0]
    byte[16] dir_vy = [0, -SPEED, SPEED, 0, 0, -SPEED_DIAG, SPEED_DIAG, 0,
                       0, -SPEED_DIAG, SPEED_DIAG, 0, 0, -SPEED, SPEED, 0]
    byte[16] boost_vx = [0, 0, 0, 0, -BOOST_SPEED, -BOOST_DIAG, -BOOST_DIAG, -BOOST_SPEED,
                         BOOST_SPEED, BOOST_DIAG, BOOST_DIAG, BOOST_SPEED, 0, 0, 0, 0]
    byte[16] boost_vy = [0, -BOOST_SPEED, BOOST_SPEED, 0, 0, -BOOST_DIAG, BOOST_DIAG, 0,
                         0, -BOOST_DIAG, BOOST_DIAG, 0, 0, -BOOST_SPEED, BOOST_SPEED, 0]

    uword x
    ubyte y
    ubyte x_frac
    ubyte y_frac
    ubyte boost_left                    ; frames of boost left, 0 = not boosting
    ubyte cooldown                      ; frames before the next boost is allowed
    ubyte anim_frame                    ; 0 to SPIN_FRAMES - 1
    ubyte anim_timer
    bool spin_ccw                       ; false = clockwise (the start direction)
    ubyte color
    ubyte boosts                        ; boosts started (debug readout)
    ubyte knock_left                    ; knockback frames left
    ubyte knock_star                    ; the star that started the knockback (255: a hurled hostile)
    byte knock_vx
    byte knock_vy
    ubyte bounces                       ; bounces started (debug readout)
    byte vx                             ; speed moved with this frame (hostile hurl direction)
    byte vy
    bool boosted                        ; the boost was running this frame (hits and hurls count as boosted)
    ubyte dying                         ; frames of the death effect left; no control or contacts meanwhile
    ubyte safe                          ; frames of safety left after reappearing
    bool gone                           ; the death effect ended with no lives left: game over
    ubyte deaths                        ; lives lost (debug readout)
    ubyte respawns                      ; times reappeared (debug readout and self-test hooks)
    uword invincible                    ; frames of invincibility left
    ubyte inv_secs                      ; seconds left, shown on the HUD (8 down to 1)
    ubyte inv_frames                    ; frames left in the current second

    sub init() {
        x = START_X
        y = START_Y
        x_frac = 0
        y_frac = 0
        boost_left = 0
        cooldown = 0
        anim_frame = 0
        anim_timer = 0
        spin_ccw = false
        color = COLOR
        knock_left = 0
        vx = 0
        vy = 0
        boosted = false
        dying = 0
        safe = 0
        gone = false
        invincible = 0
        inv_secs = 0
        video.hud_invincible(0)
    }

    sub make_invincible() {
        ; Quasar pickup. A running boost, its cooldown and a knockback end: control is back at once, and fire
        ; works again as soon as the invincibility ends.
        invincible = INVINCIBLE_FRAMES
        inv_secs = INVINCIBLE_SECS
        inv_frames = 50
        video.hud_invincible(inv_secs)
        boost_left = 0
        cooldown = 0
        knock_left = 0
    }

    sub hurt() {
        ; Touched by a hostile or caught in an explosion: a life lost, the death effect starts.
        score.lose_life()
        sound.play(sound.LIFE_LOST)
        deaths++
        dying = DIE_FRAMES
        boost_left = 0
        cooldown = 0
        knock_left = 0
        vx = 0
        vy = 0
        boosted = false
    }

    sub hurtable() -> bool {
        if main.NO_DEATH
            return false
        return dying == 0 and safe == 0 and invincible == 0
    }

    sub update() {
        if dying != 0 {
            ; the death effect plays where the player was hit; then the centre, or game over
            dying--
            color = die_colors[(dying >> 1) & 3]
            anim_timer = SPIN_DELAY     ; fast spin: a picture every frame
            spin()
            if dying == 0 {
                if score.lives == 0
                    gone = true
                else {
                    init()
                    safe = SAFE_FRAMES
                    respawns++
                    hostiles.push_out()
                }
            }
            return
        }
        if safe != 0
            safe--
        if knock_left != 0 {
            ; knockback: no joystick control (fire presses are ignored too); the boost keeps running
            knock_left--
            vx = knock_vx
            vy = knock_vy
            move(vx, vy)
            spin()
        } else {
            ; invincible: boost speed in the stick direction, fire does nothing
            if input.pressed & input.FIRE != 0 and boost_left == 0 and cooldown == 0 and invincible == 0 {
                boost_left = BOOST_FRAMES
                boosts++
                sound.play(sound.BOOST)
            }

            ubyte dir = input.held & %1111
            vx = dir_vx[dir]
            vy = dir_vy[dir]
            if boost_left != 0 or invincible != 0 {
                vx = boost_vx[dir]
                vy = boost_vy[dir]
            }
            move(vx, vy)

            if vx < 0
                spin_ccw = true
            else if vx > 0
                spin_ccw = false
            if vx != 0 or vy != 0
                spin()
        }

        color = COLOR
        boosted = boost_left != 0
        if boost_left != 0 {
            color = glow_colors[(boost_left >> 1) & 3]
            boost_left--
            if boost_left == 0
                cooldown = COOLDOWN_FRAMES
        } else if cooldown != 0
            cooldown--
        if invincible != 0 {
            ubyte glow = (lsb(invincible) >> 1) & 7
            if invincible <= INVINCIBLE_SLOW
                glow = (lsb(invincible) >> 3) & 7
            color = invincible_colors[glow]
            invincible--
            inv_frames--
            if inv_frames == 0 {
                inv_frames = 50
                inv_secs--
                video.hud_invincible(inv_secs)     ; reaches 0 (cleared) with the invincibility
            }
        }
    }

    sub bounce(byte dx, byte dy) {
        ; Knockback away from a star: dx, dy point from the star to the player. Nearest of 8 directions:
        ; an axis counts when it is at least half the other (tan 26.6 deg, close to the 22.5 deg boundary).
        ; prog8c 12.3.4 bug: "ax = dx / if dx < 0" at the start of a sub tested the flags of the caller's last
        ; load (dy), not dx, so the bounce went sideways when dx and dy had opposite signs. Written so the test
        ; needs a fresh load.
        ubyte ax = (-dx) as ubyte
        if dx >= 0
            ax = dx as ubyte
        ubyte ay = dy as ubyte
        if dy < 0
            ay = (-dy) as ubyte
        bool use_x = ax << 1 > ay
        bool use_y = ay << 1 > ax
        byte speed = KNOCK_SPEED
        if use_x and use_y
            speed = KNOCK_DIAG
        knock_vx = 0
        knock_vy = 0
        if use_x {
            knock_vx = speed
            if dx < 0
                knock_vx = -speed
        }
        if use_y {
            knock_vy = speed
            if dy < 0
                knock_vy = -speed
        }
        if not use_x and not use_y
            knock_vy = -KNOCK_SPEED     ; dead centre (can't happen with boxes this size): straight up
        knock_left = KNOCK_FRAMES
        knock_star = 255                ; stars.touch() sets it after the bounce
        bounces++
    }

    sub move(byte mx, byte my) {
        ; frac + speed: the whole pixels (arithmetic shift, so negative sums step left/up) and the new fraction
        byte t = (x_frac as byte) + mx
        x_frac = (t as ubyte) & 15
        byte d = t >> 4
        if d < 0 {
            ubyte left = (-d) as ubyte
            if x < left {
                x = 0
                x_frac = 0
            } else
                x -= left
        } else if d > 0 {
            x += d as ubyte
            if x > MAX_X {
                x = MAX_X
                x_frac = 0
            }
        }

        t = (y_frac as byte) + my
        y_frac = (t as ubyte) & 15
        d = t >> 4
        if d < 0 {
            ubyte up = (-d) as ubyte
            if y < up {
                y = 0
                y_frac = 0
            } else
                y -= up
        } else if d > 0 {
            y += d as ubyte
            if y > MAX_Y {
                y = MAX_Y
                y_frac = 0
            }
        }
    }

    sub spin() {
        ; Called on frames the player moves. Clockwise plays the frames forward.
        anim_timer++
        if boost_left == 0 and invincible == 0 and anim_timer < SPIN_DELAY
            return
        anim_timer = 0
        if spin_ccw {
            if anim_frame == 0
                anim_frame = SPIN_FRAMES
            anim_frame--
        } else {
            anim_frame++
            if anim_frame == SPIN_FRAMES
                anim_frame = 0
        }
    }

    sub draw() {
        ; Sprite shadow registers. At the top/left edges the frame starts at -4: the uword/ubyte wrap-around
        ; in set_sprite still gives the right hardware position. Blinks while safe.
        if gone or (safe != 0 and (safe / SAFE_BLINK) & 1 != 0) {
            video.hide_sprite(0)
            return
        }
        ubyte frame = assets.SPR_PLAYER_0 + anim_frame
        if dying != 0 and dying <= SHRINK_START {
            frame = assets.SPR_DIE_2
            if dying > SHRINK_START - 10
                frame = assets.SPR_DIE_0
            else if dying > SHRINK_START - 20
                frame = assets.SPR_DIE_1
        }
        video.set_sprite(0, frame, color, x - BOX_INSET, y - BOX_INSET)
    }
}
