// nav/grid: paths through cell worlds. nav/crowd: walkers stepping round each other.
package main

import (
    "math/geom"
    "math/rand"
    "nav/crowd"
    "nav/grid"
    "time"
)

var failures = 0

func check(ok: bool, what: string) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

func c(x: int32, y: int32, z: int32) -> geom.IVec3 { return geom.IVec3(x, y, z) }

func main() -> int32 {
    let two = grid.Agent(height: 2)

    // A floor at y = 0, from x and z -20 to 20.
    let floor: (geom.IVec3) -> bool = { p in p.Y <= 0 && abs(p.X) <= 20 && abs(p.Z) <= 20 }
    let flat = grid.Terrain(solid: floor)
    check(grid.Stands(c(0, 1, 0), two, flat) && !grid.Stands(c(0, 2, 0), two, flat) && !grid.Stands(c(0, 0, 0), two, flat),
          "an agent stands on the floor, not in the air or in the ground")
    check(grid.Settle(c(3, 6, 3), two, flat) == c(3, 1, 3) && grid.Settle(c(3, -2, 3), two, flat) == c(3, 1, 3),
          "Settle drops onto the floor and climbs out of it")

    if let p = grid.Find(from: c(0, 1, 0), to: c(6, 1, 0), agent: two, terrain: flat) {
        check(p.Complete && p.Cells.count == 7 && p.End == c(6, 1, 0), "a straight walk is the cells in a line (\(p.Cells.count))")
    } else { check(false, "a straight walk is found") }
    if let p = grid.Find(from: c(0, 1, 0), to: c(5, 1, 5), agent: two, terrain: flat) {
        check(p.Complete && p.Cells.count == 6, "a diagonal walk goes corner to corner (\(p.Cells.count) cells)")
    } else { check(false, "a diagonal walk is found") }

    // A wall at x = 3, z -10…10, two high, with a gap at z = 8.
    let wall: (geom.IVec3) -> bool = { p in floor(p) || (p.X == 3 && abs(p.Z) <= 10 && p.Z != 8 && p.Y >= 1 && p.Y <= 2) }
    let walled = grid.Terrain(solid: wall)
    if let p = grid.Find(from: c(0, 1, 0), to: c(6, 1, 0), agent: two, terrain: walled) {
        check(p.Complete && p.Cells.contains(c(3, 1, 8)) && !p.Cells.contains(where: { wall($0) }),
              "a wall too high to climb is walked round, through the gap")
    } else { check(false, "the way round a wall is found") }

    // The same wall, one high: hop over it.
    let low: (geom.IVec3) -> bool = { p in floor(p) || (p.X == 3 && abs(p.Z) <= 10 && p.Y == 1) }
    if let p = grid.Find(from: c(0, 1, 0), to: c(6, 1, 0), agent: two, terrain: grid.Terrain(solid: low)) {
        check(p.Complete && p.Cells.contains(c(3, 2, 0)) && p.Cells.count == 7, "a one-high wall is stepped over")
    } else { check(false, "a step over is found") }

    // A ledge: a platform y 1…4 for x ≥ 5. Up is a climb of 4; down is a drop.
    let ledge: (geom.IVec3) -> bool = { p in floor(p) || (p.X >= 5 && p.X <= 20 && abs(p.Z) <= 20 && p.Y <= 4) }
    let cliff = grid.Terrain(solid: ledge)
    if let p = grid.Find(from: c(0, 1, 0), to: c(8, 5, 0), agent: two, terrain: cliff) {
        check(!p.Complete, "a ledge four high can't be climbed: the path is incomplete")
    } else { check(false, "an incomplete path comes back") }
    if let p = grid.Find(from: c(8, 5, 0), to: c(0, 1, 0), agent: grid.Agent(height: 2, maxDrop: 4), terrain: cliff) {
        check(p.Complete, "but it can be dropped from by an agent that falls four")
    } else { check(false, "the drop is found") }
    if let p = grid.Find(from: c(8, 5, 0), to: c(0, 1, 0), agent: two, terrain: cliff) {
        check(!p.Complete, "and not by one that falls three")
    } else { check(false, "the refused drop gives a path") }

    // A pond: water at y 1 where x is -3…3 and z 4…12, the floor under it.
    let pond: (geom.IVec3) -> bool = { p in abs(p.X) <= 3 && p.Z >= 4 && p.Z <= 12 && p.Y == 1 }
    let wet = grid.Terrain(solid: floor, fluid: pond)
    if let p = grid.Find(from: c(0, 1, 2), to: c(0, 1, 14), agent: two, terrain: wet) {
        check(p.Complete && !p.Cells.contains(where: { pond($0) }), "a pond is walked round, as swimming costs more")
    } else { check(false, "the way round a pond is found") }
    if let p = grid.Find(from: c(0, 1, 2), to: c(0, 1, 8), agent: two, terrain: wet) {
        check(p.Complete && p.End == c(0, 1, 8), "but swum into when the goal is in it")
    } else { check(false, "a swim is found") }
    var dry = two
    dry.Swims = false
    if let p = grid.Find(from: c(0, 1, 2), to: c(0, 1, 8), agent: dry, terrain: wet) {
        check(!p.Complete && !p.Cells.contains(where: { pond($0) }), "an agent that doesn't swim stays out")
    } else { check(false, "a dry path comes back") }

    // Costs: a strip to avoid entirely.
    let fire = grid.Terrain(solid: floor, cost: { p in p.X == 3 && abs(p.Z) <= 2 ? -1 : 0 })
    if let p = grid.Find(from: c(0, 1, 0), to: c(6, 1, 0), agent: two, terrain: fire) {
        check(p.Complete && !p.Cells.contains(where: { $0.X == 3 && abs($0.Z) <= 2 }), "cells with a negative cost are never stood in")
    } else { check(false, "a path round the avoided cells is found") }

    // Corners aren't cut: a pillar at (1, 1…2, 1) blocks the diagonal past it.
    let pillar: (geom.IVec3) -> bool = { p in floor(p) || (p.X == 1 && p.Z == 0 && p.Y >= 1 && p.Y <= 2) }
    if let p = grid.Find(from: c(0, 1, 0), to: c(1, 1, 1), agent: two, terrain: grid.Terrain(solid: pillar)) {
        check(p.Cells.count == 3, "a diagonal past a pillar's corner goes round it (\(p.Cells.count) cells)")
    } else { check(false, "the way round a corner is found") }

    // The search is bounded: a goal far outside its reach still answers
    // quickly, as near as it could get.
    let open = grid.Terrain(solid: { p in p.Y <= 0 })
    let start = time.Instant.Now()
    if let p = grid.Find(from: c(0, 1, 0), to: c(500, 1, 0), agent: two, terrain: open, limits: grid.Limits(nodes: 800, distance: 40)) {
        let ms = start.Elapsed().AsMilliseconds()
        print("      \(p.Cells.count) cells toward a goal 500 away, in \(ms) ms")
        check(!p.Complete && p.End.X >= 30, "a far goal gives the way toward it, within the limits (end x \(p.End.X))")
    } else { check(false, "a far goal gives a path") }

    // Pick: random targets, all standable, preferring what score likes.
    var r = rand.Xorshift128Plus(seed: 7)
    var picked = 0, onLeft = 0
    for _ in 0..<50 {
        if let t = grid.Pick(around: c(0, 1, 0), across: 10, vertical: 3, tries: 10, agent: two, terrain: flat,
                             random: { float32(r.Float64()) }, score: { p in p.X < 0 ? 1 : 0 }) {
            if grid.Stands(t, two, flat) { picked += 1 }
            if t.X < 0 { onLeft += 1 }
        }
    }
    check(picked == 50 && onLeft >= 45, "Pick finds standable cells, and the ones the score prefers (\(onLeft) of 50)")

    // Follower: walks the path cell by cell, saying when to jump.
    if let p = grid.Find(from: c(0, 1, 0), to: c(6, 1, 0), agent: two, terrain: grid.Terrain(solid: low)) {
        var f = grid.Follower(p)
        var at = geom.DVec3(0.5, 1, 0.5)
        var jumps = 0, steps = 0
        while let w = f.Next(from: at), steps < 100 {
            if w.Jump { jumps += 1; at = geom.DVec3(at.X, w.Target.Y, at.Z) }
            // Move a quarter of a cell toward the target.
            let x = w.Target.X - at.X, z = w.Target.Z - at.Z
            let len = (x * x + z * z).squareRoot()
            if len > 0.001 { at = at + geom.DVec3(x / len * 0.25, 0, z / len * 0.25) }
            if w.Target.Y < at.Y && len < 0.5 { at = geom.DVec3(at.X, w.Target.Y, at.Z) }
            steps += 1
        }
        check(f.Done && at.Floor() == c(6, 1, 0) && jumps > 0, "a follower reaches the end, jumping onto the wall (\(steps) steps)")
    } else { check(false, "a path to follow is found") }

    crowds()

    if failures == 0 { print("all passed") } else { print("\(failures) failed") }
    return failures == 0 ? 0 : 1
}

