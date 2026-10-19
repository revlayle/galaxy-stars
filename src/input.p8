; Joystick in port 2 and the Run/Stop key (read from the keyboard matrix), with edge detection.
; Adapted from Smashy Smashy.
; SCRIPTED = true replays the `script` table instead of reading $DC00 (self-testing only; keep false in builds
; for the designer).
; While `pilot` is on (the demo, demo.p8) the game gets the pilot's bits; the stick (or the script) only goes to
; real_pressed, and a fire press there sets demo.quit.

input {
    const bool SCRIPTED = false

    ; joystick bits, 1 = active
    const ubyte UP = %00001
    const ubyte DOWN = %00010
    const ubyte LEFT = %00100
    const ubyte RIGHT = %01000
    const ubyte FIRE = %10000
    const ubyte STOP = %100000          ; Run/Stop key, in the same bit set

    ubyte held          ; bits held this frame
    ubyte pressed       ; bits that went from released to held this frame
    ubyte prev
    bool pilot
    ubyte real_pressed                  ; pilot on: presses on the real stick
    ubyte real_prev

    ; (frames to hold, joystick bits) pairs. A 0 frame count ends the script; input is released after that.
    ; Self-tests may point `script` at their own table.
    ubyte[] default_script = [
        100, 0,
        0, 0
    ]
    uword script = &default_script
    ubyte script_pos = 0
    ubyte script_left = 0

    sub read() {
        ubyte joy
        if SCRIPTED
            joy = scripted()
        else {
            joy = ~c64.CIA1PRA & %00011111
            ; Keyboard matrix: a 0 on a port A bit selects a row, port B shows its keys (0 = down).
            ; Run/Stop is row 7 bit 7. The KERNAL IRQ doesn't run, so nothing else scans.
            c64.CIA1PRA = %01111111
            if c64.CIA1PRB & %10000000 == 0
                joy |= STOP
            c64.CIA1PRA = $FF
        }
        if pilot {
            real_pressed = joy & ~real_prev
            real_prev = joy
            if real_pressed & FIRE != 0
                demo.quit = true
            joy = demo.steer()
        }
        pressed = joy & ~prev
        held = joy
        prev = joy
    }

    sub start_pilot() {
        real_prev = prev                ; a fire held from before is not a press
        real_pressed = 0
        pilot = true
    }

    sub stop_pilot() {
        ; Back to the stick: what it holds now is not a new press on the next page.
        pilot = false
        prev = real_prev
        held = real_prev
        pressed = 0
    }

    sub scripted() -> ubyte {
        while script_left == 0 {
            if @(script + script_pos) == 0
                return 0
            script_left = @(script + script_pos)
            script_pos += 2
        }
        script_left--
        return @(script + script_pos - 1)
    }
}
