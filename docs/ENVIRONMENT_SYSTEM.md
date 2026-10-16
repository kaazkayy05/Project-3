# Familiar House & Environment System — Samai Hartley

## Run in Godot 4.3

Import `echoes-of-home/project.godot`, open `demo/house_demo.tscn`, and press F6.
F5 runs the existing main menu. WASD moves, mouse looks, Shift sprints, Space
emits an echo, E interacts, and right click holds breath. Escape releases the
cursor; click recaptures it. F6 during gameplay toggles the existing resonance
freeze debug feature. Restart the scene to reset objectives.

## Playtesting improvements

The original deterministic house, player integration, two floors, stair collider,
monster/breath bindings, and runtime navigation bake are retained. A 4 × 12 m
west extension adds 48 square meters instead of scaling the existing rooms.
Two broad openings connect the living room, reading/family room, and northwest
sideboard area into a loop. An additional 2 m upstairs doorway connects the hall
to the study and the bedroom wing. The existing bedroom door remains functional.
The continuous stair ramp remains the physics surface; visual treads add a
recognizable staircase without introducing individual collision steps.

The living area has a couch with worn cushions, coffee table, old television,
family silhouettes in picture frames (one crooked), and carpet. The family room
adds a reading bench, rug, bookshelf, and books. The kitchen has counters, wall
cabinets, refrigerator, dining table, chairs, and plates. Upstairs, the childhood
bedroom has a quilt, pillow, dresser with drawers, bookshelf, toy blocks, and
childlike framed family drawings. The study has a homework desk, carpet, and a
chair facing an empty corner. All art is original primitive geometry.

Furniture bodies use simple solid colliders for predictable movement and navigation.
Small decorative pieces use collision layer 0, so books, plates, picture details,
toy blocks, and visual stair treads cannot snag the player or split navigation.
New solid bodies exist before the existing navigation bake. No monster logic or
navigation API is replaced. Both new ground-floor entrances and the upstairs
study are checked against the real baked navigation map.

## Intentional interactions

The brass key remains on the accessible downstairs northwest sideboard at
(-6, 0.98, -3). Its new bow/stem/teeth silhouette hides with the original key body.
Targeting uses a 2.2 m camera-to-target reach and a 24-degree view cone rather than
a pixel-sized ray target. Candidates must have an unobstructed layer-1 ray from
the camera to their actual body. Walls and furniture therefore block pickup;
there is no oversized collision trigger reaching through them. E is still required.
Target selection is deterministic: alignment and distance rank visible candidates,
with a small priority for the key and lock controls over door slabs.

The larger brass deadbolt with a round escutcheon is mounted on the front door's interior face. Its
contrasting pulse material and thumb-turn identify it without a permanent light.
The center-bottom HUD shows contextual E instructions. Trying the locked door
reports “The deadbolt is still locked.” Without the key, the bolt asks for it.
Pickup confirms “Brass Key Collected”; unlocking rotates the thumb-turn and
explicitly tells the player to press E on the door next. Both successful transitions
play a short original synthesized click, once per state transition. This is local
presentation audio; it does not add a second acoustic noise event.

An unlocked bolt yields targeting to the door. Unlocking alone never opens it.
After a separate door interaction, walking into the original porch trigger calls
`try_escape()`. The optional chain remains supported by the root's `require_chain`
export and retains its original objective gate.

## Preserved interfaces

`HouseEnvironmentSystem` still owns `current_surface_type`, `resonance_multiplier`,
`room_layout_state`, `objective_progress`, and `has_escaped`. Its `surface_changed`,
`objectives_changed`, and `escaped` signals keep their original signatures.
`interact(StringName)` still accepts `brass_key`, `deadbolt`, `chain`, `exit`, and
`bedroom_door` and returns feedback text. `interaction_prompt()` supplies UI text;
controllers remain responsible for intentional input, reach, and line of sight.
Objective updates still hide/disable the collected key and opened doors, update
the original navigation links, and emit a copied progress dictionary.

