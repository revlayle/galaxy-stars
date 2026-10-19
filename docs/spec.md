# Technical spec: Galaxy Stars

A single-screen C64 action game. The player is an alien (a spinning yellow star) who slams into the stars of each galaxy to make them go supernova, while stars that turn hostile chase them.

Source design: `galaxy-star-basic-spec.txt`. This document turns it into implementation decisions for Prog8 12.3.4 on a PAL C64.
Items marked **[DECIDE]** are proposals waiting for the designer's confirmation. Items marked **[TUNE]** are starting values expected to change after playtesting.

In the game a level is always called a **galaxy**. This document says "level" and "galaxy" interchangeably.

---

## 1. Platform and timing

- Target: PAL C64, 50 frames/s, Prog8 `-target c64`, 64tass. NTSC is not a goal (timers and speeds would run 20% fast).
- One game update per frame. Frame sync: a raster IRQ at line 251 (bottom border) copies the sprite shadow registers to the VIC, steps the sound effect, counts frames and sets a `frame_ready` flag; the main loop waits on it. It does not chain to the KERNAL IRQ.
- Per-frame order: wait for frame → read joystick → update player → update hostile stars → contacts (player vs stars, player vs hostiles, explosions vs everything) → star timers (counters, countdowns, warnings) → explosions → queued tile redraws → HUD (only changed digits) → compute sprite shadow registers for next frame.
- Frame budget is roughly 18,000 CPU cycles.
- 1 second = 50 frames. All timers count frames, or seconds plus a 50-frame subcounter.

### Number rules
- **No floating point anywhere.** Do not `%import floats`.
- Prefer `ubyte`/`byte`. Use `uword` only where a value can exceed 255, such as an x pixel (0-319).
- Multiply and divide only by powers of two (shifts), or use lookup tables. No general `*` or `/` in per-frame code. Multiplying at level start (speed tables) is fine.
- **Speeds are signed bytes in 1/16-pixel steps** ("subpixels"): 24 means 1.5 px per frame. Each actor stores a whole-pixel coordinate plus a `ubyte` fraction (0-15). Each frame: `frac += speed`, carry `frac >> 4` into the pixel coordinate, keep `frac & 15`.

## 2. Screen layout

```
char row 0        HUD: SCORE 00000000        @60    x1    *3
char rows 1-24    playfield: 20 x 12 tiles, each tile 2x2 chars (16x16 px)
```

