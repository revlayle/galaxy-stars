# Pending change: title screen and attract mode

Designer request, 2026-10-18, for after phase 8. When built, merge into `spec.md` (§11 game flow, §12 assets, §13 sound) and delete this file.
Items marked **[DECIDE]** are proposals waiting for the designer. Items marked **[TUNE]** are starting values.

Designer's wishes: a logo built by stars flying in fast across the screen; HOW TO PLAY and SCORING pages; a self-playing demo as a stretch goal; the session high score stays as it is; the designer composes the music if the game can play it.

---

## 1. Attract cycle

```
TITLE (logo build, then 8 s) -> HOW TO PLAY (10 s) -> SCORING (12 s) -> [DEMO (30 s), stretch] -> TITLE ...
```
- Fire starts a game from any page, edge-triggered (a fire held from the game-over screen doesn't count). The RNG is seeded at that press, as now.
- After GAME OVER the cycle starts at TITLE.
- Page times **[TUNE]**; all page text lives in string tables in one module (`src/pages.p8`), so wording is easy to change.

## 2. Title: the star-built logo

- **Logo:** "GALAXY" and "STARS" on two lines in big block letters, 5 char rows tall each (about rows 3-7 and 10-14), 3 chars wide per letter (M, W wider if used) with 1 column between letters. Each letter "pixel" is one char: a small bright star glyph (hi-res, so it can use all 16 colors). The letter shapes are a string table in the code, like Smashy Smashy's title, so they are easy to redraw.
  - "GALAXY" is 6 letters (23 columns), "STARS" 5 letters (19 columns); both centred. About 120 star pixels in total.
- **Build:** the logo stars fly in fast from off-screen and each one becomes its logo char where it lands.
  - The flying stars are the 8 hardware sprites (a small star frame, white/yellow), each streaking in from a random point off a screen edge in a straight line to its target in about 8 frames **[TUNE]**, with the char set on arrival. A sprite is reused as soon as it lands, so 8 are always in flight: about 120 / 8 x 8 frames = 120 frames, 2.4 s.
  - Order: random, or letter by letter left to right **[DECIDE]**. Proposal: random, so the words appear out of a swarm.
  - A short sparkle on landing: the char flashes white for 2 frames, then takes its color.
  - Fire during the build skips straight to the finished logo? **[DECIDE]** Proposal: no, fire always starts a game (as on every page).
- **After the build:** the logo twinkles: a few random logo chars at a time flash white, and a color sweep rolls through the letters (yellow, orange, white, light blue) every few frames **[TUNE]**. Background specks as in the game.
- **Text:** "PRESS FIRE" blinking (row 19), "HIGH SCORE 00000000" (row 22). The player star spins under the logo as now **[DECIDE]**: proposal: keep it, centred between logo and text.
- Hi-res character mode on the title so logo chars can use all 16 colors; the game switches multicolor back on (same as Smashy Smashy).

## 3. Info pages

Both use the game's multicolor mode with real tiles and sprites, text in hi-res cells from the HUD font, as in Smashy Smashy's `pages.p8`.

- **HOW TO PLAY:** graphic at the left, text at the right:
  - player star: MOVE WITH THE STICK / FIRE TO BOOST
  - a stationary star: RAM STARS TO MAKE THEM GO SUPERNOVA / 3 BUMPS OR 1 BOOST
  - the swelling star and an explosion frame: GET CLEAR BEFORE THEY BLOW
  - a hostile: BOOST INTO HOSTILES TO HURL THEM / DON'T LET THEM TOUCH YOU
  - the quasar: GRAB A QUASAR FOR 8 SECONDS OF INVINCIBILITY
  - CLEAR EVERY STAR TO REACH THE NEXT GALAXY
- **SCORING:** SUPERNOVA 100 AND MULTIPLIER +1 (x icon), HOSTILE CHAIN 500 1000 2000 4000 8000 16000, TIME BONUS 100 PER SECOND, ALL POINTS X MULTIPLIER, EXTRA LIFE EVERY 50000. Values read from the game's tables/constants so they stay right after tuning.
- Exact wording **[DECIDE]**; lines fit in 40 columns.

## 4. Demo play (stretch goal)

A self-playing game with "DEMO" on the HUD, 30 s or until the pilot loses a life, then back to TITLE. Fire starts a real game.

Two ways; proposal: **the AI pilot** **[DECIDE]**.
- **AI pilot:** a small routine that writes joystick bits instead of `$DC00` (the scripted-input path already exists): head for the nearest idle star, boost into it, then move away from countdown stars and explosions; boost into a hostile that is close and in front; otherwise keep away from hostiles. It doesn't have to play well, just look busy and safe for 30 s. Works with any seed and keeps working after gameplay tuning.
- **Recorded input:** the designer plays, a record switch logs the joystick to RAM, and the demo replays it with a fixed seed. Looks most natural, but any change to gameplay or timing makes the replay drift out of sync, so it has to be re-recorded after tuning.
- Galaxy for the demo: galaxy 3-5, so there are hostiles to show **[TUNE]**. The demo doesn't touch the high score.
- Frame time: the pilot runs in the game's frame budget, which is thin at galaxy 21 but has plenty of room at galaxy 3-5.

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

1. Title logo with the star fly-in, twinkle and text.
2. Attract cycle with HOW TO PLAY and SCORING.
3. Demo pilot (stretch).

Music (§5) is not part of this change.

Each step ends with a build for the designer, as with the phases.
