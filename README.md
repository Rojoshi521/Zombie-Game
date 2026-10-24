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

- **Five headquarters to choose from**, each with a working passive: Old Farmhouse with Barn
  (+30% food), Drained Water Tower (double warning time), Defunct Ferris Wheel (+50% scrap),
  Half-Working Casino (chance of a bonus cache) and Worn-Down Broadcast Station (40% faster
  learning).
- **Build your own base**: a run starts with only the headquarters inside the walls and scrap
  for one building, so the first choice is the player's. Each group's panel lists its three
  foundations from the design bible (40 scrap each); pick one and place it on the grid like a
  StarCraft building, its tiles green where it fits and red where it doesn't. R turns it a
  quarter at a time: the Box Truck Armory, painted from several sides, shows the matching
  view; buildings painted once are mirrored. Shift-click places another, right-click cancels. Nothing is built
  at night. A group without a building waits at the HQ and does nothing; Leadership needs none.
  Without an armory, gear is handed out at the HQ.
- **Ten specialization groups**, one survivor in each at the start, managed from the
  specialization bar along the bottom of the screen. Combat drills at the School Bus Barracks
  and draws gear from the Box Truck Armory; Scouting keeps watch from the Lifeguard Tower and
  sees much further in the field; Scavenging sorts scrap at the Garbage Compactor Truck and
  searches buildings fastest; Agriculture farms the Salvage Garden and the Hydroponic Container;
  Engineering patches walls for free at the Tow-Truck Workshop; Medicine speeds healing from
  the Laundromat Sterilization Ward; Research speeds learning in the Derelict Arcade Lab;
  Fabrication turns scrap into ammo at the Pizza Parlor Forge; Logistics cuts food use at the
  Vending Machine Supply Wall; Leadership (which has no foundation) makes all work faster from
  the headquarters.
- **A ruined town, new every run**: streets, houses, shops, lots and landmarks (jail, zoo,
  soccer field) around the walls, with wrecked and burning cars and lurking packs of infected.
  It starts under fog of war. Scouts reveal what each building holds; anyone can search one
  (right-click it), and the loot only counts once it is carried back inside the walls.
  Gunfire draws nearby infected. Survivors downed in the town bleed out unless a teammate
  reaches them, while waves keep coming at the base.
- **Generated survivors**: name, age, one of 71 backgrounds, ten aptitudes, six combat
  attributes, two permanent core traits and learned skills that grow with work and fighting.
- **Physical mobilization**: work → alarm → walk to the armory → collect the group's loadout
  from shared stock → rally point → fight. Returning to work puts the gear back.
- **Day and night**: a 3-minute first day (then 2.5 minutes) for scouting, scavenging and repairs,
  with wider sight and sluggish town infected. At dusk scouts name the direction of the horde;
  the night lasts until it is beaten back, and the town's infected grow restless. Dawn brings
  rewards and a new recruit. Calling the night early pays extra scrap.
- **Breakable perimeter**: zombies smash fences, gates, towers and buildings; scrap repairs them.

## Controls

| Input | Action |
| --- | --- |
| Left-click / drag | Select survivors (Shift adds) |
| Right-click | Move · right-click a zombie to focus fire · right-click a town building to search it |
| A, then left-click | Attack-move |
| H / S / F | Hold position · Stop · Fall back to rally point |
| 1 - 9, 0 | Open that group's panel; again to close (double-tap selects the group) |
| Specialization bar (bottom) | Click a group card to open or close its panel |
| Minimap (bottom right) | Click or drag to move the camera |
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

The town sheets (`terrain1.png` to `terrain5.png`) are sliced into `assets/town/`, one PNG per
object and view, with the ground-plate anchors in a generated `assets/town/index.lua`.

Building art lives in `assets/buildings/` and prop art (fence, gate, watchtower, crates, lamp,
fire barrel) in `assets/props/`, cut from the `terrain.png` prop sheet. Fences and gates are drawn
one vertical slice per tile, sheared to the tile grid, so a destroyed tile leaves a real gap.
Each painting has a `<id>.png` cut-out and an
`<id>_glow.png` emissive layer (lamps, windows, neon), which is added on top after the night
lighting so the painted lights still shine.

Survivor and zombie portraits are cut into `assets/units/` by
`love . --process-units "<folder or PNG>" ...`, which removes the studio background and the
patch of ground under the survivors, shrinks each figure and records its foot anchor and head
in `assets/units/index.lua`. LÖVE runs out of memory on a big batch in one run, so feed a large
set one file per run; each run merges into the index. Each group wears one portrait set
(`Units.GROUP_SET` in `src/units.lua`): Combat `combat*`, Scouting `leader*`, Scavenging
`worker*`, Agriculture `farmer*`. Zombie kinds pick from `zombie1-10`. Figures face right and
are mirrored to face left; walking and attacking bob and lean the whole figure.

A group can instead wear a walk sheet: 4 columns (front, side, three-quarter front, back) by 2
rows (left foot forward, right foot forward), each figure facing screen-right on a plain
background, with an optional label under each figure. `love . --process-units --sheet soldier
"<sheet PNG>"` cuts it into `soldier_<view><1|2>` frames at one shared scale, and
`Units.WALK_SET` in `src/units.lua` assigns it to a group (every group wears `soldier` for
now). The 16-pose sheet adds a four-step side walk and back-diagonal views:
`--sheet soldier:walk16 "<sheet PNG>"` (the layouts are in `LAYOUTS` in
`tools/process_units.lua`). Survivors show the view matching their heading (front,
three-quarter, side, back-diagonal, back; mirrored for the left) and step through its frames as
they walk.

A building painted from several sides comes as a rotation sheet: name it in `ROTATION_SHEETS`
in `tools/process_art.lua` with the rectangle of each view, which become `<id>_r0`, `_r1`, ...,
then list them as the building's `views` in `src/structures.lua` (one per quarter turn; a
missing turn can reuse another view mirrored).

To add or update a painting:

1. Render it as one building on a plain dark background, at the same camera angle as the
   existing ones, and name it in `SOURCES` in `tools/process_art.lua`.
2. Run `love . --process-art "<folder with the source PNGs>"` to cut out the background and
   build the glow layer.
3. Add an entry to `D.SPRITES` in `src/data.lua`, then run `love . --calibrate [<id> ...]`
   (naming ids shows only those paintings). The resulting
   `calibrate.png` in the save folder shows each painting over its footprint. Adjust `ax`/`ay`
   (the pixel that sits on the footprint centre) and `scale` until the building's base fits.

Rendering is layered: the scene, multiplied by a light map that is near-black except around
lamps, fires, windows, muzzle flashes and survivors; then emissive layers and glowing zombie
eyes; then unlit overlays such as selection rings and health bars.
