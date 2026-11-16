# KOMMANDER cheat database credits

`kommander.db` is **one cheat database merged from two community databases**. KOMMANDER did not author any of these codes; every cheat belongs to its community authors. The full source list is in CREDITS.txt beside this file. Keep both credit files with the database if you redistribute it.

## Source 1 - CWCheat Database Plus+

Compiled and maintained by **Saramagrean**: [CWCheat Database Plus+](https://github.com/Saramagrean/CWCheat-Database-Plus-). CWCheat (`_L`) codes, about 2,656 PSP games.

## Source 2 - the TempAR cheat database

Compiled and maintained by **raing3**, author of [TempAR](https://github.com/raing3/tempar), dated 02-03-2011. CWCheat (`_L`) and PSPAR (`_M`) codes; the codes inside are credited to their authors (e.g. Codejunkies). The PSPAR / TempAR engine in KOMCHEAT follows raing3's [PSP cheat documentation](https://github.com/raing3/psp-cheat-documentation).

raing3's header asks that his database is not merged into another one and called someone else's. KOMMANDER claims none of it: the header of `kommander.db` names him, and every block of TempAR codes inside it is marked `# <* from the TempAR database by raing3 *>`.

## How kommander.db was made

`tools/cheatdb_merge.py` (2026-11-05): per game, the CWCheat Database Plus+ codes first, then the TempAR codes that add something. A code that does the same thing as one already listed (the same writes, whatever its name) is dropped; a TempAR code whose name is taken by a different code is kept as `<name> [TA]`; TempAR folders become name prefixes and its comments `NOTE:` rows; two different codes with one name get `(2)` / `[TA 2]` (picks are saved by name); PPSSPP-only rows and PS1 (GameShark-format) sections are not included. About 2,803 PSP games and 104,300 codes and group headers.

**Your own database:** put your own `cheat.db` (CWCheat or TempAR format; `cheats.db` / `tempar.db` also work) beside `kommander.db` - the overlay's CHEATS page shows it as a second tab (L / R).

## MotorStorm: Arctic Edge update - 2026-10-04

- **Kabuto_Kun**: fixed-speed FPS patches and the PSP/Vita dynamic-gamespeed assembly routine. [Original post](https://forums.ppsspp.org/showthread.php?pid=125104&tid=4799).
- **stranno**: original European FPS discovery, credited in Kabuto_Kun's post.
- **Saramagrean**: the existing US/EU cheat sections and database compilation.
- **Quadruple and the Edge Pack author/contributors**: linked European menu-adaptive reference, credited by the [Edge Pack cheat file](https://edge.the-sauna.icu/download/UCES01250.ini). That emulator-oriented patch is a research reference; the installed PSP patch uses Kabuto_Kun's dynamic routine.
- **KOMMANDER integration**: replaces the existing fixed-60 and default-30 rows at the same positions; restores the original 1.0 timing factor before installing dynamic timing, initializes its timestamp, and clears the cave sentinel during restoration so it can be enabled again. Original assembly authors retain credit.

## Use on PSP

Supported IDs: UCUS98743 (US) and UCES01250 (Europe). The supplied PC ISO is US 1.00. Enable CHEAT ENGINE and **60 FPS - NORMAL SPEED [PSP]**, with every other FPS/game-speed cheat OFF. Prefer 333 MHz CPU / 166 MHz bus. The code targets a 60 FPS ceiling; real PSP throughput can be lower. Dynamic timing derives simulation time from elapsed microseconds, so dropped frames do not impose the fixed-60 slow motion.

To undo: turn the 60 FPS row OFF, enable **30 FPS - RESTORE NORMAL SPEED**, allow one apply tick with the overlay closed, then turn the restore row OFF. Disabling a normal database cheat alone does not undo writes. Never enable both rows together. Restarting the game also removes the patch. Use 30 FPS for movies if their playback is affected.

This PSP/Vita dynamic patch is unsuitable for PPSSPP: the original author says to use the fixed-speed emulator variant there.

## Validation and limits

US patch sites, original instructions and the sceKernelGetSystemTimeWide import were matched to the supplied, decrypted UCUS98743 1.00 executable at load base 0x08804000. Europe is the author's published port and has no supplied binary validation. Both code blocks fit KOMCHEAT's 32-line limit and retain existing selection ordinals. The index is regenerated for the exact modified database. Tests execute the actual KOMCHEAT parser/applier and the US MIPS routine: elapsed-time steps match 20–60 FPS, ON/restore/ON passes, and deliberately broken guard, restore and timing instructions are rejected. The original routine caps large frame gaps at 52.734 ms, so extreme drops below about 19 FPS or long stalls do not preserve elapsed time fully.

Physical PSP gameplay, movies and sustained 60 FPS have not been measured in this session. The original author reported roughly 40+ and sometimes 50+ FPS on a real PSP; a database unlock cannot guarantee the requested sustained 60 FPS. No performance/resolution, bloom, AI or audio hacks were added.