`sample_surface()` samples the uppermost floor from the player's feet and publishes
through Kai's existing `set_surface_resonance()`. Rugs, tile, hardwood, and clutter
retain multipliers 0.5, 1.6, 1.8, and 2.0 respectively. Untagged/absent floors fall
back to hardwood. F6 freeze still publishes 1.0 without changing surface identity.
The demo still calls the original footstep, pulse, and gasp methods. Their signal
signatures, charge economy, hearing behavior, and resonance scaling are unchanged.
Current acoustic tuning separates the 36 m visual radius from hearing. Following
the latest merged hearing balance, walking uses `base_footstep_noise_radius` (5 m),
pulses use `base_pulse_noise_radius` (12 m) at 0.45 base intensity, and gasps use
`base_gasp_noise_radius` (14 m). All still scale by the existing surface resonance.
Tests follow these current exported noise values without changing acoustic code.

Every new visible prop uses the existing environment echo shader and is registered
in the existing pulse material update list. No new light or shader rewrite is
introduced. Tiny details have a lower ambient baseline; key/bolt faces have a
stronger warm pulse response. Monster AI, acoustic code, and sanity/breath code
are unchanged. Music and pause implementations are also retained.

For fresh Godot 4.3 imports, the project feature version is corrected from 4.7,
the music autoload uses its existing script path rather than a newer script UID,
the house scene drops a stale script UID, and the existing Web export gets the
4.3 `runnable` field. The Web build itself has not been regenerated.

## Automated validation

```powershell
./echoes-of-home/tests/run_tests.ps1 -Godot 'C:/path/to/Godot_v4.3-stable_win64_console.exe'
```

The runner imports the project, executes the environment, house, and monster
suites, and launches Kai's original acoustic scene. House coverage includes:

- Carpet/wood transitions, stair ascent/descent, and inter-floor navigation.
- Key pickup from multiple approach angles with imprecise aim, reach limits,
  obstruction by solid furniture, and obstruction from below the sideboard.
- Navigation to both ends of the new family room and the upstairs study.
- Continuous floor collision while traversing the family-room loop.
- Deadbolt selection, locked-door explanation, contextual prompt, thumb rotation,
  separate unlock/open actions, key removal, porch escape, and bedroom door.
- Existing gasp/acoustic/breath bindings, monster noise-triggered death, and HUD.

Validated on Godot **4.3.stable.official.77dcf97d8**: the complete PowerShell
runner passed, including import, 53 environment checks, the expanded house suite,
66 monster checks, and the original acoustic scene. OpenGL captures were rendered
and inspected for darkness, key/bolt recognition, furnishings, and pulse response.
Some standalone exits still emit Godot ObjectDB cleanup warnings; the test runner
completes successfully.
Stale environment radius expectations and the house test's old HUD reference are
updated. The death test resets its previous escape state before testing death.
Monster test teardown stops/releases audio and gives the mixer time to finish
before quitting Godot 4.3; no AI assertions or production behavior are changed.

For visual captures, run without `--headless`:

```sh
godot --path echoes-of-home --script res://tests/capture_house.gd
```

This writes darkness, pulse, living, family, kitchen, childhood bedroom, key, and
bolt PNGs to Godot's printed user-data directory. Captures freeze player movement
and position the camera; they do not alter production lighting or pulse balance.

## Manual acceptance route

1. At spawn, pulse and explore the living room. Circle the coffee table and couch,
   enter the west family room through the broad opening, then leave by its north
   opening toward the sideboard. Compare wood, rug, kitchen tile, and clutter noise.
2. Approach the sideboard from the front and either side. Aim roughly toward the
   key, confirm “Press E to Pick Up Key,” and press E. Verify the click, confirmation,
   disappearance, and that it cannot be collected from behind an occluding wall.
