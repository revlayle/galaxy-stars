; Quasar (spec section 9): a supernova may leave one, at most once per galaxy. It appears when that supernova's
; explosion ends, burns out after 5 s (blinking in the last second), and touching it makes the player invincible
; for 8 s (player.p8). Sprite 7. Its box is a star's box: tile pixels 2-13.

%import video
%import player
%import stars
%import explode

quasar {
    const bool FORCE = false           ; debug: every supernova leaves one (still once per galaxy). Keep false.
    const bool ALWAYS = FORCE or (main.TEST >= 33 and main.TEST <= 36)
    const ubyte CHANCE = 100            ; [TUNE] 1 in 100 per supernova
    const ubyte LIFE_FRAMES = 250       ; 5 s
    const ubyte BLINK_FRAMES = 50       ; [TUNE] blinks in the last second
    const ubyte BLINK = 4               ; [TUNE] shown 4 frames, hidden 4
    const ubyte ANIM_DELAY = 4          ; [TUNE] game frames per picture
    const ubyte ANIM_FRAMES = 4
    const ubyte COLOR = 14              ; light blue disc; multicolor sprite, white core and cyan jets (video.p8)
    const ubyte SPRITE = 7
    const ubyte BOX = 12

    bool appeared                       ; this galaxy already has had its quasar (waiting, shown or gone)
    ubyte wait                          ; frames until it appears (its explosion is still running)
    ubyte life                          ; frames left while shown, 0 = none shown
    uword x                             ; box top-left in playfield pixels
    ubyte y
    ubyte anim_frame
    ubyte anim_timer
    ubyte shows                         ; quasars shown (debug readout)
    ubyte pickups                       ; quasars picked up (debug readout)

    sub start_galaxy() {
        appeared = false
        wait = 0
        life = 0
        video.hide_sprite(SPRITE)
    }

    sub chance(ubyte c, ubyte r) {
        ; A supernova of the star at tile (c, r).
        if appeared
            return
        if not ALWAYS and stars.rand_below(CHANCE) != 0
            return
        appeared = true
        wait = explode.FRAMES           ; counted down after explode.update, so it appears as the explosion ends
        x = ((c as uword) << 4) + 2
        y = (r << 4) + 2
    }

    sub update() {
        ; After explode.update: appearing, burning out, pickup.
        if wait != 0 {
            wait--
            if wait == 0 {
                life = LIFE_FRAMES
                anim_frame = 0
                anim_timer = 0
                shows++
            }
            return
        }
        if life == 0
            return
        life--
        if life == 0 {
            video.hide_sprite(SPRITE)
            return
        }
        anim_timer++
        if anim_timer == ANIM_DELAY {
            anim_timer = 0
            anim_frame++
            if anim_frame == ANIM_FRAMES
                anim_frame = 0
        }
        if player.dying == 0 and player.x < x + BOX and x < player.x + player.BOX
                and player.y < y + BOX and y < player.y + player.BOX {
            life = 0
            pickups++
            video.hide_sprite(SPRITE)
            player.make_invincible()
        }
    }

    sub draw() {
        ; Art centre (frame pixel 10,10) on the box centre (box + 6).
        if life == 0
            return
        if life <= BLINK_FRAMES and (life / BLINK) & 1 != 0
            video.hide_sprite(SPRITE)
        else
            video.set_sprite(SPRITE, assets.SPR_QUASAR_0 + anim_frame, COLOR, x - 4, y - 4)
    }
}
