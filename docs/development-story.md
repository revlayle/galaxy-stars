# How Galaxy Stars was made

Galaxy Stars is the second Commodore 64 game made by Rev. Layle (designer) and Claude (Anthropic's AI model), after [Smashy Smashy](https://github.com/revlayle/smashy-smashy). The method was the same: a one-page design note turned into a written spec and a phase plan, then one fresh AI coding session per phase, with the designer playing every build before it was saved. [Smashy Smashy's development story](https://github.com/revlayle/smashy-smashy/blob/main/docs/development-story.md) explains that method and the C64 terms in detail. This page is about what was different this time.

<p align="center"><img src="images/gameplay.png" width="512" alt="Gameplay: a supernova explosion next to the player star and a hostile star"></p>

**In numbers**
- 20 saved versions (git commits), from October 17, 14:45 to October 19, 10:20.
- About 5,800 lines of Prog8 in 15 modules, including the built-in self-tests and a frame-time profiler.
- A 380-line spec and a 300-line build log.
- The finished game uses about 25 KB of the C64's memory.

## Starting from a working base

Smashy Smashy was the first game, and a lot of its first day went into tooling. Galaxy Stars started with all of that already proven: the same toolchain (copied, not downloaded again), the same `AGENTS.md` rules, the same spec-and-phases documents and session prompts. The coding prompt told every session to read Smashy Smashy's source and adapt its tested pieces (moving the C64's graphics chip to the top of memory, the once-per-frame interrupt, scripted joystick input for self-tests, the text-art converter, the sound player) rather than rewrite them.

The effect shows in the timeline: graphics, movement, stars and supernovas, hostile stars and the whole game flow (phases 1 to 5) were built and played on the first afternoon and evening.

## Turning the notes into numbers

The designer's notes were clear about the game but left the edges open, as notes do. The planning session turned every rule into frame counts and speeds (a boost is 2.5 x speed for 75 frames; the multiplier drop time runs from 50 frames at x9 to 175 at x2) and collected 14 open questions, each with a proposal: what counts as one hostile chain, what happens when you lose a life, whether a hit on a star that is about to turn hostile still counts, and so on. The designer answered them in a few short messages, mostly "yes", sometimes with a better idea (the HUD got small icons instead of labels; the multiplier resets when you lose a life).

## Changed by playing

The biggest difference from the notes came from playing each build. A few examples, each recorded in the spec with the date and the reason:

- **Hitting a hostile with a boost.** The notes had it flying off the screen. Before hostiles were even built, the designer changed it: the hostile is hurled and explodes like a supernova, so a hurl can start a chain reaction. After playing it, it was too easy to ram a hostile and follow it straight into its own explosion. So the player now recoils from the hit, the hurled star flies over stationary stars instead of exploding on them, and one that reaches the screen edge just leaves (still a kill, no explosion).
- **Respawning.** Hostiles kept chasing the spot where the player died and were waiting there when they came back: three lives went in about 8 seconds in one test. Now hostiles near the centre are pushed out when the player reappears, and hold still during the 2 seconds of safety.
- **Explosions.** Deaths in the empty corners of an explosion's square felt unfair, so the player and hostiles are now hit only by its round bright core. Stars still use the whole square, so chain reactions work as before.
- **Difficulty.** The ramp got hard suddenly around galaxy 7. It was stretched to reach its peak at galaxy 21 instead of 11, with up to 55 stars.
- **Late-game scoring.** The designer reached galaxy 39 with 20 million points and lives to spare. In big chain reactions one hostile chain never ended, so every kill scored the maximum. The coding session measured four candidate rules on the same games, played by the demo's AI pilot at galaxy 25, before the designer picked one: a star counting down no longer keeps a chain alive (points per galaxy fell from about 1.5 million to 250,000), and extra lives moved from every 50,000 to 100,000 and then every 300,000.

## The frame budget

The C64 redraws the screen 50 times a second, and all the game's work for a frame has to fit in about 19,000 processor cycles. Smashy Smashy never came close. Galaxy Stars did: up to 55 stars, 6 hostile stars steering after the player, up to 8 explosions, all in the same frame.

The first build of hostile stars missed frames at galaxy 11. From then on the coding sessions measured instead of guessing: a profiler built on one of the C64's hardware timers showed which part of the frame cost what, and every change was checked on the same 16 fixed game layouts before and after. The busiest loops moved to 6502 assembly, at most one explosion starts per frame (a second one waits a frame, too short to see), and an explosion's animation step can wait up to 4 frames for a quieter one. At the hardest galaxies the game drops a single frame now and then in 2 of the 16 test layouts; elsewhere it never does.

## Small limits, firm choices

- **Characters.** The C64 shows the playfield from a set of 256 small 8 x 8 images, 64 of them taken by the HUD font. The first art plan (12 star kinds, a 4-frame explosion) needed more than the rest. The designer cut it to 8 kinds and 3 frames, which fit with room to spare.
- **Colours.** All stars and explosions share two colours (white and orange) besides each star's own. The designer picked them from a short list of proposals, along with 8 distinct star shapes and a shared "swelling" star for the countdown. Claude drew all the art as text files; the designer played it and kept it.
- **A compiler bug.** Prog8 12.3.4 compiles an array index that adds two other array reads wrong. Exploded stars came back because the wrong screen tile was cleared. The coding session found it in the generated assembly, worked around it, and it became a rule in `AGENTS.md` so later sessions avoid it.

## The attract mode

After the eight phases came a title and attract mode, planned as a separate change file (`docs/title-attract.md`): the logo is built by 93 small stars flying in from the screen edges, then HOW TO PLAY and SCORING pages, then a demo game. The demo was a stretch goal. It's played by a small AI pilot routine that writes joystick input the same way the self-tests do. It heads for the nearest star, rams it, gets clear of countdowns and explosions, and hurls hostiles that come too close. Its first version changed direction almost every frame and looked jittery. Holding each direction for 8 frames fixed that. It now clears most galaxies on its own, and it doubled as the test player for the scoring measurements above.

## What carried over, and what's left

What worked again: proposals with every question, so most answers were one word; the designer playing every build before it was saved; the spec recording why a rule changed, not just the new value. What was new: more changes after playtesting, and a coding session that measured before it changed anything.

Not done yet: music (the plan in `docs/title-attract.md` is for the designer to compose in a C64 tracker and the game to play the export on the title), plus a few backlog items in the spec.
