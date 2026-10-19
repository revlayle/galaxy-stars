# Pending change: title screen and attract mode

Designer request, 2026-10-18, for after phase 8. Items marked **[DECIDE]** are proposals waiting for the designer. Items marked **[TUNE]** are starting values.

Designer's wishes: a logo built by stars flying in fast across the screen; HOW TO PLAY and SCORING pages; a self-playing demo as a stretch goal; the session high score stays as it is; the designer composes the music if the game can play it.

**Status:** steps 1 and 2 (title logo, attract cycle with HOW TO PLAY and SCORING) built 2026-10-18; step 3 (the demo, with the AI pilot) built 2026-10-18 and approved by the designer as is. All three are merged into `spec.md` §11, §12 and §14; sections 1-4 of this file are replaced by the notes below. The music plan (§5) stays here.

---

## Steps 1-2: built (notes)

- Designer decisions (2026-10-18): logo stars land in random order; fire during the logo build starts a game, as on every page; the spinning player star stays on the title.
- **7 flying stars, not 8:** the player star needs sprite 0, so sprites 1-7 fly. The logo has 93 star chars (the 3 x 5 letters of GALAXY STARS), not about 120, so the build still takes about 112 frames (2.2 s).
- Each logo char sits on the screen in black from the start and only gets its color when its star lands. The background specks skip those cells.
- Color band: yellow with a stripe of orange, white, light blue, white, orange rolling diagonally (column + row), one step every 3 frames; up to 3 random chars flash white for 3 frames, then a random wait of 0-15 frames **[TUNE]** (`title.p8`).
- Frame time: the band recolor first ran in Prog8 and took until raster line 97, past the top of the logo (line 74), so the top rows could show the color change a frame late. It is now a short assembly loop; the slowest title frame ends at line 45 (106 lines after the frame IRQ).
- **Wording changes** (the proposal didn't fit or read well; the exact wording was **[DECIDE]**):
  - "CLEAR EVERY STAR TO REACH THE NEXT GALAXY" is 41 characters; it is "CLEAR ALL STARS TO REACH THE NEXT GALAXY" (40).
  - "BOOST INTO HOSTILES TO HURL THEM" doesn't fit after the graphics column; it is "HURL HOSTILES WITH A BOOST / DON'T LET THEM TOUCH YOU".
  - Added a line before "GET CLEAR BEFORE THEY BLOW": "HIT STARS SWELL, THEN EXPLODE".
  - SCORING shows no high score (the title does).
- HOW TO PLAY and SCORING sprites spin (player, hostile) and the quasar animates; the explosion shown is its burst frame.
- Self-tests (in `main.p8`, need `input.SCRIPTED`): 38 runs test 19's flow, then holds fire from the game-over screen for 500 frames into the title (no game starts, the cycle goes on); 39 runs the attract cycle from power-on with fire on page `main.ATTRACT_FIRE` (1 title during the build, 2 HOW TO PLAY, 3 SCORING, 4 second title).
- Checked by screenshot: the logo mid-build and finished; HOW TO PLAY, SCORING, the next TITLE (logo rebuilt) and HOW TO PLAY again in a run with no input; fire on each of the 4 pages starts GALAXY 01 in multicolor with a new random layout; test 38: GAME OVER, then the title with the updated high score (6,000) stays up while fire is held, then HOW TO PLAY and SCORING follow.

## Step 3: built (notes)

- Designer decision (2026-10-18): the AI pilot, not recorded input. `src/demo.p8`; the pilot's rules are in `spec.md` §11.
- **Ends after GALAXY CLEAR too:** the pilot usually clears galaxy 3-5 before the 30 s are up, so a cleared galaxy shows GALAXY CLEAR (with the time bonus) and then the demo ends. Not in the proposal.
- **Stars turning hostile are threats, not targets:** an early version also went for WARNING stars; a hostile appearing under the walking player killed it. They now push the pilot away (32 px) and are never targets.
- **Sound effects play in the demo** (the rest of the attract cycle is silent). Designer, 2026-10-18: keep them.
- DEMO sits in HUD columns 16-19, not after the invincibility field: a quasar pickup in the demo put its counter right against the word ("+1DEMO").
- Frame time: the first pilot compared every star against every countdown and explosion and took up to 250 raster lines on chain-reaction frames (7 overrun frames in 8 games). Now threats are filtered by tile in assembly, at most 8 weighed, the distance is assembly, and the next-star search is spread over frames (up to 2 stars, one tile check a frame): at most 91 lines (including any frame IRQ that falls inside), 0 overrun frames in 40 games.
- Self-tests: 39 has two more fire pages, `main.ATTRACT_FIRE` 4 (150 frames into the demo) and 5 (the title after the demo); 40 plays 16 demo games in a row (`main.DEMO_SEED` fixes the seed) and shows a table (galaxy (+1 after a clear), frames played, stars, stars left, hostiles destroyed, lives lost (a symbol when it gained lives), overrun frames, distances at a death, stick direction changes, the pilot's slowest frame). `demo.FREEZE_AT_DEATH` stops at the first death with the pilot's state on the HUD row and the nearby threats on row 24.
- **Results before the smoothing** (test 40, 5 runs of 8 games, the RNG running on): 0 lives lost in 40 games; 33 cleared the galaxy, after 14.6-29.5 s; 7 played the full 30 s with 1-2 stars left; 2-5 hostiles destroyed per game (hurls and explosions). An earlier pilot (before the changes above) lost a life in 3 of 24 games (at 4 s, 12 s and 16 s); the one with a readout was touched by a hostile.
- **Smoothing** (designer, after watching: "really fast back and forth movements, it looks jerky"): the pilot decided its direction from scratch every frame, so near a boundary (straight vs diagonal towards a star, approach vs flee at a flee distance) it flipped almost every frame: 450-840 direction changes in a 30 s game. Now a new direction is held 8 frames while walking to a star, and after a flee.
  - Tried first: holding every direction, also while fleeing (with an override for close threats, then also for turns over 45 degrees near a blast). It lost more lives; a frozen death showed why: between two explosions only one way out is safe, and a held direction 45 degrees off leads into one of them. So fleeing and hostile hunts react every frame.
  - Also added: a boost while fleeing from a close threat (16 px inside its distance). A frozen death had the pilot trapped at the top edge between a countdown star and a hostile it couldn't hurl.
  - **Result** (test 40, 3 fixed seeds x 16 games, the same seeds with and without the hold): direction changes per game 70-400, mostly about 140 (without the hold 450-840); lives lost 4 of 48 with the hold, 2 of 48 without (too few to call a difference); 0 overrun frames; the pilot's slowest frame 75-85 raster lines.
- **It plays better than "not well":** it clears most galaxies. Designer, 2026-10-18: fine as is.
- Checked by screenshot: the demo's GALAXY 05 start, play with explosions, a hostile and the multiplier at x8-x9, its GALAXY CLEAR, then TITLE with the high score unchanged (0 after power-on; 6,000 after test 38's game, through two demos); fire 150 frames into the demo starts GALAXY 01 with a new layout and no DEMO on the HUD (test 39, page 4); the title after the demo starts a game on fire (page 5); test 38's held fire still doesn't start a game, and the cycle runs on through the demo.

## 5. Music (later, not in this change)

Designer, 2026-10-18: no music for starters; the title and attract mode are silent. This section is kept as the plan for when the designer has a tune. The designer composes; the game plays it. Proposal:
- **Tool: GoatTracker 2** (free, Windows, the most common C64 tracker). Any tracker works if it exports a standard player with an init and a play address (SID-Wizard, CheeseCutter); a `.sid` file works too, the build strips its header.
- **Export:** a binary relocated to a fixed address below `$C000`, e.g. `$A000` **[DECIDE]** (the program ends around `$4A00`, so there is room), using zero-page addresses the game doesn't use (to be picked from the Prog8 zero-page map when this is built). Saved as `assets/music/title.bin` (or `.sid`).
- **Playback:** included with `%asmbinary` in a block at that address; `init` called with the song number on entering the title, `play` once per frame from the frame IRQ. Silenced when a game starts.
- **Where it plays:** title and attract pages first. **In-game music [DECIDE]** has two costs:
  - Voices: the sound effects use voice 1, so in-game music would have to use only voices 2 and 3 (GoatTracker can compose for 2 channels), or the effects interrupt it.
  - Frame time: a player routine typically takes 1,500-3,000 cycles per frame (20-40 raster lines). At galaxy 21 the slowest frames have only a few lines to spare, so in-game music would need more optimisation or lighter difficulty peaks first.
  - Proposal: title/attract music now; in-game music as a separate later change if wanted, after measuring.
- Also possible with the same player: a short jingle for GALAXY CLEAR and GAME OVER (those screens have time to spare).

## 6. Build order

1. Title logo with the star fly-in, twinkle and text. **Built.**
2. Attract cycle with HOW TO PLAY and SCORING. **Built.**
3. Demo pilot (stretch). **Built.**

Music (§5) is not part of this change.

Each step ends with a build for the designer, as with the phases.