// walk moves a crowd for `seconds`, each walker wanting `wants[i]`, and
// answers the closest any two came (edge to edge).
func walk(c: crowd.Crowd, wants: [geom.Vec3], seconds: float32) -> float32 {
    let dt: float32 = 1.0 / 30
    var closest: float32 = 1e9
    var t: float32 = 0
    while t < seconds {
        c.Update()
        var v: [geom.Vec3] = []
        for i in 0..<c.Walkers.count { v.append(c.Steer(i, wants[i])) }
        for i in 0..<c.Walkers.count {
            c.Walkers[i].Velocity = v[i]
            c.Walkers[i].Position = c.Walkers[i].Position + v[i] * dt
        }
        for i in 0..<c.Walkers.count {
            for k in (i + 1)..<c.Walkers.count {
                let d = (c.Walkers[i].Position - c.Walkers[k].Position).Length() - c.Walkers[i].Radius - c.Walkers[k].Radius
                if d < closest { closest = d }
            }
        }
        t += dt
    }
    return closest
}

func crowds() {
    // Near: by place, through the cells.
    let c = crowd.Crowd()
    for i in 0..<10 { c.Add(crowd.Walker(at: geom.Vec3(float32(i), 0, 0))) }
    c.Update()
    let near = c.Near(geom.Vec3(4.2, 0, 0.5), within: 1.5)
    check(near.count == 3 && near.contains(3) && near.contains(4) && near.contains(5), "Near finds the walkers within reach (\(near))")

    // Head on: they pass each other, not through.
    let h = crowd.Crowd()
    h.Add(crowd.Walker(at: geom.Vec3(-5, 0, 0)))
    h.Add(crowd.Walker(at: geom.Vec3(5, 0, 0)))
    let gap = walk(h, [geom.Vec3(1.5, 0, 0), geom.Vec3(-1.5, 0, 0)], seconds: 7)
    check(gap > 0 && h.Walkers[0].Position.X > 4 && h.Walkers[1].Position.X < -4,
          "two walkers meeting head on pass each other (closest \(gap) m apart; at \(h.Walkers[0].Position.X), \(h.Walkers[1].Position.X))")

    // One holding its line: the other does all the stepping aside.
    let y = crowd.Crowd()
    var player = crowd.Walker(at: geom.Vec3(-5, 0, 0))
    player.Yield = 0
    y.Add(player)
    y.Add(crowd.Walker(at: geom.Vec3(5, 0, 0)))
    let gap2 = walk(y, [geom.Vec3(2, 0, 0), geom.Vec3(-1.5, 0, 0)], seconds: 7)
    check(gap2 > -0.05 && abs(y.Walkers[0].Position.Z) < 0.001, "a walker that doesn't yield keeps its line and the other gets out of its way (closest \(gap2) m)")

    // A huddle spreads out, and no one wanders off.
    let b = crowd.Crowd()
    var g = rand.Xorshift128Plus(seed: 3)
    for _ in 0..<20 { b.Add(crowd.Walker(at: geom.Vec3(float32(g.Float64()) * 1.2, 0, float32(g.Float64()) * 1.2))) }
    var still: [geom.Vec3] = []
    for _ in 0..<20 { still.append(geom.Vec3.Zero) }
    _ = walk(b, still, seconds: 6)
    var worst: float32 = 1e9
    var far: float32 = 0
    for i in 0..<20 {
        far = max(far, b.Walkers[i].Position.Length())
        for k in (i + 1)..<20 {
            worst = min(worst, (b.Walkers[i].Position - b.Walkers[k].Position).Length() - 0.6)
        }
    }
    check(worst > -0.05 && far < 4, "a huddle of twenty spreads out until no one overlaps (closest \(worst) m, farthest \(far) m out)")

    // Crossing streams: two lines of eight walk through each other.
    let x = crowd.Crowd()
    var wants: [geom.Vec3] = []
    for i in 0..<8 {
        x.Add(crowd.Walker(at: geom.Vec3(-6, 0, float32(i) * 0.8 - 2.8)))
        wants.append(geom.Vec3(1.4, 0, 0))
    }
    for i in 0..<8 {
        x.Add(crowd.Walker(at: geom.Vec3(float32(i) * 0.8 - 2.8, 0, -6)))
        wants.append(geom.Vec3(0, 0, 1.4))
    }
    let gap3 = walk(x, wants, seconds: 10)
    var through = 0
    for i in 0..<8 where x.Walkers[i].Position.X > 4 { through += 1 }
    for i in 8..<16 where x.Walkers[i].Position.Z > 4 { through += 1 }
    check(gap3 > -0.12 && through == 16, "two streams cross with no one walking through anyone (closest \(gap3) m; \(through) of 16 across)")

    // A wood: walkers cross a field of trunks without walking into one.
    let wood = crowd.Crowd()
    var g2 = rand.Xorshift128Plus(seed: 11)
    // Trunks at least 2 m apart, as a forest's are (closer, local steering
    // can be boxed in; that's pathfinding's job).
    while wood.Obstacles.count < 60 {
        let p = geom.Vec3(float32(g2.Float64()) * 20 - 10, 0, float32(g2.Float64()) * 20 - 10)
        var clear = true
        for o in wood.Obstacles where (o.Position - p).Length() < 2 { clear = false }
        if clear { wood.Obstacles.append(crowd.Obstacle(at: p, radius: 0.3)) }
    }
    wood.PlaceObstacles()
    var wants2: [geom.Vec3] = []
    for i in 0..<6 {
        wood.Add(crowd.Walker(at: geom.Vec3(-14, 0, float32(i) * 2.4 - 6)))
        wants2.append(geom.Vec3(1.4, 0, 0))
    }
    let dt: float32 = 1.0 / 30
    var into: float32 = 0
    for _ in 0..<600 {
        wood.Update()
        var vs: [geom.Vec3] = []
        for i in 0..<wood.Walkers.count { vs.append(wood.Steer(i, wants2[i])) }
        for i in 0..<wood.Walkers.count {
            wood.Walkers[i].Velocity = vs[i]
            wood.Walkers[i].Position = wood.Walkers[i].Position + vs[i] * dt
            for o in wood.Obstacles {
                var d = wood.Walkers[i].Position - o.Position
                d.Y = 0
                into = max(into, 0.3 + o.Radius - d.Length())
            }
        }
    }
    var across = 0
    for w in wood.Walkers where w.Position.X > 10 { across += 1 }
    check(into < 0.08 && across >= 5, "walkers cross a wood of 60 trunks without walking into one (at worst \(into) m in; \(across) of 6 across)")
}
