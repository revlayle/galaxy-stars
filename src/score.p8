; Score, multiplier, lives and the galaxy timer (spec section 8 and 10). Adapted from Smashy Smashy.
; Score events in play come from a table of every base value times x1-x9 (init()), so each is one BCD add. The
; score digits are drawn once at the end of the frame when the score changed (flush()); the other HUD digits are
; redrawn when their value changes (video.put_digit skips unchanged digits).

%import video

score {
    const ubyte START_LIVES = 3
    const ubyte MAX_LIVES = 9
    const uword EXTRA_LIFE_EVERY = $0500    ; [TUNE] BCD hundreds: an extra life every 50,000 points
    const ubyte MAX_MULT = 9
    const ubyte GALAXY_TIME = $60       ; BCD seconds
    const ubyte FRAMES_PER_SECOND = 50
    ; [TUNE] frames before the multiplier drops by 1, indexed by its current value (x2 to x9)
    ubyte[MAX_MULT + 1] drop_frames = [0, 0, 175, 157, 139, 121, 104, 86, 68, 50]
    ; hostile chain steps in hundreds, BCD: 500, 1000, 2000, 4000, 8000, 16000 (the cap from the 6th kill on, the
    ; most hostiles at once; designer, 2026-10-18: was the 8th, 64000) [TUNE]
    const ubyte CHAIN_STEPS = 6
    ; score table types: 0 = supernova (100), 1-6 = chain steps 1-6; base values in BCD hundreds
    const ubyte T_SUPERNOVA = 0
    const ubyte TYPES = 1 + CHAIN_STEPS
    ubyte[TYPES] base_lo = [$01, $05, $10, $20, $40, $80, $60]
    ubyte[TYPES] base_mid = [$00, $00, $00, $00, $00, $00, $01]
    ubyte[TYPES] type_start = [0, 9, 18, 27, 36, 45, 54]   ; type * MAX_MULT
    ; base value times x1-x9 at type_start[type] + mult - 1 (BCD hundreds, at most 16,000 x 9 = 1440), by init()
    ubyte[TYPES * MAX_MULT] table_lo
    ubyte[TYPES * MAX_MULT] table_mid
    bool dirty                          ; the score changed: flush() draws it

    ; score in hundreds, 6 BCD digits (the HUD appends "00")
    ubyte points_hi
    ubyte points_mid
    ubyte points_lo
    ubyte mult
    ubyte mult_timer                    ; frames left before the multiplier drops (mult > 1)
    ubyte lives
    ubyte galaxy                        ; 1-based
    ubyte time                          ; BCD seconds left
    ubyte time_frames                   ; frames left in the current second
    ubyte chain                         ; hostile kills in the current chain
    ; next extra life at this score (BCD hundreds); no_more_lives once it would pass 99,999,900
    ubyte next_hi
    ubyte next_mid
    ubyte next_lo
    bool no_more_lives
    ; session high score (BCD hundreds)
    ubyte high_hi
    ubyte high_mid
    ubyte high_lo
    ; last galaxy clear bonus (BCD hundreds, already times the multiplier)
    ubyte bonus_mid
    ubyte bonus_lo

    sub init() {
        ; Once at startup: the score table, by repeated BCD adds (bonus_lo/bonus_mid as the sum).
        ubyte t
        ubyte k = 0
        for t in 0 to TYPES - 1 {
            bonus_lo = 0
            bonus_mid = 0
            repeat MAX_MULT {
                add_acc(base_lo[t], base_mid[t])
                table_lo[k] = bonus_lo
                table_mid[k] = bonus_mid
                k++
            }
        }
    }

    sub new_game() {
        points_hi = 0
        points_mid = 0
        points_lo = 0
        mult = 1
        mult_timer = 0
        chain = 0
        lives = START_LIVES
        galaxy = 1
        next_hi = 0
        next_mid = msb(EXTRA_LIFE_EVERY)
        next_lo = lsb(EXTRA_LIFE_EVERY)
        no_more_lives = false
        video.hud_score(0, 0, 0)
        video.hud_mult(mult)
        video.hud_lives(lives)
    }

    sub start_galaxy() {
        time = GALAXY_TIME
        time_frames = FRAMES_PER_SECOND
        chain = 0
        video.hud_time(time)
    }

    sub chain_kill() {
        ; A hostile destroyed: the next chain step times the multiplier.
        ubyte step = chain
        if step >= CHAIN_STEPS
            step = CHAIN_STEPS - 1
        add_type(1 + step)
        if chain != 255
            chain++
    }

    sub supernova() {
        ; 100 points times the multiplier before the raise; then +1, or at x9 only the drop timer restarts.
        add_type(T_SUPERNOVA)
        if mult < MAX_MULT {
            mult++
            video.hud_mult(mult)
        }
        mult_timer = drop_frames[mult]
    }

    sub add_type(ubyte t) {
        ; A score event from the table: its base value times the multiplier, one BCD add.
        if main.PROFILE
            prof.sub_begin()
        ubyte k = type_start[t] + mult - 1
        add_once(table_lo[k], table_mid[k])
        dirty = true
        check_extra()
        if main.PROFILE
            prof.sub_end(2)
    }

    sub add(ubyte bcd_lo, ubyte bcd_mid) {
        ; Adds any BCD value in hundreds (bcd_mid:bcd_lo, up to 9999) times the multiplier, by repeated adds (the
        ; time bonus and self-tests; score events in play use add_type).
        repeat mult
            add_once(bcd_lo, bcd_mid)
        dirty = true
        check_extra()
    }

    sub flush() {
        ; End of frame: the score digits, if the score changed.
        if dirty {
            dirty = false
            video.hud_score(points_hi, points_mid, points_lo)
        }
    }

    sub check_extra() {
        ; An extra life for each threshold the score has reached (one event can pass several). Past
        ; MAX_LIVES none is given, but the threshold still moves on.
        while not no_more_lives and reached_next() {
            if lives < MAX_LIVES {
                lives++
                video.hud_lives(lives)
                sound.play(sound.EXTRA_LIFE)
            }
            if raise_next() != 0
                no_more_lives = true
        }
    }

    sub reached_next() -> bool {
        ; points >= next (BCD bytes compare like plain numbers)
        if points_hi != next_hi
            return points_hi > next_hi
        if points_mid != next_mid
            return points_mid > next_mid
        return points_lo >= next_lo
    }

    asmsub raise_next() -> ubyte @A {
        ; next += EXTRA_LIFE_EVERY in BCD. Returns 1 when it overflowed 999999.
        %asm {{
            php
            sei
            sed
            clc
            lda  p8b_score.p8v_next_lo
            adc  #<p8b_score.p8c_EXTRA_LIFE_EVERY
            sta  p8b_score.p8v_next_lo
            lda  p8b_score.p8v_next_mid
            adc  #>p8b_score.p8c_EXTRA_LIFE_EVERY
            sta  p8b_score.p8v_next_mid
            lda  p8b_score.p8v_next_hi
            adc  #0
            sta  p8b_score.p8v_next_hi
            lda  #0
            rol  a                      ; the carry out (rol ignores decimal mode)
            plp
            rts
        }}
    }

    sub time_bonus() {
        ; Galaxy clear: 100 x seconds left, times the multiplier; then the multiplier resets to x1.
        ; The seconds (BCD) are the bonus in hundreds, added `mult` times into bonus_mid:bonus_lo.
        bonus_lo = 0
        bonus_mid = 0
        repeat mult
            add_acc(time, 0)
        mult = 1
        add(bonus_lo, bonus_mid)        ; already multiplied: added once
        flush()
        mult_timer = 0
        video.hud_mult(mult)
    }

    asmsub add_acc(ubyte bcd_lo @A, ubyte bcd_mid @Y) clobbers(A) {
        ; bonus_mid:bonus_lo += bcd_mid:bcd_lo in BCD (time bonus and the score table).
        %asm {{
            sta  P8ZP_SCRATCH_B1
            php
            sei
            sed
            clc
            lda  p8b_score.p8v_bonus_lo
            adc  P8ZP_SCRATCH_B1
            sta  p8b_score.p8v_bonus_lo
            tya
            adc  p8b_score.p8v_bonus_mid
            sta  p8b_score.p8v_bonus_mid
            plp
            rts
        }}
    }

    sub update_high() {
        ; Game over: the session high score.
        if points_hi > high_hi or (points_hi == high_hi and (points_mid > high_mid
                or (points_mid == high_mid and points_lo > high_lo))) {
            high_hi = points_hi
            high_mid = points_mid
            high_lo = points_lo
        }
    }

    asmsub add_once(ubyte bcd_lo @A, ubyte bcd_mid @Y) clobbers(A) {
        ; 3-byte BCD add, interrupts off while decimal mode is on. Stops at 999999 (99,999,900 points).
        %asm {{
            sta  P8ZP_SCRATCH_B1
            php
            sei
            sed
            clc
            lda  p8b_score.p8v_points_lo
            adc  P8ZP_SCRATCH_B1
            sta  p8b_score.p8v_points_lo
            tya
            adc  p8b_score.p8v_points_mid
            sta  p8b_score.p8v_points_mid
            lda  p8b_score.p8v_points_hi
            adc  #0
            sta  p8b_score.p8v_points_hi
            bcc  +
            lda  #$99
            sta  p8b_score.p8v_points_hi
            sta  p8b_score.p8v_points_mid
            sta  p8b_score.p8v_points_lo
+           plp
            rts
        }}
    }

    sub lose_life() {
        ; The count and the multiplier; player.hurt() starts the death effect.
        if lives != 0
            lives--
        video.hud_lives(lives)
        mult = 1
        mult_timer = 0
        video.hud_mult(mult)
    }

    sub update() {
        ; Once per frame: multiplier drop and galaxy timer.
        if mult > 1 {
            mult_timer--
            if mult_timer == 0 {
                mult--
                mult_timer = drop_frames[mult]
                video.hud_mult(mult)
            }
        }
        if time != 0 {
            time_frames--
            if time_frames == 0 {
                time_frames = FRAMES_PER_SECOND
                time = bcd_dec(time)
                video.hud_time(time)
            }
        }
    }

    sub bcd_dec(ubyte value) -> ubyte {
        ; BCD minus 1 for value > 0, without decimal mode
        if value & 15 == 0
            return value - 7            ; $x0 -> $(x-1)9
        return value - 1
    }
}
