; Player (spec section 5). Phase 2: 8-direction movement, boost with cooldown, playfield clamp, spin
; animation and boost glow.
; Position is the top-left of the 13x13 collision box in playfield pixels plus a 1/16 px fraction.
; The box sits at pixel (4,4) of the 24x21 sprite frame (centred in the 21x21 art).

%import input
%import video

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

    ; [TUNE] animation
    const ubyte SPIN_FRAMES = 6
    const ubyte SPIN_DELAY = 3          ; game frames per picture at normal speed (1 while boosting)
    const ubyte COLOR = 7               ; yellow
    ubyte[4] glow_colors = [1, 7, 8, 7] ; boost glow: white, yellow, orange, yellow, every 2 frames

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
    }

    sub update() {
        if input.pressed & input.FIRE != 0 and boost_left == 0 and cooldown == 0 {
            boost_left = BOOST_FRAMES
            boosts++
        }

        ubyte dir = input.held & %1111
        byte vx = dir_vx[dir]
        byte vy = dir_vy[dir]
        if boost_left != 0 {
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

        color = COLOR
        if boost_left != 0 {
            color = glow_colors[(boost_left >> 1) & 3]
            boost_left--
            if boost_left == 0
                cooldown = COOLDOWN_FRAMES
        } else if cooldown != 0
            cooldown--
    }

    sub move(byte vx, byte vy) {
        ; frac + speed: the whole pixels (arithmetic shift, so negative sums step left/up) and the new fraction
        byte t = (x_frac as byte) + vx
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

        t = (y_frac as byte) + vy
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
        if boost_left == 0 and anim_timer < SPIN_DELAY
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
        ; in set_sprite still gives the right hardware position.
        video.set_sprite(0, assets.SPR_PLAYER_0 + anim_frame, color, x - BOX_INSET, y - BOX_INSET)
    }
}
