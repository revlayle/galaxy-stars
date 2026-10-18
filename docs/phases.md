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
**Status:** done
**Spec:** §4, §6, §8 (score, multiplier), §10

Build: galaxy generation, player vs star hits and bounce, hit counter and countdown, explosions and chain reactions, player death by explosion (life count only; full respawn in phase 5), score, multiplier with drop timer, HUD updates, galaxy timer.

Done when:
- [x] Scripted tests: 3 normal hits start the countdown; 1 boosted hit starts it; star explodes 100 frames later.
- [x] An explosion next to another star starts that star's countdown (chain reaction screenshot).
- [x] Score and multiplier on the HUD match the events of a scripted run; multiplier drops on schedule.
- [x] Player caught in an explosion loses a life.

**Notes:**
- New modules: `src/score.p8` (BCD score in hundreds, multiplier, lives, galaxy timer) and `src/explode.p8` (explosion list, drawing, area checks). Star hits, countdowns and supernovas are in `stars.p8`, the knockback in `player.p8`.
- Frame order: input, score/timer tick, player, player vs stars, explosions vs player, star timers (supernovas, then countdowns), explosion timers. The score tick runs first so a multiplier raised in a frame keeps its full drop time.
- Galaxy 1 only: 15 stars from `stars.for_galaxy()`. Galaxy clear (`stars.left` = 0), game over and respawn come in phase 5. At 0 lives nothing happens yet.
- Each explosion takes at most one life (the player stays where they are until phase 5 adds the respawn).
- Knockback: the boost timer keeps counting down during the 6 knockback frames (the boost isn't cancelled), and fire presses during the knockback are ignored. The spin keeps turning. Direction: an axis counts when it is at least half the other (about 26.6°, close to the 22.5° boundary).
- Touching a star counts once, then that star ignores the player for 10 frames (no hit, no bounce). Two stars touched in the same frame both count; the bounce is away from the last one checked.
- `explode.cover` at `$C600` counts the explosions over each tile. Star color changes skip covered tiles; a tile is redrawn from the map when its last explosion ends. Spec §4 updated.
- Explosion art: only frame 0 exists, shown for all 30 frames (the 3-frame animation is phase 7).
- Hit feedback colors are placeholders, by the star's own color: hits 1 yellow, hits 2 white (yellow stars: white then cyan; white stars: yellow then cyan). Countdown flashes the star's own pixels white/black every 8 frames, every 2 frames in the last 25; the shared-color glow stays. To revisit in the art phase.
- Staggered chains (designer request, spec §6): stars caught by one explosion get countdowns of 100, 106, 112, ... frames in random order, so they don't all explode in the same frame. Test 10 (one explosion catching 5 stars): star 0 at 158, the others at 258, 264, 270, 276, 282. Two separate chains can still line up in the same frame; not handled.
- Overlapping explosions: a tile under two explosions shows the part of whichever drew last, also after that one ends (the danger area is still right). Looks like stray slivers; to revisit with the explosion animation in phase 7.
- Self-tests (`main.TEST` with `input.SCRIPTED` and `main.DEBUG_HUD`): 5 three hits, 6 boosted hit, 7 chain reaction, 8 caught in an explosion, 9 chain with a multiplier log, 10 staggered chain. Tests 1-4 now run with no stars. Readouts: frames, state+hits of stars 0-3, countdown and supernova frames of star 0, lives, score (hundreds), multiplier, bounces.
- Results: test 5: hits 1 (frame 77), 2 (93), countdown on the 3rd hit (105), supernova at 205. Test 6: one boosted hit, countdown at 58, supernova at 158. Test 7: star 0 explodes at 158 and star 1 starts its countdown; star 1 explodes at 258 and star 2 starts; star 2 explodes at 358; star 3, two tiles from star 2, stays idle. Score 600 (100 x1 + 100 x2 + 100 x3), multiplier x4. Test 9: multiplier x2 at 158, x3 at 258, x4 at 358, then drops at 497 (139 frames), 654 (157) and 829 (175). Test 8: lives 3 -> 2 once, multiplier back to x1. Timer: 01 at about 61 s, 00 after that and stays there. Phase 2 test 1 still gives x 154 -> 304.
- The compiler prints the expected "condition is always false/true" and "when-value is a constant" warnings for the self-test switches.
- **prog8c 12.3.4 bug:** `video.tiles[video.row_start[row[i]] + col[i]] = 0` compiles to `row_start[row] + row` (the `col[i]` load is overwritten), so the wrong tile was cleared and exploded stars came back. Worked around in `stars.supernova` by computing the index in two steps. The other tile index sums (plain variables) were checked in the generated assembly and are correct. Avoid summing two array reads inside an index.

## Phase 4: Hostile stars
**Status:** done
**Spec:** §7, §8 (chains)

Build: spawn timer, red warning, hostile sprite and steering, speed per galaxy, contact death, boost hurl with its explosion (early on contact or at an edge), explosion kills, chain scoring.

Done when:
- [x] Hostiles appear at the right interval, never more than 6.
- [x] Scripted tests for contact death and a boost hurl: the star flies 96 px and explodes; a hurl into another hostile explodes on contact and kills both, scoring two chain steps.
- [x] A hurl explosion next to a stationary star starts its countdown.
- [x] A supernova kills a hostile and scores 500 x multiplier; a second in the same chain scores 1000 x multiplier.

**Notes:**
- New module `src/hostiles.p8`: 6 slots (sprite = slot + 1), spawn timer, warning hand-off, steering, spin, player contact, hurl flight and explosion, explosion kills. The WARNING state (red flash, then the tile is cleared and the hostile appears) is in `stars.p8`; the chain counter and its BCD step table (500 ... 64,000) are in `score.p8`.
- Frame order: input, score/timer, player, hostiles (spawn, steer, hurl flights), player vs stars, player vs hostiles, explosions vs player, explosions vs hostiles, star timers, explosion timers and tile restore, chain check, sprites.
- Hostile position is the top-left of its 12x12 box, at frame pixel (4,4) like the player. A new hostile's box is exactly the star's box (tile pixels 2-13). Box range x 0-308, y 0-180. Spec §4 updated.
- Steering: one heading step towards the player every 4 frames, the slots spread over the 4 frames. The direction to the player comes from comparing |dy| with |dx| at the 22.5° boundaries (ratios 1/5, 2/3, 3/2, 5), no atan table. Exactly behind turns clockwise. A new hostile starts heading straight at the player. The 16 velocities are built at galaxy start (speed x cos / 127).
- Spawn "at least 4 tiles away" uses the spec's 9x9 box: a star counts as far when its column or row differs by 5 or more from the tile under the player's centre.
- **A hurled hostile keeps its slot (and sprite) until it explodes**, so it still counts towards the 6. A spawn that is due waits for that. Spec §7 updated.
- Hurled hostiles are not affected by explosions they fly through (they are already scored and explode at the end anyway). The spec didn't say; easy to change. Spec §7 updated.
- Phase 4 has no respawn: like an explosion, each hostile takes at most one life (it then passes over the player). Phase 5 replaces this with the death sequence and the 2 s of safety.
- The hurl direction uses the speed the player moved with that frame (also during a knockback); standing still, it is away from the player (nearest of 8, as the bounce). Hurl speed 96 subpx, diagonal 68. The explosion is on the tile under the box centre.
- `player.boosted` (the boost ran this frame) now decides boosted star hits and hurls. Before, the boost's 75th frame counted as a normal hit; now it is boosted.
- A +1 hit on a warning star shows the hit color until the next flash step (the flash alternates red with the star's own color every 4 frames).
- Chain: alive while an explosion runs, a star is in a countdown started by an explosion (`stars.from_blast`), or a hurl is flying; checked once at the end of the frame. Invincibility joins in phase 6.
- **Frame time.** The first build dropped frames at galaxy 11 with 6 hostiles. Measured per routine with a CIA timer and fixed:
  - `hostiles.move`, the hostiles' sprite shadow writes, the star scan in `stars.update` (`next_busy`) and the spawn scan (`scan_idle`) are inline assembly. `video.set_sprite` uses a bit table. The explosion checks return at once when no explosion is running (`explode.live`). The hurl touch checks look at 4 tiles directly.
  - At most one explosion starts per frame: a further supernova that is due goes off a frame later, and a hurled hostile whose flight is over waits in place for a frame. Tiles under an ended explosion are restored through a queue, one explosion per frame (the danger still ends on time). These delays are 1-2 frames, too short to see. Spec §6 updated.
  - Result at galaxy 11 (35 stars), 6 hostiles gathered on the player and hurled, 40 s scripted: 0 dropped frames; a normal frame takes about 113 raster lines, the slowest 272 of 312. That leaves about 40 lines in the worst frame for later phases (quasar, 3-frame explosion animation, 45 stars), so the explosion animation will need care.
- Hostile look is placeholder: red (2), spinning every 3 frames, every frame while hurled.
- Designer played the build (2026-10-17): approved. The hostile warning visuals may be tweaked later.
- Self-tests (`main.TEST` with `input.SCRIPTED` and `main.DEBUG_HUD`): 11 spawns in galaxy 1, 12 spawns in galaxy 11 with boosts into the pack, 13 contact death, 14 hurl in the open, 15 hurl into another hostile, 16 hurl explosion next to a star, 17 supernova kills two hostiles, 18 hurl into a stationary star. Tests 1-10 run with spawns off. With the debug HUD on, the normal HUD values no longer draw over the readouts; tests 11-18 redraw them every 8th frame.
- Results: test 11: warnings at frames 300, 600, 900, 1200, 1500, 1800, then 6 active and no more. Test 12 (galaxy 11): every 50 frames up to 6 by frame 300; after the boost at frame 600 the next spawn came at 614, when the first hurled one exploded and freed its slot; max active 6, 0 dropped frames. Test 13: lives 3 -> 2, once. Test 14: hurled at box x 185, exploded at 281 (96 px) 16 frames later, score 500. Test 15: exploded on touching the second hostile after 6 frames (x 185 -> 221); both destroyed, score 500 + 1,000, chain 2. Test 16: the end-of-flight explosion at x 281 put star 1 (tile 18,4, not touched) into its countdown; it went supernova 100 frames later. Test 18: exploded on touching star 1 after 13 frames (x 185 -> 263) and started its countdown. Test 17: supernova 100 at x1 (raises to x2), then the two hostiles in it 500 x2 and 1,000 x2: 3,100. Tests 1-10 give the same numbers as before.

## Phase 5: Game flow
**Status:** done
**Spec:** §8 (lives), §10, §11

Build: lives, extra lives, life-lost sequence and respawn, galaxy start/clear with bonus, galaxy progression and difficulty tables, title, game over, pause, session high score.

Done when:
- [x] Full loop: title → galaxy 1 → clear → galaxy 2 → game over → title.
- [x] Clear bonus and extra life checked with scripted runs.

**Notes:**
- New module `src/title.p8` (title and game-over screens). The state machine is in `main.start()`: title, new game, then galaxy start, play and galaxy clear until play returns false (game over). Program ends at `$44C3` (with the later changes below).
- Designer decisions (2026-10-17): when the last star is destroyed, play goes on until the explosions and hurl flights are over, and the player can still be hurt meanwhile. A boost during the 2 s of safety still hurls hostiles. Title: text, background specks and the spinning player star, no attract pages (may be expanded later). Spec §8 and §11 updated.
- Galaxy clear: when `stars.left` reaches 0 the timer and the multiplier stop (the bonus uses that moment's seconds and multiplier). Play ends when no explosion runs, the restore queue is empty, no hurl is flying and no death effect is playing. A death in that time resets the multiplier to x1 before the bonus; if it was the last life, it is game over instead of a clear.
- Clear screen: "GALAXY CLEAR" and "TIME BONUS n", where n is the total added (seconds x 100 x multiplier, no leading zeros), 3 s. Then the multiplier is x1 and the next galaxy starts.
- Galaxy start: "GALAXY nn" at char row 9 (above the player) for 2 s. The stars appear one per frame in random order (15-45 stars: 0.3-0.9 s); the spec said "a few per frame". The message is redrawn each frame, since a star at tile column 7 or 12 of row 4 is drawn under it, and those tiles are restored when it goes. The galaxy number shows up to 99.
- Losing a life: the life is taken at the hit, so the HUD shows 0 during the last death effect; game over comes when that effect ends. During the effect there is no control and no contact with stars, hostiles or explosions; boost, cooldown and knockback are cleared. Hostiles keep chasing the spot where the player was.
- Death effect placeholder: the sprite flashes white, red, yellow, black (one every 2 frames) and spins a picture per frame. Shrink frames come with the art in phase 7. Safety blink: 4 frames shown, 4 hidden.
- The phase 3-4 stopgaps (each explosion and each hostile takes at most one life) are gone; the death effect and safety replace them.
- Pause: "PAUSED" in the empty HUD columns 18-23, so nothing on the playfield has to be restored (an explosion could be drawn there). Run/Stop again resumes; the resume press doesn't reach the game.
- Game over: "GAME OVER" and "HIGH SCORE" over the frozen playfield (hostile sprites stay and can cover the text). The high score is updated first, so it already includes this game. Fire after 1 s returns to the title.
- Extra lives: `score.check_extra()` after every score add. One event can pass several thresholds (a life each, up to 9). At the score maximum (99,999,900) the thresholds stop (`no_more_lives`), so the check can't loop forever.
- **Respawn push and hold** (designer change after playing, 2026-10-17; spec §8). Before it, a hostile at the centre killed the player on the first frame after the safety ended, so three lives went in about 8 s.
  - When the player reappears, `hostiles.push_out()` starts a push for every chasing hostile whose centre is inside the box 80 px left/right and 64 px up/down of the centre: straight away from the player (nearest of 16 headings) at 6 px/f until its centre is outside the box. Hurled hostiles aren't pushed. The box lies inside the playfield, so a push always ends at the box edge (the edge stop is kept anyway), within 14 frames, well inside the safe time.
  - While the player is safe, chasing hostiles hold still and spin; they keep turning towards the player, so they set off straight at them when the safety ends. Hostiles that appear during the safety hold too.
  - Frame time: the first version put the push and hold checks in `chase()` (about 20 cycles per hostile per frame) and test 12 counted 1 dropped frame in 5 of 16 layouts. Most likely that was the counting error found later (see the hurl change below): the count included the first frame. Now `hostiles.update` runs a separate `chase_safe()` only while the player is safe, so normal frames run the old code either way. A frame with 6 pushes costs about the same as 6 chasing hostiles (the same `move()`), and held hostiles cost less; test 12 doesn't cover respawn frames, since the player can't die there.
- **Hurl blasts** (designer change after playing, 2026-10-18; spec §7). A hostile hurled while over or next to a star exploded on the spot (12-30 px away) and caught the player every time.
  - The player now bounces off the hurled hostile, the knockback of a star bounce, opposite the hurl direction (the boost keeps running). So a boost into a pack usually hurls one hostile, not all it passes.
  - The hurled hostile flies through stationary stars (`touches_star` is gone). It flies through hostiles for its first 8 frames (`hostiles.HURL_FREE_FRAMES`, 48 px), then explodes on touching one; otherwise at the end of the 96 px flight.
  - At a playfield edge it flies on for 7 frames (`OFF_FRAMES`, whole pixels, no clamp; the coordinates wrap slightly past the edges, where the border hides the sprite) and is freed with no explosion. Its kill was scored at the hurl. At the top edge it passes over the HUD row for a frame or two.
  - New test 27 (readouts as tests 13-18): the hostile from tile (15,5) is hurled at box x 185 while overlapping a star at (12,5). Result: full flight to x 281 (96 px), the star untouched, lives 3. An intermediate version that still exploded on stars after the first 8 frames gave the same result; with those 8 frames set to 0 it exploded after 1 frame (x 191) and the player lost a life, even with the bounce.
  - New test 28: the player moves right, then boosts into the hostile from tile (19,5): hurled at box x 237, it reached the right edge and slid off into the border. No explosion (blast x and frame stay 0), kill counted (500, chain 1), slot freed, lives 3.
  - Changed numbers: test 15 now explodes on the second hostile after 8 frames instead of 6 (x 185 -> 233, was 221), with the same score of 1,500 and chain 2. Test 18 now flies through the star at (17,5) to the full 96 px (x 281, was 263 when it exploded at the star); the landing blast still sets that star off, so the score is the same, 600. Tests 14 and 16 are unchanged (96 px, x 281).
  - **Test 12 counting error fixed:** the dropped-frame counter included frame 0, which always starts late after the test setup; it now skips it. Results with the fix, galaxy 11 stress, 45 s per layout: before the off-edge change, 1 real dropped frame in 48 layouts, at frame 825 of one layout. That was 3 frames after the scripted boost into the pack, with 3 explosions running. The per-frame margin was already thin (phase 4: about 40 lines in the worst frame); to look at with the phase 7 explosion animation. With the final hurl rules (through stars, off the edge): 0 dropped frames in 16 layouts.
- Self-tests (`main.TEST` with `input.SCRIPTED`; DEBUG_HUD where noted): 19 full loop, 20 clear bonus and extra life, 21 extra life thresholds (DEBUG_HUD, no play), 22 pause, 23 death and respawn (DEBUG_HUD), 24 boost hurl while safe (DEBUG_HUD), 25 explosion over the respawn point while safe (DEBUG_HUD), 26 respawn push and hold with a galaxy 11 speed hostile (DEBUG_HUD), 27 hurl of a hostile over a star, 28 hurl off the playfield edge, 29 and 30 boost out of a one-tile gap between two stars (horizontal, vertical), 31 lone explosions in column 0 and row 0 (all old-style readouts), 32 map of an explosion's round core (no play). Tests 1-18 and 27-31 run their old setup through the new play loop (`main.OLD_TEST`: never cleared, halts at game over). Tests 11-12 make the player unhurtable (`main.NO_DEATH`); otherwise the player dies before the stress test boosts into the pack.
- Results: test 19: title, fire, GALAXY 01 with the star appearing, supernova, GALAXY CLEAR with TIME BONUS 11400 (57 s x 100 x2) and score 11,500, GALAXY 02 with 17 random stars, three lives lost to hostiles, GAME OVER with HIGH SCORE 00011500, then the title showing 00011500. Test 20 (start score 19,900): supernova -> 20,000, x2, lives 3 -> 4; clear bonus 11,400 -> 31,400, x1. Test 21: +60,000 in one event: lives 3 -> 6, next 80,000; then 9 x 100,000: 960,000, lives 9 (cap), next 980,000; at the score maximum 99,999,900 the flag is set and lives stay 9. Test 22: two screenshots 1.2 s apart during the pause are pixel-identical (timer 52, hostile still); after Run/Stop the timer runs on. Test 23 (before the respawn push): death at frame 152, back in the centre at 202 (+50), the hostile passed through during safety, next death at 302 (the first frame after safety), then 352 and the third. With the push: deaths at 152 and 378, respawns at 202 and 428, the third later. Test 24: a boost during safety hurled the hostile (kills 1, lives 2, one death). Since the push it boosts towards where the hostile was pushed (the direction is filled into the script at the respawn); a boost on the spot no longer reaches it. Test 26: death at 93, respawn at 143; the hostile, at the centre when the player died, was pushed straight up and out of the box by frame 148 (box 153, 22), moved on 0 frames during the safety, then chased (31 moving frames) until the next death. Test 25: death at 159, respawn at 209, star 1's explosion over the respawn point at 221: no death, lives 2.
- Designer played the build (2026-10-17): approved; more feedback after longer play.
- Designer approved the later changes below (2026-10-18): tuning, bounce fixes, round explosion core, frame-time work. Phase 5 done.
- **Tuning after play** (designer, 2026-10-18; spec §7, §8, §10). Galaxies 1-6 felt easy and it got hard suddenly around 7; scores reached 600,000+.
  - Difficulty ramp stretched: the spawn interval drops 0.25 s per galaxy instead of 0.5 s and the hostile speed rises half as fast, both reaching their maximum (1 s, 120%) at galaxy 21 instead of 11. Galaxy 1 is unchanged. `hostiles.galaxy_speed` has 21 entries.
  - Stars: at most 55 (was 45), reached at galaxy 21 together with the ramp (`stars.MAX`).
  - Extra life every 50,000 (was 20,000). Chain cap at the 6th kill, 16,000 (was the 8th, 64,000): a full chain is 31,500 x multiplier.
  - Test 12 now runs galaxy 21, the hardest. Test 20 starts at 49,900: the supernova reaches 50,000 and gives the 4th life; the clear bonus brings it to 61,400. Test 21: +60,000 gives 1 life (next 100,000); a 900,000 event caps at 9 lives (next 1,000,000); at the maximum score the thresholds stop; then 8 chain kills at x1 score 63,500 (500 + 1,000 + 2,000 + 4,000 + 8,000 + 16,000 x 3). Test 26 uses the top speed from the table's last entry.
  - **Frame time at the top end: dropped frames.** Test 12 at galaxy 21 (55 stars): 7 of 16 layouts dropped frames (1 to 10 in 45 s). The committed code at galaxy 16 (45 stars, never tested before) already dropped 1 frame in 3 of 16. The dropped frames come when a new explosion starts (drawing its 3x3 tiles and catching stars) while 2-8 explosions run, 3-6 stars count down after a blast and 4-6 hostiles chase; in two layouts with all 8 explosion slots full at x9. To fix before the art phase adds the explosion animation (see the report).
  - **Frame-time work (2026-10-18).** New test-only profiler `src/prof.p8` (`main.PROFILE`): CIA 2 timer A, a mark after each part of the frame, the worst frame's breakdown and each part's maximum on char rows 21-24, plus maxima of explosion start, tile restore and score add. Numbers are CPU cycles; a PAL frame is about 19,700.
  - First measurement (galaxy 21): worst frame 23,179 cycles. Explosion start up to 5,602, tile restore up to 3,654, a score add at x9 up to 2,828 (repeated adds plus redrawing the 8 digits through Prog8 calls), the hostile/explosion and player/hostile checks up to about 5,000 each in busy frames.
  - In assembly (`asmsub`): `video.draw_tile`; `explode.draw_area` (explosion start: 36 chars and colors, the cover map and the caught stars in one loop); `explode.restore_area`; `video.put_score`; `hostiles.explosion_hit` (hostile vs explosion, comparing tile ranges; each explosion's area is stored at its start in `explode.ac0/ac1/ar0/ar1` instead of recomputed every frame). `video.draw_quad` was removed (no longer used).
  - Score table (`score.init()`): every base value (supernova 100, chain steps 500-16,000) times x1-x9 in two 63-byte BCD arrays, filled at startup, so each score event in play is one BCD add at any multiplier (`score.add_type`). The score digits are drawn once at the end of the frame when the score changed (`score.flush()`). The time bonus still uses repeated adds (once per galaxy).
  - Checked: screenshots of the old and new code frozen at the same game frame (fixed seed) are pixel-identical in tests 7, 9, 10, 15, 17, 19, 20, 31 and 12, mid-explosion, after the restore, at the left and top edges and through a galaxy clear; only test 12's frame-time readout differs. Test 21 gives the same numbers.
  - Results: explosion start 5,602 -> about 3,400 (the rest is the caught stars: shuffle, countdowns, recoloring), restore 3,654 -> about 2,500, score add at x9 2,828 -> under 1,000 (with the profiler's own overhead and the extra-life check). Test 12 at galaxy 21, 16 layouts: dropped frames in 7 layouts (up to 10) -> 4 (up to 7) after the drawing -> 3 (1 frame each) after the score table and the explosion check.
  - **Round explosion core** (designer report and decision, 2026-10-18; spec §6): explosions hurt the player and destroy hostiles only within a round core, `explode.hits()` (assembly): the object's centre within `explode.REACH` (22 px) of the explosion's centre, as longer axis + half the shorter. Each explosion stores its centre at its start (`core_x`, `core_y`); `hostiles.explosion_hit` and `explode.check_player` both use it. Stationary stars are still caught by the whole 3x3 tiles. Test 32 draws the hit area (17 x 17 offsets, 4 px apart): an octagon reaching 20 px along the axes, about 40 px across, inside the 48 x 48 square.
  - Changed tests: test 8 now keeps pushing into the star (`script_caught_close`) and starts lined up with it (y 82); with the old script and the corrected diagonal bounce the player ended 22 px from the centre, just outside the core. Lives 3 -> 2 as before. Test 17's second hostile is now right of the star (13,5) instead of diagonal (13,6), which is outside the core; result as before, 3,100 with chain 2. Tests 15, 16 and 25 behave as before; the flow tests 19 and 20 give the same results.
  - Frame time after the core change: test 12 at galaxy 21, 16 layouts: **0 dropped frames**. The core check is cheaper per explosion, and one explosion now kills fewer hostiles in the same frame.
  - Open question: test 32 first wrote its map with `@(video.row_addr(2 + gy) + 4 + gx * 2) = if explode.hits(0) '*' as ubyte else '.' as ubyte` inside two loops, and that build crashed back to the BASIC screen colors. The generated code for the expression looked right; rewritten as plain statements it works. Game code doesn't use that form.
  - Still Prog8 in the heaviest frames: handling each kill (sprite off, chain score, extra-life check; one explosion can kill 4-5 hostiles), the caught-stars part of an explosion start, the countdown-star loop in `stars.update`, and hostile steering.
- **Bounce trap** (designer report and decision, 2026-10-18; spec §6). Two stars in a row with one empty tile between them leave 7 px of room for the 13 px box, and a knockback is 18 px. Boosting into one bounced the player into the other and back, with no control (the 10-frame hit lockout even let it slide into a star), until a star exploded.
  - Now `stars.touch()` stops a knockback that started in an earlier frame when a different star is touched (`player.knock_star` holds the one that started it, 255 for a hurl bounce). There is no second bounce, and the touch still counts as a hit. Touches in the bounce's own first frame keep the old rule (both count, the bounce is away from the last one), so hitting the seam between two neighbouring stars still bounces.
  - **prog8c 12.3.4 bug found while testing this:** at the start of a sub with register arguments, `ax = dx` followed by `if dx < 0` compiled to `sta` then `bpl`, testing the flags left by the caller's last load (dy), not dx. In `player.bounce` that made every bounce with dx and dy of opposite signs go sideways (ax became e.g. 255 for dx = -1). Since phase 3, diagonal bounces off a star's side were often wrong, and they turned into straight sideways bounces, which made the two-star trap far more likely. Fixed by writing the test so it needs a fresh load (`ax = -dx`, then `if dx >= 0 ax = dx`). A scan of the generated assembly for a branch on N/Z before any flag-setting instruction at a sub's start found one more case, `explode.area_at` (`c0 = c / if c0 != 0`); there the callers happened to leave the right flags, so it never misbehaved (test 31 checks lone explosions in column 0 and row 0). Rewritten the same way. Only library assembly loops remain in the scan. **Avoid testing a just-stored sub argument as the first statement.**
  - New test 29 (readouts as tests 5-8): the player starts in the gap tile (13,5) between stars at (12,5) and (14,5), lined up with them, boosts right, keeps pushing right, then goes up. Result: 2 bounces (once off each star, each followed by a stop at the other), both stars counted 3 hits and went supernova (score 300), the player got out upwards, lives 3. Without the stop: 20 bounces and a life lost. Test 30 is the same vertically (stars at (10,4) and (10,6)): 2 bounces, lives 3; without the stop 3 bounces, then the player got out on its own, so the vertical case is milder. Not lined up (8 px off), the corrected bounce is diagonal and slips out of the gap on its own.
  - Changed numbers from the bounce fix: test 5 now starts the player lined up with the star (y 82); off by 8 px the correct bounce is diagonal and the player slid under the star after one hit. With that, the same numbers as phase 3 (countdown 105, supernova 205). Test 17 got its own script (let go during the bounce, then back off left), because the diagonal bounce sent the boosting player into a hostile and hurled it; result as before, 3,100 with chain 2. Test 9: the diagonal bounce now also makes the boosting player hit star 1 directly, so the multiplier changes come at 158, 176, 258, then drops at 397, 554, 729 (139, 157, 175 frames apart, as before); score 600. Test 10: star 5 is now hit directly and goes off at 172; the others at 158 and 258-276 (6 frames apart). Tests 1-4, 6-8, 14-16, 18, 27, 28 and the flow tests 19-20 give the same results as before.
- Regression: tests 1, 5, 14 and 17 give the same numbers as before (x 154 -> 304; countdown 105, supernova 205; hurl 185 -> 281; score 3,100). Test 12 with 8 different seeds, 45 s: 0 dropped frames, slowest frames 233 to over 255 raster lines (the readout caps at 255). One run before `NO_DEATH` (player dying, run ending early) counted 1 dropped frame; it didn't happen again in 16 more runs with deaths on or off.

## Phase 6: Quasar and invincibility
**Status:** done
**Spec:** §9

Done when:
- [x] With a debug switch forcing the chance to 100%, the quasar appears, burns out after 5 s, and pickup gives 8 s of invincibility with every listed effect.
- [x] Only one quasar per galaxy.

**Notes:**
- New module `src/quasar.p8`. `stars.supernova()` calls `quasar.chance()`: 1 in 100 (`stars.rand_below(100)`), only if this galaxy has had no quasar. It is placed on the star's tile and appears after `explode.FRAMES` frames, counted down after `explode.update`, so on the frame the explosion ends. Hurl explosions aren't supernovas and never roll. Program ends at `$4264`.
- Debug switch: `quasar.FORCE` (every supernova leaves one, still once per galaxy). Off. Tests 33-35 turn it on through `quasar.ALWAYS`.
- Quasar: sprite 7, light blue (14), 2 placeholder frames (core, flat disc, two dashed jets), a picture every 4 frames. Shown 250 frames; in the last 50 it blinks 4 frames shown, 4 hidden. Its box is a star's box (tile pixels 2-13, 12 x 12); the player box overlapping it picks it up, also while safe after a respawn, not while dying.
- Invincibility: `player.invincible` (uword, 400 frames). Stick moves at boost speed (the boost table), spin every frame, fire does nothing. `player.hurtable()` is false, so hostiles and explosions can't hurt. Glow: 8 colors (white, yellow, light green, cyan, light blue, purple, light red, orange), every 2 frames, every 8 in the last 50 frames [art phase / TUNE].
- Implementation choices (not in the spec): the pickup ends a running boost, its cooldown and a knockback, so control is back at once and fire works as soon as invincibility ends. A star touched while invincible goes off even if it is in `WARNING` (it goes supernova, not hostile) or already in `COUNTDOWN` (`stars.blow`: countdown with timer 0, set off by `stars.update` in the same frame, or the next if an explosion already started this frame). It scores as a supernova (100 x mult, multiplier +1). Hostiles touched are freed and score the next chain step (`hostiles.check_player`). The chain stays alive while invincible (the reset check in `main.play` includes `player.invincible`).
- The quasar (shown or still waiting) is removed when the galaxy clear screen starts; it stayed over the GALAXY CLEAR text before. `quasar.start_galaxy()` resets it at every galaxy start.
- **HUD countdown** (designer, 2026-10-18, after the report; spec §2, §9): a warning that invincibility is wearing off, on top of the slowing glow. A quasar icon (`icon quasar`, cyan) and the seconds left (8 to 1) in HUD columns 20-21 (`video.hud_invincible`), counted by `player.inv_secs`/`inv_frames`; cleared when it ends, at `player.init()` and at galaxy clear (invincibility ends there). The pause clears columns 18-23 and redraws it on resume. Test 34 with the normal HUD: 8 shown right after the pickup, 1 in the last second, cleared after it with the player yellow again.
- The designer agreed with the implementation choices above (2026-10-18).
- Designer played the build with `quasar.FORCE` on (2026-10-18): approved, "good for now". `FORCE` back off.
- Self-tests (`input.SCRIPTED`, `main.DEBUG_HUD`): 33 quasar appears and burns out (layout of test 5), 34 pickup and invincibility (star 0 hit, stars at (15,5) and (17,5) and a still hostile from (19,5) in the path, a fire press while invincible), 35 one quasar per galaxy (layout of test 10 in two galaxies, flow test). Readouts for 33-34 on row 0 and row 24, see `main.quasar_readouts`.
- Results: test 33: supernova, quasar shown at frame 187 at the star's tile, gone at 437 (250 frames), hidden 24 of its last 50 frames. Test 34: picked up at 363 (box x 183); 37 px in the next 10 frames (3.75 px/f boost speed); star 1 went off at 376 and star 2 at 385, each when the player reached it (no bounce: the positions match straight boost-speed travel); the hostile destroyed at 393, chain 1; the player passed through both explosions' cores, lives stayed 3; the fire press didn't start a boost (boosts stays 1); invincibility ended at 763 (400 frames); glow gap 2 frames at 300 left, 8 frames at 10 left. Score 1,900 (100 + 100 x1 + 100 x2 + 500 x3). Test 35: galaxy 1: 6 supernovas, 1 quasar (at frame 187); galaxy 2: the second one, total 2.
- Regression: tests 5 (countdown 105, supernova 205), 14 (hurl 185 -> 281), 17 (3,100, chain 2) and 20 (61,400, 4 lives) give the phase 5 numbers.
- Frame time (test 12, galaxy 21): 16 fixed seeds on the phase 5 code and on this code with the quasar roll switched off (so both play the same game): the same dropped frames in both, 1 frame in one seed, 0 in the other 15. The slowest frame is 1-2 raster lines longer with this phase's checks. The one dropped frame in a seed shows the margin at galaxy 21 is still thin (phase 5 noted the same once); the explosion animation in phase 7 has to be checked against it. One more run with the startup seed also dropped 1 frame, with no quasar in that game.

## Phase 7: Art
**Status:** not started
**Spec:** §12

Build: final sprites and chars per spec §12 (art direction decided 2026-10-18), replacing the placeholders listed in earlier notes:
- Shared char colors white + orange; specks redrawn in their own color only.
- 8 stationary star kinds as 8 distinct shapes, none like the player's 5-pointed outline.
- Hit feedback colors (hits 1 and 2), the shared 2-frame swelling star for the countdown, the red warning flash (phase 4 note: may be tweaked).
- 3-frame explosion (flash, burst, embers); on overlap the brighter frame wins (fixes the phase 3 slivers).
- Player (plain yellow star, no face) and hostile spin frames, the death effect with shrink frames (phase 5 note), the quasar, the boost and invincibility glow colors.
- HUD icons if they need it.

Frame time is the main risk: at galaxy 21, test 12 already drops 1 frame in 1 of 16 seeds (phase 6 notes). Measure with the CIA-timer profiler (`src/prof.p8`) before and after, on the same 16 seeds. Animation steps can be spread over frames (e.g. one explosion's step per frame) as long as no explosion visibly lags.

Done when:
- [ ] Screenshots of: all 8 star kinds, a star at hits 1 and 2, the swelling countdown star, a red warning, each explosion frame, two overlapping explosions, the player normal/boosting/invincible, a hostile, the quasar, the death effect.
- [ ] Test 12 at galaxy 21 on the 16 seeds: no more dropped frames than before this phase; dropped-frame count and slowest frame reported.
- [ ] The phase 3-6 regression tests give the same numbers.
- [ ] Char budget: chars used reported (spec §12).

## Phase 8: Sound
**Status:** not started
**Spec:** §13

Build: SID effects, table-driven, one voice, stepped by the frame IRQ (adapt `src/sound.p8` from Smashy Smashy): boost, star hit, supernova, hostile warning, hurl, life lost, extra life, quasar pickup, galaxy clear.

Done when:
- [ ] Every effect is triggered in a scripted run (an effect counter on the debug HUD).
- [ ] Frame time unchanged (test 12, same 16 seeds).
- [ ] Report lists which effects cut each other off, for the designer to judge by ear.
