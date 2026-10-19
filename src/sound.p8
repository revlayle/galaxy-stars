; Sound effects (spec section 13): SID voice 1, one effect at a time, table-driven. Adapted from Smashy Smashy.
; play() only leaves a request; the frame IRQ calls step(), which starts it and then slides the pitch once per
; frame. A new effect cuts off the one playing, and of two requests in the same frame only the later one plays.

sound {
    const ubyte BOOST = 0
    const ubyte HIT = 1                 ; a star hit (a bounce off a stationary star)
    const ubyte SUPERNOVA = 2           ; also a hurled hostile's explosion
    const ubyte WARNING = 3             ; a star starts turning hostile
    const ubyte HURL = 4                ; a hostile hurled by a boost, or destroyed by the invincible player
    const ubyte LIFE_LOST = 5
    const ubyte EXTRA_LIFE = 6
    const ubyte QUASAR = 7              ; quasar pickup
    const ubyte CLEAR = 8               ; galaxy clear
    const ubyte EFFECTS = 9

    ; [TUNE] one column per effect, in the order above. Waveform bits (the gate, bit 0, is added by step()):
    ; $10 triangle, $20 saw, $40 pulse, $80 noise. Pitch = SID frequency value (PAL: Hz * 17.03), slide = added per
    ; frame (signed). The gate opens at the start and closes after `length` frames, then the release (SR low nibble)
    ; runs. Pitch + slide * length must stay within 0-$FFFF.
    ;                          boost  hit    nova   warn   hurl   life-  life+  quasar clear
    ubyte[] @shared wave =   [$20,   $10,   $80,   $40,   $20,   $10,   $40,   $10,   $40]
    ubyte[] @shared ad =     [$00,   $00,   $00,   $00,   $00,   $00,   $00,   $00,   $00]
    ubyte[] @shared sr =     [$A4,   $A2,   $A9,   $A3,   $A4,   $A6,   $A5,   $A6,   $A8]
    uword[] @shared pitch =  [$0A00, $2000, $1800, $2C00, $4000, $1800, $1000, $0C00, $0800]
    word[] @shared slide =   [$0200, -$0200, -$0060, $0000, -$0400, -$0030, $0200, $0300, $0080]
    ubyte[] @shared length = [12,    3,     20,    8,     10,    50,    25,    30,    60]

    const uword PULSE_WIDTH = $0800     ; 50% square for the pulse effects

    ubyte @shared request               ; 1 + effect, taken by the next step()
    ubyte @shared left                  ; frames until the gate closes, 0 = nothing playing
    ubyte @shared cur_wave
    uword @shared cur_pitch
    word @shared cur_slide
    ubyte[EFFECTS] played               ; times each effect was requested (debug readout)

    sub init() {
        c64.PW1 = PULSE_WIDTH
        c64.CR1 = 0
        c64.MVOL = 15                   ; no filters, full volume
    }

    sub play(ubyte effect) {
        request = effect + 1
        if main.TEST != 0
            played[effect]++
    }

    asmsub step() clobbers(A, X) {
        ; In the frame IRQ.
        %asm {{
            ldx  p8b_sound.p8v_request
            beq  _run
            lda  #0
            sta  p8b_sound.p8v_request
            dex
            sta  c64.CR1                ; gate off first, so the new effect's envelope starts again
            lda  p8b_sound.p8v_ad,x
            sta  c64.AD1
            lda  p8b_sound.p8v_sr,x
            sta  c64.SR1
            lda  p8b_sound.p8v_pitch_lsb,x
            sta  p8b_sound.p8v_cur_pitch
            lda  p8b_sound.p8v_pitch_msb,x
            sta  p8b_sound.p8v_cur_pitch+1
            lda  p8b_sound.p8v_slide_lsb,x
            sta  p8b_sound.p8v_cur_slide
            lda  p8b_sound.p8v_slide_msb,x
            sta  p8b_sound.p8v_cur_slide+1
            lda  p8b_sound.p8v_length,x
            sta  p8b_sound.p8v_left
            lda  p8b_sound.p8v_wave,x
            sta  p8b_sound.p8v_cur_wave
            ora  #1
            sta  c64.CR1
            jmp  _pitch
_run
            lda  p8b_sound.p8v_left
            beq  _done
            dec  p8b_sound.p8v_left
            bne  _slide
            lda  p8b_sound.p8v_cur_wave ; last frame: gate off, release
            sta  c64.CR1
            rts
_slide
            clc
            lda  p8b_sound.p8v_cur_pitch
            adc  p8b_sound.p8v_cur_slide
            sta  p8b_sound.p8v_cur_pitch
            lda  p8b_sound.p8v_cur_pitch+1
            adc  p8b_sound.p8v_cur_slide+1
            sta  p8b_sound.p8v_cur_pitch+1
_pitch
            lda  p8b_sound.p8v_cur_pitch
            sta  c64.FREQLO1
            lda  p8b_sound.p8v_cur_pitch+1
            sta  c64.FREQHI1
_done
            rts
        }}
    }
}
