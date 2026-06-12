# ZAMN Super Famicade Version
I'm working on a special hack for Zombies Ate My Neighbors, originally released in 1993 in the USA for the Super Nintendo Entertainment System.

## Here's what is implemented so far:
- High Score SRAM saving
- Game Over Blood Hack
- HUD is customized to show "Lives:#"
- HUD is moved to the bottom of the screen
- Support for P1 coin-up in-game
- Supports basic support for SRAM mapping for both LoROM and HiROM (if you want to convert the game to HiROM for whatever reason)

## What's next:
- Additional support for extra input for the SuperFamicade Controller Board
	(make support switchable - always on until other features are implemented)
	(SuperFamicade/SFC Controller Board project here: https://hackaday.io/project/3121-super-famicade)
- Graphical Changes for "Arcade Mode"
- Code Changes for "Arcade Mode" (Including options for difficulty, # lives per coin-up, etc.)
- Support second player join-in

## Building
The project now builds with [retrotool](https://pypi.org/project/retrotool/) + asar:

```bash
pip install retrotool[asar]
# Put the unmodified "Zombies Ate My Neighbors (USA)" LoROM image at base/zamn.sfc
retrotool build .                # -> out/ZAMN_SuperFamicade.sfc
retrotool build . --diff ips     # also emits out/ZAMN_SuperFamicade.sfc.ips
```

The hack source lives in `src/superfamicade.asm` (asar dialect). The legacy
sources (`ZAMN_SuperFamicade.asm` xkas-plus, `ZAMN_SuperFamicade_xkas.asm`
xkas v06, `build.cmd`/`debug.cmd`) are kept under `src/old/` for reference but
are no longer the build path.

Conversion notes (xkas-plus -> asar):
- `define x`/`{x}` became `!x = `/`!x`
- bare `org $ffXX` header/table addresses became full 24-bit `org $00ffXX`
- **MVN operand order is swapped**: asar uses `mvn dest,src` (matches the
  machine-code byte order), xkas-plus used `mvn src,dest`. All nine MVNs in
  the high-score code were swapped and byte-verified against the original.

## Note:
Removed Synwrite lexer. Will be moving to new repo.
