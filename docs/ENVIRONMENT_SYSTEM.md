# Samaii's Familiar House & Environment System

## Inspection of the starting repository

Base commit: `373c375`. Read the entire tracked project: README, GDD PDF, Kai's
`acoustic_pulse_system.gd`, `test_acoustic_pulse.gd`, `node.tscn`, and UID files.
There was no project.godot, player controller, input map, house scene, art/audio
asset, Monster AI, breath system, or navigation mesh. All original files under
`systems/acoustic_pulse` are unchanged. A minimal project file launches an isolated
environment demo; it does not replace a pre-existing game configuration.

## Run

Open `echoes-of-home/project.godot` in **Godot 4.3** and press F6 with
`demo/house_demo.tscn` open, or F5. WASD moves, mouse looks, Shift sprints, Space
uses Kai's rechargeable pulse, E interacts within 2.2 meters, and Escape releases
the cursor. Click to recapture. F6 **while playing** toggles the resonance freeze.
Restart the scene to reset objectives.

Find the small brass key on the downstairs sideboard in the northwest part of
the house. Aim at it and press E. At the front door, interact with the deadbolt
on its left, then the door, then walk through. The optional chain is off by
default, matching the GDD's scoped key/deadbolt loop. Set the demo root's exported
`require_chain` to true to add a chain interaction on the right of the front door.
The master-bedroom door can be opened/closed using its adjacent handle.

## Owned state and interfaces

`systems/environment/house_environment_system.gd` owns `current_surface_type`,
`resonance_multiplier`, `room_layout_state`, and `objective_progress`.

| Floor | Multiplier | Walk intensity | Walk radius | Pulse intensity | Pulse radius |
| --- | ---: | ---: | ---: | ---: | ---: |
| CARPET | 0.5 | 0.125 | 3.6 m | 0.5 | 6 m |
| HARDWOOD | 1.8 | 0.45 | 12.96 m | 1.8 | 21.6 m |
| TILE | 1.6 | 0.4 | 11.52 m | 1.6 | 19.2 m |
| CLUTTER / creaky board | 2.0 | 0.5 | 14.4 m | 2.0 | 24 m |

Connect `acoustic_system` to the existing AcousticPulseSystem instance. Give solid
floor colliders integer `surface_type` metadata from `HouseEnvironmentSystem.Surface`.
Floors use collision layer 1. `sample_surface(player)` casts a short downward ray
from the player's feet origin, excluding the player's collider. The first solid
hit wins, so a slightly raised carpet covers hardwood deterministically and
upstairs floors do not compete with downstairs floors. Untagged/missing footing
falls back to hardwood rather than retaining a stale carpet benefit; the return
value indicates whether a floor was hit. The controller suppresses airborne steps.
For a center-origin controller, adapt the ray origin to its feet before integration.

Call `sample_surface` in physics processing after movement and **before** publishing
a footstep or pulse. It writes Kai's existing `set_surface_resonance()` cache.
Continue using his `emit_footstep_noise(position, sprinting)` and
`trigger_player_pulse(position)` methods. No additional scaling or replacement
noise dispatcher is needed. The demo emits steps after 0.9 m of grounded movement;
standing against a wall does not generate footsteps. Creaky/clutter steps also
play an original, reproducible placeholder friction cue, with no second noise event.

Daryl should subscribe to the unchanged
`noise_emitted(origin: Vector3, intensity: float, radius: float)` signal. Its origin
is the position of **that event**; do not use the last pulse origin for a footstep.
Event dictionaries and pulse charge/recharge/expansion behavior are unchanged.
Kayla's gasp entry point and its existing scaling are also untouched.

`interact(action: StringName)` accepts `brass_key`, `deadbolt`, `chain`, `exit`, and
`bedroom_door`. This is a controller-independent target API, not an input controller.
The caller is responsible for reach and line of sight (the demo checks both with a
camera ray against solid colliders). Bind your eventual player interaction system
to this method and remove the demo adapter. Objective changes emit a copied progress
dictionary; the scene mirrors this state into door/key visibility and collision.
`try_escape()` must be called on the player crossing the exit trigger. It validates
key, bolt, optional chain, and door-open state again, and emits `escaped` only once.
No door interaction alone grants victory.

## Fixed house and visuals

`demo/house_demo.gd` constructs a deterministic blockout from fixed coordinates:
foyer at the south/front, living room to the west, kitchen to the north/east,
stair ramp on the east, upstairs hall along z=0, master bedroom behind z=-2.
All walkable floors, exterior/interior walls, sofa, sideboard, bed, counter, doors,
and rails have solid collision. Rugs, tile, and clutter have separate floor colliders.
The east stair connects the two floors at y=0 and y=3. There is no room shifting,
random layout, throwable clutter, monster stand-in in gameplay, or standard light.

`echo_surface.gdshader` reveals box edges and faint faces from Kai's world-space
pulse origin/radius, then fades them. Carpet and hazard accents follow the GDD
palette. Camera FOV is 75 degrees. Ambient light/reflections are disabled. The
small HUD is independent of world lighting. Headless physics runs skip mesh creation
to avoid Godot 4.3 dummy-renderer warnings; a real OpenGL run validates the shader.

## Tests and results

Run from the repository root, substituting your Godot 4.3 executable:

```powershell
./echoes-of-home/tests/run_tests.ps1 -Godot 'C:/path/to/Godot_v4.3-stable_win64_console.exe'
```

Equivalent cross-platform commands:

```sh
godot --headless --path echoes-of-home --editor --import --quit
godot --headless --path echoes-of-home --script res://tests/test_environment.gd
godot --headless --path echoes-of-home --script res://tests/test_house.gd
godot --headless --path echoes-of-home res://systems/acoustic_pulse/node.tscn --quit-after 5
```

Validated with **4.3.stable.official.77dcf97d8**:

- 53 core assertions passed: four actual physics floor hits, intensity/radius scaling
  for steps and pulses, pulse charge consumption, off-floor fallback, restoration
  after freeze, listener threshold/origin behavior, objective ordering, chain gate,
  one-shot escape, and interior-door state.
- 12 house assertions passed: walking off/on carpet, stairs both directions,
  key targeting/reach, physical locked door, exit area, key collider removal, and
  master-bedroom door collision/opening.
- Kai's original acoustic scene ran successfully. Its existing script UID emits a
  warning on Godot 4.3 and falls back to the correct resource path; left unchanged.
- OpenGL 3.3 rendering on an RTX 4070 Laptop GPU ran without errors. Captured and
  inspected default darkness and active pulse images. `tests/capture_house.gd`
  reproduces those images in Godot's user-data directory; run it without `--headless`.

Freeze test: enable `freeze_resonance` (or F6 in the demo). Across all four actual
floor types, walking becomes intensity 0.25/radius 7.2 and pulses become intensity
1.0/radius 12.0. The surface enum still tracks footing. Disabling freeze immediately
restores the current floor's value. Visual/acoustic creak flavor remains; the test
freezes noise-event resonance, not the presence of a floor material or sound asset.

## Remaining integration work

Actual Daryl monster navigation, hearing, sprinting, and kill behavior cannot be
run because that implementation is absent. The test listener verifies the existing
signal contract and a threshold-driven state change only. Kayla's breath/panic
integration likewise cannot be exercised end to end. No navmesh or substitute AI
was added in their place.

Replace the isolated demo controller with the team's eventual player controller,
keeping the sampling/interaction calls above. Replace blockout props and placeholder
creak with final team art/audio when available. Full four-system balance, spatial
sound design, monster playtesting, heartbeat/head-bob effects, and accessibility
review remain team work; they are not represented as completed by these tests.
