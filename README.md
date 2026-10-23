# Zombie-Game

**Survivor RTS**: a 2D isometric zombie-wave survival strategy game. StarCraft-style squad
command, Fallout Shelter-style people management, and Call of Duty Zombies-style escalating waves.

This is the first playable prototype, following the design bible's recommended starting
milestone: one headquarters, one Agriculture building and one Combat building.

## Running

Requires [LÖVE 11.5](https://love2d.org/).

```
"C:\Program Files\LOVE\love.exe" .
```

or drag the project folder onto `love.exe`.

## What's in the prototype

- **Three headquarters to choose from**, each with a working passive: Old Farmhouse with Barn
  (+30% food), Drained Water Tower (double warning time), Charred Hospital (faster healing,
  longer bleed-out).
- **Two specialization groups**: Combat drills at the Box Truck Armory; Agriculture farms the
  Salvage Garden.
- **Generated survivors**: name, age, one of 72 backgrounds, ten aptitudes, six combat
  attributes, two permanent core traits and learned skills that grow with work and fighting.
- **Physical mobilization**: work → alarm → walk to the armory → collect the group's loadout
  from shared stock → rally point → fight. Returning to work puts the gear back.
- **Survival cycle**: Prepare → Alert (scouts name the direction) → Wave → Recover, with
  rewards, a new recruit after each wave, and the option to call a wave early for extra scrap.
- **Breakable perimeter**: zombies smash fences, gates, towers and buildings; scrap repairs them.

## Controls

| Input | Action |
| --- | --- |
| Left-click / drag | Select survivors (Shift adds) |
| Right-click | Move · right-click a zombie to focus fire |
| A, then left-click | Attack-move |
| H / S / F | Hold position · Stop · Fall back to rally point |
| 1 / 2 | Group tab (double-tap selects the group) |
| M | Mobilize / return the current group |
| Arrows, screen edge, middle-drag | Pan |
| Mouse wheel | Zoom |
| Space | Pause |
| F1 | Help |

## Code layout

- `main.lua`: menu, input and the main loop
- `src/game.lua`: settlement layout, simulation, rendering and orders
- `src/survivor.lua`, `src/zombie.lua`: unit generation, behavior and drawing
- `src/director.lua`: the wave cycle
- `src/map.lua`: grid, survivor pathfinding (A*) and the zombie flow field
- `src/structures.lua`, `src/gfx.lua`: placeholder art drawn in code
- `src/ui.lua`: HUD
- `src/data.lua`: backgrounds, traits, weapons, HQs and zombie types

`love . --autotest [--hq <id>]` plays a scripted session, saves screenshots to
`%APPDATA%\LOVE\survivor_rts` and prints a status line, for quick smoke testing.

## Art pipeline

Building art lives in `assets/buildings/`. Each painting has a `<id>.png` cut-out and an
`<id>_glow.png` emissive layer (lamps, windows, neon), which is added on top after the night
lighting so the painted lights still shine.

To add or update a painting:

1. Render it as one building on a plain dark background, at the same camera angle as the
   existing ones, and name it in `SOURCES` in `tools/process_art.lua`.
2. Run `love . --process-art "<folder with the source PNGs>"` to cut out the background and
   build the glow layer.
3. Add an entry to `D.SPRITES` in `src/data.lua`, then run `love . --calibrate`. The resulting
   `calibrate.png` in the save folder shows each painting over its footprint. Adjust `ax`/`ay`
   (the pixel that sits on the footprint centre) and `scale` until the building's base fits.

Rendering is layered: the scene, multiplied by a light map that is near-black except around
lamps, fires, windows, muzzle flashes and survivors; then emissive layers and glowing zombie
eyes; then unlit overlays such as selection rings and health bars.
