# Build phases

Implementation plan for `docs/spec.md`. Work one phase at a time, in order. Each phase ends with a build the designer can play in VICE.

## How to work a phase

1. Read `AGENTS.md`, then `docs/spec.md` (the whole thing once; afterwards the sections the phase names).
2. Pick the first phase whose status is not `done`. Set it to `in progress`.
3. Implement only that phase's scope. Things the spec defers to later phases stay out.
4. Verify every "Done when" item (see **Verification** below). Fix until all pass.
5. Set the status to `done`. Under the phase, add a short **Notes** list: deviations from the spec, tuned values, known issues. If a decision changed, update `docs/spec.md` too.
6. Stop and report to the designer. Don't start the next phase without their go-ahead; they will want to play each build.
7. When the designer approves the phase, commit it on `main` with a message like `Phase N: <title>`. Don't commit before approval.

If the spec is ambiguous or wrong for something the phase needs, ask the designer. Don't guess on gameplay. For pure implementation details, pick one and record it in Notes.

## Verification

- **Screenshots:** `tools/vice/bin/x64sc.exe -default -silent -sounddev dummy -warp -autostartprgmode 1 -limitcycles <N> -exitscreenshot <png> -autostart build/main.prg`, then view the PNG. About 1,000,000 cycles is 1 second; the program is running by about 3,500,000 cycles.
- **Scripted input** (built in phase 1): a compile-time switch makes `input.p8` read joystick states from a table of (frames to hold, joystick bits) instead of `$DC00`. Must be off in builds handed to the designer.
- **Debug HUD** (`main.DEBUG_HUD`): replaces the HUD row with test readouts when a check needs numbers. Off in handed-over builds.
- Feel (speeds, bounce, chase) can't be self-verified. List it in the report for the designer to check.

---

## Phase 1: Video foundation and tooling
**Status:** done
**Spec:** §1, §2, §3, §4 (tile map), §12, §14

Build:
- `tools/gfx.py`, adapted from Smashy Smashy: hi-res 24x21 sprites, multicolor 2x2 tiles.
- Placeholder art: player spin frames, hostile spin frames, a few star kinds, specks, one explosion frame.
- `build.cmd` / `build.sh`; `src/video.p8` (bank 3, charset/sprite copy, HUD font, `draw_tile`, HUD), `src/input.p8` (joystick, edges, scripted input), frame IRQ.
- `src/main.p8`: random test galaxy of 15 stars with specks, HUD with placeholder values, player sprite in the centre.

Done when:
- [x] Clean build with one command, no converter warnings.
- [x] Screenshot shows the HUD row (score, then time, multiplier and lives each with its icon), stars, specks, the player sprite at the centre, and no star in the centre 4x4 tiles.
- [x] Changing a pixel in an art file changes the screen after a rebuild.
- [x] No `floats` import; program ends below `$C000`.

**Notes:**
- Program ends at `$1789` (code, tables and art).
- The compiler prints one warning, "condition is always false" at `input.p8` (the `SCRIPTED` switch). Expected; the converter prints none. The scripted-input path was compiled once with the switch on.
- Art file format extended (spec §12): `tile ... size WxH` for multi-tile art (the 3x3 explosion), `char` (one multicolor char, specks) and `icon` (one hi-res char, HUD icons). No `mode` line: sprites are always hi-res, chars always multicolor.
- Placeholder art drawn by a script (rotated star polygons), saved as plain text in `assets/`. 8 star kinds; `video.star_char` lists them.
- Specks are stored in `video.specks` at `$C500` (one byte per tile: speck kind and which of the 4 chars), so `draw_tile` can redraw them.
- Shared char colors for now: `$D022` dark grey (11), `$D023` grey (12), chosen so specks can be dark grey, grey or blue. Star glows use them too, which looks dull; to revisit in the art phase.
- Player start: the art centre (frame pixel 10,10) sits on the playfield centre `px 160, py 96`, so the sprite's top-left is `150, 86`.
- HUD columns: `SCORE` at 1, digits 7-14; time icon 27 + digits 28-29; multiplier icon 32 + digit 33; lives icon 36 + digit 37.
- Char budget warning for phase 7: 12 star kinds (48 chars) + 4 explosion frames (144) + specks + icons is more than the 192 free chars. Resolved by the designer: 8 star kinds and 3 explosion frames (148 chars, spec §12).
- Placeholder star kinds 4-7 added (now 8, matching spec §12): green (5), blue (6), yellow (7, X shape) and cyan (3, short cross). Red (2) stays free for the warning flash, and black (0) is skipped because its core would vanish on the black background. Explosion frames 1-2 are still to come (phase 3/7).
- `main.DEBUG_HUD` doesn't exist yet; phase 2 adds it with its first readout.

## Phase 2: Player movement
**Status:** done
**Spec:** §5