- HUD fields (left to right): score (8 digits), time left (clock/hourglass icon + 2 digits), multiplier (small stylised x icon + 1 digit), lives (yellow star icon + 1 digit). Columns: `SCORE` label 1, digits 7-14; time icon 27, digits 28-29; multiplier icon 32, digit 33; lives icon 36, digit 37.
- The galaxy number is not on the HUD; it is shown at the start of each galaxy (§11).
- While invincible: quasar icon in column 20 and the seconds left in column 21 (§9).
- The three icons are custom hi-res chars, one char each: an hourglass or clock, an x drawn small and centred in the 8x8 cell, and a 5-pointed star in yellow (7). HUD text and digits stay white.
- Playfield is 320 x 192 px, in playfield coordinates `px 0..319`, `py 0..191`. `(0,0)` is the top-left of tile `(0,0)` at char row 1.
- Hardware sprite position for an object whose 24x21 frame starts at `(px, py)`: `sprite_x = px + 24`, `sprite_y = py + 50 + 8` (the +8 is the HUD row).
- Player start: centre of the playfield (the art's centre pixel, frame pixel 10,10, is placed there; sprite top-left `px 150, py 86`). The centre is the corner where tiles (9,5), (10,5), (9,6), (10,6) meet: `px 160, py 96`.

### Graphics modes
- **Characters: multicolor character mode** ($D016 bit 4). Shared colors: background $D021 (black), MC1 $D022, MC2 $D023. Color RAM values 8-15 make a cell multicolor, 0-7 hi-res. HUD text stays crisp hi-res. Multicolor cells limit each tile's own color to 0-7; the shared colors can be any of the 16.
- **Sprites: hi-res** (single color, 24x21). The player and hostile stars are star shapes that need the full resolution for clean points and smooth rotation. The quasar (sprite 7) is multicolor (phase 7): `$D01C = $80`, `$D025` white (its core), `$D026` cyan (its jets), its own color light blue (its disc).

## 3. Memory map

Same scheme as Smashy Smashy: the VIC-II in **bank 3 ($C000-$FFFF)**, the program in one contiguous block below it.

| Range | Use |
|---|---|
| `$0002-$00FF` | Zero page: KERNAL plus Prog8 variables |
| `$0801-$BFFF` | Prog8 program: code, tables, asset data. `%memtop $C000` |
| `$C000-$C3E7` | Screen matrix |
| `$C3F8-$C3FF` | Sprite pointers |
| `$C400-$CFDF` | Game RAM: tile map, star tables, explosion list, buffers |
| `$CFE0-$CFFF` | **Reserved by Prog8** for virtual registers R0-R15. Do not touch |
| `$D000-$DFFF` | I/O |
| `$E000-$E7FF` | Charset (256 chars), in RAM under KERNAL ROM |
| `$E800-$FFBF` | Sprite frames: 95 frames (pointer values 160-254) |

- `$DD00` bits 0-1 = `%00` (bank 3), `$D018 = $08` (screen at +$0000, charset at +$2000).
- The charset and sprites are included with `%asmbinary` and copied to `$E000`/`$E800` at startup (CPU writes go to RAM under the ROM).
- **Prog8's `txt.*` routines are hard-wired to `$0400`** and must not be used after the switch. The game draws through its own pointer routines into `$C000` and color RAM `$D800`.
- The game reads Run/Stop from the keyboard matrix itself; no KERNAL calls in game code.

## 4. Data structures

### Tile map
`&ubyte[240] tiles = $C400`: 20 x 12, index `row * 20 + col` via a 12-entry `row_start` table. One byte per tile:

| Value | Meaning |
|---|---|
| 0 | empty (draws as blank or a background speck, see §10) |
| 1 + i | stationary star with index `i` (0-44) |

Background specks have their own map, `&ubyte[240] specks = $C500`: 0 = none, else `(speck kind + 1) << 2 | char` (char 0-3 = TL, TR, BL, BR of the tile).

Explosion cover map, `&ubyte[240] cover = $C600`: the number of active explosions drawn over each tile. Star color changes skip covered tiles, and a tile is redrawn from the tile map when its last explosion ends.

Explosion owner map, `&ubyte[240] owner = $C700`: the slot of the newest explosion over each tile; only that one draws its animation frames there (§12).

### Stationary stars
Parallel arrays, up to 55 entries: `col`, `row`, `kind` (art type 0-7), `state`, `hits` (supernova counter), `timer` (frames). States:

| State | Meaning |
|---|---|
| `IDLE` | stationary, can be hit, can be picked to go hostile |
| `WARNING` | flashing red for 1 s, then becomes a hostile star (§7) |
| `COUNTDOWN` | supernova process running, explodes when the 2 s timer ends (§6) |
| `GONE` | exploded or turned hostile; tile cleared |

`stars_left` counts stars not yet destroyed: stationary stars not `GONE` plus active hostile stars. The galaxy is clear when it reaches 0.

### Actors and sprites
| Sprite | Use |
|---|---|
| 0 | player |
| 1-6 | hostile stars (max 6 at a time) |
| 7 | quasar |

Actor arrays (index 0 = player, 1-6 = hostiles): `uword x`, `ubyte y` (top-left of the 24x21 frame), `x_frac`, `y_frac`, `byte vx, vy`, `state`, `anim_frame`, `anim_timer`, `spin_dir`.
- The player keeps its own variables in `player.p8`, and its `x`, `y` are the top-left of its 13 x 13 collision box (frame pixel 4,4), so the box clamp is `x 0..307`, `y 0..179`. The sprite frame starts 4 px up and left of it.
- Hostiles have their own arrays in `hostiles.p8` (slot 0-5 = sprite 1-6). Their `x`, `y` are the top-left of the 12 x 12 box, also at frame pixel 4,4 (clamp `x 0..308`, `y 0..180`). A new hostile's box is the box of the star it came from.

### Collision boxes [TUNE]
- Player: 13 x 13 centred in the 21 x 21 art (corners of the star don't count).
- Hostile star: 12 x 12 centred in its art.
- Stationary star: 12 x 12 centred in its 16 x 16 tile.
- Explosion: the 3 x 3 tiles around the exploding star, 48 x 48 px, clipped to the playfield, for stationary stars. For the player and hostile stars only its round core counts (§6).
- All checks are box overlap math in software. Hardware sprite collision registers are not used.

## 5. Player

### Movement [TUNE]
| Parameter | Value |
|---|---|
| Normal speed | 24 subpx/f (1.5 px/f, ~4.3 s across the screen) |
| Boost speed | 2.5 x normal = 60 subpx/f (3.75 px/f) |
| Boost length | 1.5 s = 75 frames |
| Boost cooldown | 0.5 s = 25 frames, counted from when the boost ends |
| Diagonal | each axis at 181/256 of the speed (constant table, no multiply per frame) |

- 8-direction joystick movement, no inertia: the player moves while the stick is held and stops when it's released. Full control during boost.
- Fire is edge-triggered: a press starts a boost if no boost is running and the cooldown is over. Holding fire does nothing more.
- The player can't leave the playfield (box clamped to `px 0..319`, `py 0..191`). Hostile stars and explosions can still reach them at the edges.
- Stationary stars are solid to the player (§6, bounce).

### Spin animation
- The player is a 5-pointed yellow star. A 5-pointed star repeats every 72°, so one rotation cycle is 6 frames of 12° each **[TUNE]**.
- Moving with any left component spins counter-clockwise; any right component, clockwise. Moving straight up or down keeps the last direction (clockwise at the start of a game).
- Spins only while moving: next frame every 3 game frames at normal speed, every frame while boosting **[TUNE]**.
- Invincible (§9): the sprite color cycles rapidly through a color table (every 2 frames).
- **Boost glow:** while boosting the player glows through bright colors (white, yellow, orange), cycling every 2 frames; normal color is yellow **[TUNE]**. Nothing marks the cooldown.

## 6. Stationary stars and supernovas

### Hitting a stationary star
- When the player's box touches an `IDLE` or `WARNING` star's box:
  - The star's `hits` goes up by **1** at normal speed, by **3** while boosting.
  - At `hits >= 3` the star enters `COUNTDOWN` (2 s = 100 frames).
  - A `WARNING` star that is hit: a hit that brings `hits` to 3 cancels the warning and starts the countdown (it goes supernova instead of hostile); a +1 hit that stays below 3 only adds to its counter and it turns hostile as planned.
- **Bounce:** the player is pushed away from the star: knockback of 3 px/f for 6 frames, away from the star centre in the nearest of 8 directions, with no joystick control during the knockback **[TUNE]**. A boost that is running keeps its remaining time.
- A star only counts one hit per contact: after a bounce, the same star can't count again for 10 frames **[TUNE]**.
- **No bounce trap** (designer, 2026-10-18): touching a different star during a knockback (one that started in an earlier frame) stops the knockback there instead of bouncing again, and control returns at once. That touch still counts as a hit (+3 while boosting). Without this, a player lined up between two stars with one empty tile between them bounced back and forth with no control until a star exploded. (A compiler bug that turned diagonal bounces into sideways ones made this much more frequent; fixed, see the phase 5 notes.)
- Touching a star already in `COUNTDOWN` bounces the player but adds nothing.
- Counter feedback: `hits` 1 and 2 change the star's own color (yellow, then white; yellow and white stars: white or yellow, then cyan). `COUNTDOWN`: the star turns into the swelling star (§12).

### Supernova
- Explosions also come from hostiles hurled by a boost (§7); they behave the same.
- When a countdown ends, the star explodes: tile cleared, star `GONE`, an explosion starts covering the 3 x 3 tiles around it.
- An explosion lasts 0.6 s = 30 frames and is dangerous for its whole duration **[TUNE]**. It is drawn with explosion chars over the 3 x 3 tiles (animated: flash, burst, embers, §12) and the tiles are restored afterwards.
- While an explosion is active:
  - **Round core** (designer, 2026-10-18): the player and hostile stars are hit only when their centre is within 22 px of the explosion's centre (the centre of its centre tile), measured as the longer axis distance plus half the shorter, an octagon close to a circle **[TUNE]** `explode.REACH`. The bright part of the art is about 36 px across. Before, any overlap of the 13 x 13 box with the 48 x 48 square counted, corners included, so the player died touching only the empty corners or the faint fringe. A hostile diagonally next to the exploding star (centre about 23 px away) is now outside the core.
  - **Player** in the core: loses a life (§8), unless invincible.
  - **Hostile star** in the core: destroyed, scores in the hostile chain (§8). Also a hostile flying into an explosion that is still active.
  - **Stationary star** (`IDLE` or `WARNING`) whose tile is in the 3 x 3 area: goes straight to `COUNTDOWN` with the full 2 s (the notes: "essentially adding 3 to the counter"). Stars already in `COUNTDOWN` keep their timer.
  - **Staggered chains** (designer, 2026-10-17): when one explosion sends several stars into their countdown, they go off one after another, in random order: the first gets the full 100 frames, each further one 6 frames more (`stars.STAGGER`) **[TUNE]**. This makes the chain reaction visible and keeps the frame rate smooth.
- Up to 8 explosions at once (list in game RAM) **[TUNE]**; with 55 stars a chain reaction can be wide but each step takes 2 s, so 8 should be plenty. If the list is full, the new explosion takes the oldest slot.
- Frame time: at most one explosion starts per frame. A further supernova that is due waits a frame, and a hurled hostile whose flight is over waits in place. The tiles under an ended explosion are restored through a queue, one explosion per frame; its danger ends on time.

## 7. Hostile stars

### Turning hostile
- A spawn timer picks a star to go hostile every interval: galaxy 1 = 6.0 s, then 0.25 s less per galaxy, never below 1.0 s (galaxy 21 and up). Designer, 2026-10-18: the ramp was twice as steep (1.0 s at galaxy 11) and got hard suddenly around galaxy 7.
  - Interval in frames: `max(50, 300 - 12.5 * (galaxy - 1))`, the half frame rounded up.
- Only when fewer than 6 hostile stars (and warnings) are active; otherwise the timer waits at 0 and fires as soon as a slot is free. A hurled hostile keeps its slot until it explodes.
- Which star: a random `IDLE` star at least 4 tiles from the player (in both directions, i.e. outside a 9 x 9 tile box around them), or any `IDLE` star if there is none that far.
- The chosen star goes to `WARNING`: it flashes red (color RAM, alternating with its own color every 4 frames) for 1 s, then its tile is cleared and a hostile star sprite appears at its position and starts chasing. The original star is gone.

### Movement [TUNE]
- Speed per galaxy, as a fraction of the player's normal speed (24): galaxy 1 = 50% (12), galaxy 21 = 120% (29), linear in between: 12, 13, 14, 15, 15, 16, 17, 18, 19, 20, 20, 21, 22, 23, 24, 25, 25, 26, 27, 28, 29 (designer, 2026-10-18: was galaxy 11).
- After galaxy 21 the speed stays at 29 (120%).
- Steering: each hostile has a heading (one of 16 directions) and turns one step towards the player every 4 frames, so they curve after the player and can be dodged rather than tracking perfectly. The 16-direction velocity table is built at galaxy start from the speed. A new hostile starts heading straight at the player; when the player is exactly behind it, it turns clockwise.
- Hostile stars pass over stationary stars and each other (no collisions between them).
- The red 4-pointed star spins like the player (left = counter-clockwise, right = clockwise), 6 frames of 15° (a 4-pointed star repeats every 90°).

### Contact with the player
- Player **not** boosting and not invincible: the player loses a life (§8).
- Player **boosting**: the hostile is **hurled** away and then explodes:
  - Direction: the player's movement direction (8 directions) at the moment of contact; if the player isn't moving, straight away from the player (nearest of 8 directions, player centre → hostile centre).
  - It flies at 6 px/f for up to 16 frames (96 px, about 6 tiles) **[TUNE]**.
  - **The player bounces** off the hurled hostile like off a stationary star (designer, 2026-10-18): the knockback of §6, straight back, opposite the hurl direction. The boost keeps its remaining time.
  - **Where it explodes** (designer, 2026-10-18): it flies through stationary stars, like chasing hostiles do. It flies through other hostiles for its first 8 frames (48 px) **[TUNE]**; after that it explodes early on touching a hostile (not one that is itself being hurled). Otherwise it explodes at the end of the flight. Before this, a hostile hurled over or next to a star exploded on the spot and caught the player every time.
  - **Off the edge** (designer, 2026-10-18): when its box reaches a playfield edge it flies on off the screen (7 more frames, hidden by the border) and is gone, with no explosion. Its kill was already scored at the hurl.
  - The explosion is a normal explosion (§6): the 3 x 3 tiles around the tile under the hurled star's centre, 30 frames, with every effect of a supernova explosion. It can kill the player, destroys hostiles caught in it (chain scoring, §8) and sends stationary stars in it into their countdown, so hurls start chain reactions.
  - It is not a supernova: no 100 points, no multiplier raise, no quasar chance.
  - While flying it is harmless to the player, spins fast, and can't be hit again. Explosions it flies through don't affect it.
  - Every hostile the boosting player touches is hurled, each in its own flight. Because of the bounce, a boost into a pack usually hurls only the first one it touches (more if several are touched in the same frame, or after the knockback while the boost still runs).
- A hurled hostile scores the next chain step (§8) when it is hit, and counts as destroyed at that moment (`stars_left` goes down then), so the galaxy can be cleared while one is still flying.
- Player invincible: any hostile touched is destroyed at once and counts in the hostile chain.

## 8. Scoring, multiplier and lives

### Score
- Every score value is a multiple of 100, so the score is stored in hundreds as BCD (3 bytes = 6 digits) and the HUD appends "00": 8 digits, max 99,999,900.
- Every score event is multiplied by the current multiplier. With the multiplier at most 9, the BCD value is just added `mult` times (no multiply).

| Event | Base points |
|---|---|
| Star goes supernova (any cause, including chain reactions) | 100, then multiplier +1 |
| Hostile destroyed by a supernova | 500, doubling for each further hostile in the same chain: 500, 1000, 2000, 4000, 8000, 16000, ... |
| Hostile hurled by boost (scores when hit; its explosion scores nothing itself) | same chain as above |
| Hostile destroyed by the invincible player | same chain as above |
| Galaxy clear bonus | 100 x seconds left (0 when the timer has run out) |

- Supernova event: the 100 is multiplied by the multiplier *before* the +1.
- Galaxy clear bonus: multiplied by the multiplier like every other event; the multiplier resets to x1 after it is added.
- **Chain:** one shared chain counter for every hostile kill: supernova kills, boost hurls, kills by a hurled star's explosion and invincibility kills all add to it, and each kill scores the next doubling step. The chain stays alive while any of these is going on: an explosion is active, a star is in a countdown that was started by an explosion, a hurled hostile is still flying, or the player is invincible. When none of them is, the chain resets, so the next kill scores 500 again. **[TUNE]**
- Chain cap: the doubling stops at the 6th kill (16,000), the most hostiles at once; further kills in the chain score 16,000 each **[TUNE]**. Designer, 2026-10-18: was the 8th kill (64,000), which made one chain worth 127,500 x multiplier and scores of 600,000+.

### Multiplier
- Starts at x1, max x9. Resets to x1 at the end of each galaxy, and at the start of a new game.
- Only supernovas raise it (+1 each). At x9 a supernova doesn't raise it but restarts the drop timer.
- When above x1 it drops by 1 after a time without a raise. The time depends on the current value, linear from 1 s at x9 to 3.5 s at x2 **[TUNE]**:

| Mult | x9 | x8 | x7 | x6 | x5 | x4 | x3 | x2 |
|---|---|---|---|---|---|---|---|---|
| Frames | 50 | 68 | 86 | 104 | 121 | 139 | 157 | 175 |

- Each raise restarts the timer for the new value. Each drop starts the timer for the lower value.
- Losing a life resets the multiplier to x1.

### Lives
- 3 at the start, max 9 (the HUD shows one digit).
- Extra life every 50,000 points (at 50,000, 100,000, ...; designer, 2026-10-18: was 20,000), constant `score.EXTRA_LIFE_EVERY` (in hundreds) **[TUNE]**. Past 9 lives, no extra life is given, but the next threshold still moves on.
- A life is lost when the player is touched by a hostile star while not boosting, or is caught in an explosion. Invincibility protects from both.
- **Losing a life** (designer approved):
  - The player sprite flashes/shrinks for 1 s while everything else keeps running (explosions, countdowns, hostiles), then reappears in the centre.
  - The galaxy timer keeps running.
  - The player is safe for 2 s after reappearing (sprite blinks): hostiles pass through them harmlessly and explosions don't hurt. Hitting stars works normally.
  - **Respawn push** (designer, 2026-10-17): when the player reappears, every hostile (not one being hurled) inside the box around the centre, 80 px left and right and 64 px up and down (10 x 8 tiles), is pushed straight out from the centre (nearest of 16 directions) at 6 px/f until it is outside the box; the playfield edges stop it **[TUNE]**. Pushed hostiles are not hurt and score nothing.
  - **Hold** (designer, 2026-10-17): during the 2 s of safety hostiles hold still (spinning in place), including ones that appear then, and chase again when it ends. Without this, a hostile at top speed (1.8 px/f) gets back to the centre within the 2 s. A hostile counts as inside the push box by its centre; held hostiles keep turning towards the player, so they set off straight at them when the safety ends.
- The life is taken at the hit (the HUD shows the new count at once). During the death effect the player has no control and touches nothing; boost and cooldown are cleared. A boost during the 2 s of safety still hurls hostiles (designer, 2026-10-17).
- No lives left → game over (§11) when the last death effect ends.
- One score event can pass several extra-life thresholds: a life for each, up to 9. At the maximum score the thresholds stop.

## 9. Quasar and invincibility

- Each supernova has a 1 in 100 chance to leave a quasar at the star's position, at most once per galaxy (and only if no quasar has appeared this galaxy). It appears when the explosion ends, so the player doesn't have to enter the explosion to grab it.
- The quasar is sprite 7 and burns out after 5 s (blinking in the last second **[TUNE]**).
- Player touches it → invincible for 8 s:
  - Always moves at boost speed in the stick direction (no fire needed, fire does nothing).
  - Stationary stars touched explode at once (supernova with no countdown; scores as a supernova). The player passes through them instead of bouncing.
  - Hostile stars touched are destroyed and count in the hostile chain (§8).
  - Explosions and hostiles can't hurt the player.
  - The sprite glows through multiple colors rapidly.
  - In the last second of invincibility the glow slows down as a warning.
  - **HUD countdown** (designer, 2026-10-18): while invincible, the HUD shows a quasar icon (cyan, hi-res) and the seconds left, 8 down to 1, in columns 20-21 (the free middle, shared with PAUSED). It clears when the invincibility ends.
- A 1 in 100 chance means a quasar shows up in roughly a third of galaxies at 45 stars, more at 55, and fewer at 15 **[TUNE]** if it should be more common.
- Details (phase 6): the quasar's box is a star's box (12 x 12 in its tile); the player can pick it up while safe after a respawn, not while dying. The pickup ends a running boost, its cooldown and a knockback. A star touched while invincible goes off at once whatever its state (a `WARNING` star goes supernova instead of hostile, a `COUNTDOWN` star skips the rest of it); like every explosion start, it waits a frame if another explosion already started that frame. The glow cycles 8 colors every 2 frames, every 8 frames in the last second **[TUNE]**. A quasar still shown when the galaxy is cleared goes away with the clear screen. Debug switch `quasar.FORCE` makes every supernova leave one (still once per galaxy).

## 10. Galaxies

- Galaxy `n` has `min(55, 15 + 2 * (n - 1))` stars (55 from galaxy 21; designer, 2026-10-18: was 45 from galaxy 16).
- Placement: random free tiles, never in the 4 x 4 tiles around the player's start (tile columns 8-11, rows 4-7). Stars may be next to each other (chain reactions).
- Each star gets a random `kind` (art type 0-7).
- Background specks: about one empty tile in four shows a faint speck (1-px dots, blue, in a hi-res cell; phase 7) in one of its 4 chars **[TUNE]**. Specks are decoration only: they live in the screen, not the tile map, and are redrawn when a tile is restored.
- 60 seconds per galaxy. At 0 the timer stops; play continues with no penalty and no clear bonus.
- RNG: Prog8's `math.rnd()`, seeded from the raster line and frame counter when fire is pressed on the title screen.

## 11. Game flow

```
TITLE --fire--> NEW_GAME --> GALAXY_START --> PLAYING
PLAYING --stars_left = 0--> GALAXY_CLEAR --> GALAXY_START (galaxy + 1)
PLAYING --no lives left--> GAME_OVER --fire--> TITLE
```
- **TITLE:** "GALAXY STARS" (yellow), the player star spinning under it, "PRESS FIRE" blinking, "HIGH SCORE" with the session high score, faint background specks. No attract pages for now (designer, 2026-10-17: may be expanded later). Fire (edge-triggered) starts a game.
- **GALAXY_START:** "GALAXY 01" above the player (char row 9) for 2 s while the stars appear in random order, one per frame **[TUNE]**; the player sits in the centre. No control, timer not running. Then PLAYING.
- **PLAYING:** as described above.
- **Last star destroyed** (designer, 2026-10-17): the timer and the multiplier stop at once. Play goes on (the player keeps control and can still be hurt) until no explosion is running, no hurled hostile is flying and no death effect is playing. A death meanwhile resets the multiplier before the bonus; if it was the last life, it is game over.
- **GALAXY_CLEAR:** "GALAXY CLEAR", "TIME BONUS <n>" (the total added: seconds x 100 x multiplier) with the bonus added, 3 s, then the multiplier resets and the next galaxy starts **[TUNE]**. The galaxy number is shown up to 99.
- **Pause:** Run/Stop toggles pause during PLAYING; everything freezes, "PAUSED" shown in the empty middle of the HUD row.
- **GAME_OVER:** "GAME OVER" and the high score (already including this game) over the frozen playfield; fire accepted after 1 s → TITLE.
- **Session high score** in RAM, shown on the title and game-over screens.

## 12. Assets

### Sprites (hi-res 24x21, art up to 21x21)
| Set | Frames |
|---|---|
| Player spin (plain yellow 5-pointed star, no face; 0°-60° in 12° steps) | 6 |
| Hostile spin (4-pointed star, 0°-75° in 15° steps) | 6 |
| Player lost-a-life effect (shrink) | 3 |
| Quasar (multicolor) | 4 |
| **Total** | 19 (of 95) |

Clockwise spin plays the frames forward, counter-clockwise backward.

### Chars (2x2 per tile, multicolor)
- **Shared char colors** (designer, 2026-10-18): `$D022` = white (1) for hot cores, `$D023` = orange (8) for glows and rays. They apply to every multicolor char: stars, explosion, specks.
- **8 stationary star kinds**, 8 distinct shapes (not shapes x colors): small dot, 4-ray flare, 8-ray flare, ringed star, binary pair, large giant, diamond pulsar, soft-glow nebula star. White core and orange glow from the shared colors; the kind's own color (0-7) mostly realistic star colors (white, blue, yellow, cyan), purple and green sparingly. Red (2) is kept for the hostile warning flash. None of them may look like the player's 5-pointed outline: the player must stand out from the stationary stars.
- **Hit feedback:** hits 1 and 2 change the star's own color only (extra shapes for 8 kinds don't fit the char budget).
- **Countdown "swelling" star:** one shared tile, 2 frames (8 chars), that every kind turns into for its 2 s countdown, flashing faster near the end, then explodes from. Phase 7: it alternates big/white and small/yellow every 8 frames; in the last half second it stays big and flashes white/yellow every 2 frames by color only (frame time: many stars can be in their last half second at once) **[TUNE]**.
- **Explosion:** 3 x 3 tiles = 6 x 6 chars per frame, 3 frames: small white flash, full orange burst, fading embers. Own color yellow (7). Where explosions overlap, the brighter frame (flash > burst > embers) wins on shared tiles, so no stray slivers. Phase 7: flash for 6 frames, burst for 14, embers for the last 10 **[TUNE]**. Every explosion runs the same timeline, so the newest one over a tile is the brightest; it owns the tile (`owner` map, §4). Frame time: at most one explosion changes frame per frame, and a change waits while that frame starts or restores an explosion, at most 4 frames.
- **Background specks:** 5 chars, own color only (no shared-color pixels), so they stay faint under the white/orange shared colors. Phase 7: hi-res chars (1-px dots), blue (6); their cells have no multicolor bit.
- **Star kinds** (phase 7, own colors): 0 small dot yellow, 1 4-ray flare white, 2 8-ray flare cyan, 3 ringed star purple, 4 binary pair cyan, 5 large giant yellow, 6 diamond pulsar green, 7 soft-glow nebula star blue.
- **Sprites** (phase 7): player a plain filled 5-pointed star; hostile a 4-pointed star with a hole in the middle (a shuriken); death effect: 20 frames flashing at full size, then 3 shrink frames of 10 frames each; quasar: white core, light blue disc, cyan jets, 4 frames (the jets' blobs move out, two bright spots turn in the disc).
- Char budget: 192 free chars (64-255). 8 star kinds (32) + swelling star (8) + 3 explosion frames (108) + 5 specks + 4 icons = 157, leaving 35 spare.
- HUD font: ROM screen codes 0-63 copied to chars 0-63 at startup, plus 3 hi-res icon chars (time, multiplier, lives; §2).

### Pipeline
Same as Smashy Smashy: editable text art in `assets/sprites.txt` and `assets/tiles.txt`, converted by `tools/gfx.py` into `build/sprites.bin`, `build/chars.bin` and `src/gen_assets.p8` (name constants like `SPR_PLAYER_0`, `TILE_STAR_0_TL`, `CHAR_SPECK_0`). Entries: `sprite` (24 x 21 hi-res, `.` and `1`), `tile <name> color <0-7> [size WxH]` (multicolor, 8 fat pixels x 16 rows per tile; the explosion is one 3x3 entry), `char` (one multicolor char) and `icon` (one hi-res char for the HUD). The format is described at the top of each art file. Claude draws all the art (designer, 2026-10-18); everything stays editable text so the designer can redraw any of it in a text editor.

## 13. Sound

Basic SID effects only, no music, built in phase 8: boost, star hit, supernova, hostile warning, hurl, life lost, extra life, quasar pickup, galaxy clear. Same table-driven player as Smashy Smashy (one voice, stepped by the frame IRQ).

## 14. Source layout

```
src/main.p8        entry, state machine, frame loop
src/video.p8       VIC bank setup, IRQ, tile drawing, HUD, sprite shadow registers
src/input.p8       joystick read, edge detection, Run/Stop, scripted input for tests
src/player.p8      player movement, boost, bounce, spin, invincibility
src/stars.p8       stationary stars: placement, hits, countdowns, warnings, specks
src/hostiles.p8    hostile stars: spawn, steering, hurl
src/explode.p8     explosion list, drawing, area checks
src/score.p8       BCD score, multiplier, lives, timer, chains
src/quasar.p8      quasar spawn and pickup
src/title.p8       title and game-over screens
src/sound.p8       SID effects
src/gen_assets.p8  GENERATED by tools/gfx.py
assets/            sprites.txt, tiles.txt
tools/gfx.py       text art -> binaries + gen_assets.p8
```

## 15. Open questions

None at the moment (star art kinds are decided in the art phase, §12).

### Resolved
- HUD (designer, 2026-10-17): no galaxy number on the HUD, it's shown at galaxy start. Time, multiplier and lives each use a one-char icon (clock/hourglass, small centred x, yellow star) followed by the digits.
- Losing a life (designer, 2026-10-17): 1 s death effect while play continues, respawn in the centre with 2 s of safety, hostiles stay, timer keeps running (§8). The multiplier resets to x1.
- Designer answers 2026-10-17: boost glows through bright colors (§5); a warning star hit to 3 goes supernova instead of hostile (§6); hit-count and countdown feedback if doable (§6); hostiles spawn 4+ tiles from the player and stay at 120% after galaxy 11 (later galaxy 21), pass over stars and each other (§7); boost hurls, supernova kills and invincibility kills share one chain, capped at the 8th step (later the 6th) (§8); supernova points use the multiplier before the +1; clear bonus multiplied then reset; extra life every 20,000 to start with (later 50,000) (§8); quasar appears after its explosion, invincibility glow slows in its last second (§9).
- Art budget (designer, 2026-10-17): 8 star kinds and 3 explosion frames, so all chars fit without reuse (§12).
- Boost vs hostile (designer change, 2026-10-17): instead of flying off the screen, a boosted hostile is hurled about 6 tiles away and explodes like a supernova (can hurt the player, starts chain reactions). It explodes early on touching another star or a playfield edge (later changed: see "Hurl blasts" below). The hit scores the chain step; the explosion adds no supernova points or multiplier (§7).
- Respawn (designer, 2026-10-17): hostiles near the centre are pushed out when the player reappears, so they can't camp the respawn point (§8).
- Explosion hit area (designer, 2026-10-18): the player and hostile stars are hit by an explosion's round core, not its whole 3 x 3 square; stationary stars still use the square (§6).
- Bounce trap (designer, 2026-10-18): a star touched during a knockback stops it instead of bouncing again, so the player can't be trapped between two stars (§6).
- Hurl blasts (designer, 2026-10-18): the player bounces off a hurled hostile; the hostile flies through stationary stars, and through hostiles for its first 8 frames; at a playfield edge it flies off the screen with no explosion. So its explosion no longer catches the player who hurled it (§7).

- Art direction (designer, 2026-10-18): shared colors white + orange, 8 distinct star shapes, a shared swelling star for the countdown, 3-frame explosion (flash, burst, embers; brighter wins on overlap), plain player star with no face, all art by Claude as editable text (§12).

## 16. Backlog

- Score popups at the scoring spot (as in Smashy Smashy).
- Twinkling background specks.
- Saved high-score list.
