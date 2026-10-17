; Galaxy Stars, a C64 action game. Phase 1: video foundation test screen
; (random test galaxy, HUD with placeholder values, player sprite in the centre).

%import video
%import input
%import stars
%zeropage basicsafe
%memtop $C000

main {
    const ubyte TEST_STARS = 15
    const ubyte PLAYER_COLOR = 7
    ; player start: art centre (pixel 10,10 of the frame) on the playfield centre px 160, py 96
    const uword START_X = 160 - 10
    const ubyte START_Y = 96 - 10

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
        video.set_sprite(0, assets.SPR_PLAYER_0, PLAYER_COLOR, START_X, START_Y)

        repeat {
            video.wait_frame()
            input.read()
        }
    }
}