3. Return to the front door. Before collecting the key, test both door and bolt
   feedback. After collection, pulse to identify the brass lock, press E to unlock,
   observe its rotation/click, then look at the door and press E again. Step outside.
4. In a fresh run, take the east stairs up and down without jumping. Explore the
   hall, bedroom door, childhood room, and study doorway. Walk around furniture;
   verify footsteps and pulse visibility on both floors.
5. Pulse near the monster to verify it still hears player noise. Check right-click
   breath control, forced gasp, death/restart, and optional chain-enabled escape.

Automated physics and visual captures complement team playtesting; final pursuit
difficulty, nostalgic readability, and darkness should still be reviewed in play.

## Developed porch and neighborhood ending

The empty 3 × 3 m exit platform is replaced by an 11 × 5.5 m covered wooden porch.
It has slatted chairs with faded cushions, a side table and forgotten cup, floor
planters, hanging baskets, posts, balusters, board seams, a welcome mat and lantern.
Thin exterior facade skins add siding, window trim/shutters and a pitched roof
without replacing any interior wall, collision, or pulse material. Original low-poly
plants and houses are generated from Godot primitives; no external assets are needed.

A level garden path leads from the porch into a fenced front lawn. Beyond the
non-openable gate are a sidewalk, residential street, trees, and three neighboring
houses with a few warm windows and a distant moon. The porch/garden are playable;
the street and neighboring houses are visual scenery, not additional interiors.
Rail and fence colliders bound exploration, and solid floor/path colliders prevent
falls. Small decorative parts and neighborhood scenery have collision layer 0,
keeping them out of the existing monster navigation bake. The porch uses the
original hardwood surface tag and the original front-door navigation link.

`systems/environment/porch_dusk.gdshader` supplies subdued moon/lantern shading
only to exterior materials. It shares colors between props and accepts the existing
pulse origin/radius/fade update, so exterior objects also respond to an echo before
the escape completes. It creates no world light, changes no indoor shader, and does
not illuminate the house interior. On escape the background becomes a dark blue
night sky; no global ambient illumination is introduced.

The existing validated `escaped` signal now enters a safe ending presentation.
The trigger is a little farther onto the porch, at z=10, so the player is fully
clear of the doorway before victory. It still requires the key, bolt, optional
chain, and separate open-door action. Once escaped:

- The existing monster instance stops processing; its AI implementation is unchanged.
- Breath processing/audio and the chase music stop, and gameplay meters are hidden.
- Mouse look and slower WASD movement let the player explore the porch and garden.
- E, echo input, sprinting, and breath input no longer generate gameplay actions/noise.
- The completed escape is one-way: a terminal doorway collider keeps the player
  outside. The garden gate/fences keep them inside the authored ending area.
- R restarts the house and restores normal gameplay; M opens the existing main menu.
  Escape continues to use the existing pause menu.

House integration tests now drive actual post-escape WASD input, check silence,
blocked pulse input, porch/path collision, rear/front/side boundaries, and real
SceneTree restart/menu transitions. They also retain the full interior and escape
sequence checks. The environment test expectations were aligned with the latest
merged hearing-balance changes; no teammate production scripts were rewritten.

To inspect the ending, complete the key/bolt/door loop, step onto the porch, then
look left/right at the furniture and plants. Walk along the central path, look
across the street at the houses, and turn back toward the porch. Try the garden
fences, R, M, and Escape. Run the normal test runner for automated validation.
`tests/capture_house.gd` additionally captures `environment_porch_arrival.png`,
`environment_porch_chairs.png`, `environment_garden_neighborhood.png`, and
`environment_porch_from_garden.png`, without needing an active echo outdoors.

Porch update validation on Godot 4.3: full runner passed with 53 environment,
56 house, and 66 monster checks, plus editor import and the original acoustic
scene. OpenGL porch/neighborhood captures were inspected. Existing standalone
ObjectDB shutdown warnings remain; no script errors or failed checks occurred.
