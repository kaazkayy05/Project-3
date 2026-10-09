# Project-3
TEAM 3 - Echoes of Home

**Kayla Cobb**: Sanity / Breath Control System

**Kai Harris-Coles**: Acoustic Pulse & Perception System

**Samai Hartley**: Familiar House & Environment System

**Daryl Watkins-Mattocks**: Monster AI & Behavior State

**Part 2: Pick one**
Our team chose Kai’s echolocation idea. We liked how the childhood home fits the “Familiar” theme while the darkness and distorted layout make it feel unsettling, and the echolocation mechanic gives the player a unique way to explore while also creating risk because the monster can detect each echo too. The other ideas lost because they relied more on traditional hiding, chasing, or jump scare mechanics, while Kai’s idea gives the player a mechanic that directly connects exploration, danger, and the monster’s hidden rules.




Part 4: The monster (30 points)
Write at least three rules the monster follows. For each one, say which system's state it reads.
For each rule, say how a player would figure it out without being told.
Predict the scariest moment in your game. Say where it happens and which rules are in play.


Rule 1: The Ghost Coordinate (Origin Anchor)
The Rule: The monster does not pathfind toward the player's moving avatar; it paths exclusively toward the exact (x,y) world coordinate where a noise event originated, investigating that specific anchor point for 2.5 seconds before returning to patrol.
System State Read: Reads the last_noise_position vector and noise_timestamp emitted by the Acoustic Pulse & Perception System (Member 1).
How Players Figure It Out: Through trial and dying. A player will inevitably panic, tap an echo pulse in a doorway, and dash around a corner onto a carpeted surface. Instead of rounding the corner to kill them, the monster will barrel directly into the empty doorframe where the pulse occurred, swipe at the empty space, and sniff around. Players realize that an echo reveals their past location, not their current one—turning the pulse into a deliberate distraction flare.
Rule 2: Resonance Amplification (Surface Echo Penalty)
The Rule: The monster’s detection range and movement speed scale proportionally to the acoustic resonance of the floor surface beneath the player when an action occurs. Hard surfaces (hardwood, bathroom tile, loose clutter) create high-amplitude vibrations that instantly send the monster into a sprint, while dampening surfaces (runner rugs, bath mats, carpet) halve its detection radius and keep it in a slow stalking gait.
System State Read: Reads current_surface_resonance (a float multiplier from 0.2 to 2.0) from the Familiar House & Environment System (Member 3).
How Players Figure It Out: Audio cues and behavioral contrast. When clapping or stepping on bare hardwood, the monster lets out an immediate shriek and closes the distance in seconds. When doing the exact same action while standing on the living room area rug, the monster merely grunts and wanders slowly toward the hallway. Observant players notice that rugs act as safe acoustic islands where they can pulse with much less risk.
Rule 3: The Gasp Response (Vocal Freeze)
The Rule: When the monster comes within proximity (under 2 meters), it cannot detect static collision or player touch, but it enters an acute sensory lock: any audio pulse or involuntary breathing vocalization triggers an instant, un-dodgeable kill strike. Holding breath guarantees survival even if the monster physically brushes past the player.
System State Read: Reads is_holding_breath (boolean) and vocal_noise_level (float) from the Sanity / Breath Control System (Member 4).
How Players Figure It Out: Players trapped in a dead-end room will naturally stop moving. If they don't hold their breath, their character's stamina meter depletes, triggering a forced audible gasp—followed immediately by an instant kill. In subsequent runs, players who hold their breath notice the monster walking right along their collision box without triggering an attack, learning that proximity alone isn't lethal—only breathing is.


Scariest Momment:
Location: Upstairs Hallway (outside the linen closet)
Rules in Play: Rule 1 (Ghost Coordinate), Rule 2 (Resonance Amplification), Rule 3 (Gasp Response)
You run out of steps in the dark and fire an echo to find the stairs. The pulse illuminates the hallway—and reveals the monster standing inches from your face.
You scramble back toward the linen closet, but your foot hits bare hardwood, triggering a loud resonance spike (Rule 2) while the monster charges the doorway you just pulsed from (Rule 1). You dive inside the closet and hold your breath. The screen fades to black, and the monster stops right in the open doorway, inches away, sniffing the air—leaving you pinned and praying your lung meter doesn't run out before it turns around (Rule 3).

## Playable environment system (Samaii)

Open `echoes-of-home/project.godot` with Godot 4.3 to run the fixed two-story
house blockout. WASD/mouse move and look, Space pulses, E interacts, Shift sprints,
and F6 while playing toggles the resonance freeze test.

See [Environment implementation, integration, and test results](docs/ENVIRONMENT_SYSTEM.md)
for the four floor types, key/deadbolt escape loop, optional chain, controller
integration, validation commands, and limits of the currently available team systems.
Kai's acoustic implementation and original test scene remain unchanged.
