# Add Samaii's environment system and fixed house demo

Players can traverse four floor types whose resonance feeds Kai's existing acoustic
setter, find a brass key, unlock the front deadbolt, and exit only after the required
objectives. An optional chain is disabled by default to match the scoped GDD loop.

## Files and behavior

- `systems/environment/house_environment_system.gd`: floor ray sampling, owned
  surface/layout/objective state, resonance freeze, interaction API, escape gating.
- `systems/environment/echo_surface.gdshader`: pulse-driven edges/faces and fade.
- `demo/house_demo.tscn`, `house_demo.gd`, `demo_player.gd`, `demo/audio/*`: fixed
  two-story house blockout, collidable doors/props, rugs and creaky patches, a
  replaceable first-person interaction adapter, and original placeholder creak.
- `project.godot`, `.gitignore`: minimal runnable scaffold; none existed upstream.
- `tests/*`: assertion-based core/physics tests, runner, and rendered-frame capture.
- `docs/ENVIRONMENT_SYSTEM.md`, README: controls, interfaces, floor values,
  integration instructions, reproducible tests, and remaining limitations.

## Team integration

No existing acoustic source or scene changed. Samaii calls
`set_surface_resonance()` before Kai's existing step/pulse entry points; those
already scale intensity and radius. `noise_emitted(origin, intensity, radius)`
and event dictionaries are unchanged. No Monster AI or breath system was added.
The repository had no player controller, house assets, or project configuration,
so the new controller is explicitly a demo adapter with a documented replacement seam.

## Validation

Godot 4.3.stable.official.77dcf97d8: clean import; 53 core assertions and 12 house
assertions passed. Tests cover all floor colliders, movement/pulse scaling,
listener response and event origin, freeze at 1.0, objective ordering, optional
chain, physical door gating, exit crossing, key targeting/range, and stairs both ways.
Kai's original test scene runs with its existing UID/path-fallback warning.
Actual OpenGL rendering completed without errors; dark and active-pulse frames
were captured and inspected. Physics-only headless runs omit visual meshes.

## Limits for team review

Daryl's AI, Kayla's breath system, the production player controller, and final art
are absent upstream. The noise listener test is a contract probe, not validation
of the actual monster. This is a playable environment blockout; final art/audio,
navmesh integration, four-system balance, and monster playtesting remain pending.