Build: 8-direction movement, boost with length and cooldown, playfield clamp, spin animation with direction rules.

Done when:
- [x] Scripted test: hold right for 2 s → moved 150 px (±2).
- [x] Scripted test: boost → 3.75 px/f for 75 frames, second press during boost or within 25 frames after it ends does nothing; a press after that boosts.
- [x] Scripted test: player can't leave the playfield at any edge.
- [x] Spin direction follows the rules (screenshots of frame numbers on the debug HUD).

**Notes:**
- `src/player.p8`. The player's position is the top-left of its 13x13 collision box (frame pixel 4,4), not the sprite frame; that makes the box clamp and the phase 3 hit checks simple. Box range: x 0-307, y 0-179. Start box `154, 90`. Spec §4 updated.
- Clamp: the box, as in the spec (designer confirmed). At the top edge the star's tips overlap the HUD row by up to 4 px; at the other edges the border hides them.
- The player has its own variables in `player`, not the shared actor arrays of spec §4; hostiles get theirs in phase 4.
- Diagonal speeds: 17 normal, 42 boost (24 and 60 x 181/256, rounded).
- The boost starts on the frame fire is pressed and moves at boost speed on that frame; 75 boosted frames, then 25 frames of cooldown in which presses are ignored. Boost with no stick direction just runs the timer.
- Opposite directions held together (left+right) cancel on that axis.
- The spin advances whenever the stick moves the player, including while pushing against an edge.
- Boost glow (spec §5) built here: white, yellow, orange, yellow, changing every 2 frames.
- Stars are not solid yet (phase 3); the player passes over them.
- Self-test: `main.DEBUG_HUD` and `main.TEST` (1 move, 2 boost, 3 clamp, 4 spin) with `input.SCRIPTED`. Results: test 1 x 154 → 304 (150 px). Test 2 x 304 → 22 after 75 boosted frames (281 px = 3.75 px/f); mid-boost the timer showed 30 left at frame 45, so the press at boost frame 41 was ignored; presses 11 and 24 frames after the boost were ignored, the one at 26 frames started boost 2 (frame 251). Test 3 box x min 0 / max 307, y min 0 / max 179. Test 4 right: frames 1,2,3,4,5,0 one every 3 frames; up after right: still forward; left: 4,3,2,1,0,5; down after left: still backward; boosting right: forward, one per frame.
- The compiler prints "condition is always false" / "when-value is a constant" warnings for the self-test switches. Expected.

## Phase 3: Stars, supernovas, scoring
**Status:** not started
**Spec:** §4, §6, §8 (score, multiplier), §10

Build: galaxy generation, player vs star hits and bounce, hit counter and countdown, explosions and chain reactions, player death by explosion (life count only; full respawn in phase 5), score, multiplier with drop timer, HUD updates, galaxy timer.

Done when:
- [ ] Scripted tests: 3 normal hits start the countdown; 1 boosted hit starts it; star explodes 100 frames later.
- [ ] An explosion next to another star starts that star's countdown (chain reaction screenshot).
- [ ] Score and multiplier on the HUD match the events of a scripted run; multiplier drops on schedule.
- [ ] Player caught in an explosion loses a life.

## Phase 4: Hostile stars
**Status:** not started
**Spec:** §7, §8 (chains)

Build: spawn timer, red warning, hostile sprite and steering, speed per galaxy, contact death, boost hurl with its explosion (early on contact or at an edge), explosion kills, chain scoring.

Done when:
- [ ] Hostiles appear at the right interval, never more than 6.
- [ ] Scripted tests for contact death and a boost hurl: the star flies 96 px and explodes; a hurl into another hostile explodes on contact and kills both, scoring two chain steps.
- [ ] A hurl explosion next to a stationary star starts its countdown.
- [ ] A supernova kills a hostile and scores 500 x multiplier; a second in the same chain scores 1000 x multiplier.

## Phase 5: Game flow
**Status:** not started
**Spec:** §8 (lives), §10, §11

Build: lives, extra lives, life-lost sequence and respawn, galaxy start/clear with bonus, galaxy progression and difficulty tables, title, game over, pause, session high score.

Done when:
- [ ] Full loop: title → galaxy 1 → clear → galaxy 2 → game over → title.
- [ ] Clear bonus and extra life checked with scripted runs.

## Phase 6: Quasar and invincibility
**Status:** not started
**Spec:** §9

Done when:
- [ ] With a debug switch forcing the chance to 100%, the quasar appears, burns out after 5 s, and pickup gives 8 s of invincibility with every listed effect.
- [ ] Only one quasar per galaxy.

## Phase 7: Art and sound
**Status:** not started
**Spec:** §12, §13

Build: final sprites and chars (8 star kinds, 3-frame explosion animation, specks), invincibility glow, sound effects.
