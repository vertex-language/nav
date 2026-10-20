# nav

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![license: MIT](https://img.shields.io/badge/license-MIT-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](LICENSE)

Finding the way: how a character gets from here to there through the
world it lives in. Pure Vertex, no `gpu`, so a game server or a test can
path as well as a game.

---

## Packages

| Package | What it is |
| :--- | :--- |
| **`nav/crowd`** | Walkers stepping round each other. Each says where it wants to go (a velocity); `Steer` bends it: neighbors it would brush past within `Horizon` seconds are stepped round, sooner and harder the nearer they are (each keeps right when head on), and walkers already overlapping push apart. `Yield` 0 holds its line (a player). Neighbors come from a grid of cells rebuilt once a tick (`Update`, `Near`). `Obstacles` (trunks, posts: circles that don't move, filed once by `PlaceObstacles`) are stepped round the same way, can't be pushed into, and a walker blocked head on slides round to the right. |
| **`nav/grid`** | Paths through worlds made of cells: block worlds, tile maps, voxel volumes. An `Agent` (height in cells, how high it climbs, how far it will drop, whether it swims) stands where its body fits and something holds it up. `Find` is A* over the eight cells around, stepping up, dropping down, never cutting corners, with `Terrain` costs (negative never stands there); it is bounded by `Limits` and, when the goal can't be reached, answers the way to as near it as it got. `Pick` chooses a random place to go nearby, scored (a mob's random stroll). `Follower` walks a body along a `Path`, saying where to head and when to jump. |

Later, as `proposed_graphics_v3.md` §10.2 has it: `nav/mesh` (navmeshes
from triangles) and `nav/path` (A* over polygons, string pulling); ORCA
inside `nav/crowd`'s `Steer`.

---

## Example

```vertex
import "math/geom"
import "nav/grid"

// The world is three questions asked of a cell.
let t = grid.Terrain(solid: { c in world.Solid(c) },
                     fluid: { c in world.Get(c) == water },
                     cost: { c in nextToCactus(c) ? 8 : 0 })
let sheep = grid.Agent(height: 2, stepUp: 1, maxDrop: 3)

if let path = grid.Find(from: here, to: there, agent: sheep, terrain: t) {
    var f = grid.Follower(path)
    // Each tick:
    if let way = f.Next(from: position) {
        steer(toward: way.Target)
        if way.Jump { jump() }
    }
}
```

---

## Performance notes

A search keeps its nodes in flat arrays and finds them by a cell packed
into an `int`, so it never hashes a `geom.IVec3` (`vsc_TODO.md` #61). A
search capped at 800 nodes takes about 6 ms on an M-series Mac; vcraft's
animals search at most 600 nodes within 24 blocks, a few times a second
between them.

---

## Testing

```bash
vsc run check    # grid: standing, walls, steps, ledges, ponds, costs, corners, limits, Pick, Follower; crowd: Near, head on, yielding, a huddle spreading, crossing streams, crossing a wood of trunks
```

---

## License

[MIT](LICENSE)
