// Package crowd is how many walkers share the ground: each says where it
// wants to go (a velocity), and the crowd bends that so they step round
// each other instead of through. Two parts:
//
//   - avoidance: for each neighbor, when the two will come closest if
//     both keep going, and how close; one that will brush past within
//     the horizon gets stepped round, sooner and harder the nearer it is;
//   - separation: walkers already overlapping push apart, even standing
//     still, so a crowd that bunches up spreads out.
//
// Neighbors come from a grid of cells, rebuilt once a tick (Update), so
// a walker only looks at the few around it. Positions are feet on the
// ground: Y is ignored. Pure Vertex, no physics, so a server or a test
// can steer a crowd too. ORCA (proposed_graphics_v3.md §10.2) can replace
// Steer's insides later; the API stays.
package crowd

import (
    "math"
    "math/geom"
)

/// Walker is one member of a crowd as the crowd sees it.
public struct Walker {
    /// Where its feet are; Y is ignored.
    public var Position: geom.Vec3
    /// How it is moving now, m/s.
    public var Velocity = geom.Vec3.Zero
    /// How wide it is: the radius others keep clear of.
    public var Radius: float32 = 0.3
    /// Whether others steer round it (false for someone lying down, or
    /// gone).
    public var Solid = true
    /// How much it gives way, 0…1: 0 holds its line (a player), 1 does
    /// all of the stepping aside itself.
    public var Yield: float32 = 1

    public init(at position: geom.Vec3, radius: float32 = 0.3) {
        Position = position
        Radius = radius
    }
}

/// Obstacle is something that doesn't move that walkers go round: a
/// tree trunk, a post, a rock. Feet-level circle; Y is ignored.
public struct Obstacle {
    public var Position: geom.Vec3
    public var Radius: float32

    public init(at position: geom.Vec3, radius: float32) {
        Position = position
        Radius = radius
    }
}

/// Crowd is walkers, found by place, and obstacles they go round.
public final class Crowd {
    public var Walkers: [Walker] = []
    /// What they go round. Set them, then call PlaceObstacles once.
    public var Obstacles: [Obstacle] = []
    /// Cell size of the neighbor grid, meters: about the distance walkers
    /// look ahead.
    public var Cell: float32 = 2.5
    /// How far ahead, in seconds, a walker looks for someone in its way.
    public var Horizon: float32 = 1.5
    /// Space walkers leave between their edges, meters.
    public var Gap: float32 = 0.15
    var cells: [int: [int]] = [:]
    var obstacleCells: [int: [int]] = [:]

    public init() {}

    /// PlaceObstacles files the obstacles by cell: once, after setting
    /// them (they don't move).
    public func PlaceObstacles() {
        obstacleCells = [:]
        for (i, o) in Obstacles.enumerated() {
            let k = key(cellOf(o.Position.X), cellOf(o.Position.Z))
            var list = obstacleCells[k] ?? [int]()
            list.append(i)
            obstacleCells[k] = list
        }
    }

    /// NearObstacles is the obstacles whose edge is within `distance` of a point.
    public func NearObstacles(p: geom.Vec3, within distance: float32) -> [int] {
        var out: [int] = []
        let reach = distance + 1.5
        let x0 = cellOf(p.X - reach), x1 = cellOf(p.X + reach)
        let z0 = cellOf(p.Z - reach), z1 = cellOf(p.Z + reach)
        for cx in x0...x1 {
            for cz in z0...z1 {
                guard let list = obstacleCells[key(cx, cz)] else { continue }
                for i in list {
                    let o = Obstacles[i]
                    let dx = o.Position.X - p.X, dz = o.Position.Z - p.Z
                    let r = distance + o.Radius
                    if dx * dx + dz * dz <= r * r { out.append(i) }
                }
            }
        }
        return out
    }

    /// Add puts a walker in the crowd and answers its index.
    @discardableResult
    public func Add(w: Walker) -> int {
        Walkers.append(w)
        return Walkers.count - 1
    }

    /// Update files the walkers into cells by where they are now: call it
    /// once a tick, after moving them and before Near or Steer.
    public func Update() {
        cells = [:]
        for (i, w) in Walkers.enumerated() where w.Solid {
            let k = key(cellOf(w.Position.X), cellOf(w.Position.Z))
            if cells[k] == nil { cells[k] = [i] } else { cells[k]!.append(i) }
        }
    }

    /// Near is the solid walkers within `distance` of a point (as filed by
    /// the last Update).
    public func Near(p: geom.Vec3, within distance: float32) -> [int] {
        var out: [int] = []
        let x0 = cellOf(p.X - distance), x1 = cellOf(p.X + distance)
        let z0 = cellOf(p.Z - distance), z1 = cellOf(p.Z + distance)
        let d2 = distance * distance
        for cx in x0...x1 {
            for cz in z0...z1 {
                guard let list = cells[key(cx, cz)] else { continue }
                for i in list {
                    let q = Walkers[i].Position
                    let dx = q.X - p.X, dz = q.Z - p.Z
                    if dx * dx + dz * dz <= d2 { out.append(i) }
                }
            }
        }
        return out
    }

    /// Steer is walker i's wanted velocity (m/s over the ground) bent to
    /// keep clear of the others: what it should ask its legs for. Its
    /// speed stays at most the wanted one's (or a slow shuffle, when it
    /// only wants to stand and is being crowded).
    public func Steer(i: int, wanted: geom.Vec3) -> geom.Vec3 {
        let me = Walkers[i]
        let want = geom.Vec3(wanted.X, 0, wanted.Z)
        let speed = want.Length()
        // Far enough to see who it will meet within the horizon, but no
        // farther than a few strides: a sprinter in a crowd would look at
        // everyone.
        let reach = me.Radius + 1 + math.Min(math.Max(speed, me.Velocity.Length()) * Horizon, 4)
        var dodge = geom.Vec3.Zero
        var push = geom.Vec3.Zero
        for j in Near(me.Position, within: reach) where j != i {
            let other = Walkers[j]
            let apart = me.Radius + other.Radius + Gap
            var d = me.Position - other.Position
            d.Y = 0
            let dist = d.Length()
            // Already too close: push apart, harder the deeper.
            if dist < apart {
                let away = dist > 1e-4 ? d / dist : geom.Vec3(i < j ? 1 : -1, 0, 0)
                push += away * ((apart - dist) / apart * 2.5)
            }
            // Coming together: where will they be when closest?
            let rel = want - geom.Vec3(other.Velocity.X, 0, other.Velocity.Z)
            let rel2 = rel.LengthSquared()
            if rel2 < 1e-6 { continue }
            let t = -d.Dot(rel) / rel2
            if t <= 0 || t > Horizon { continue }
            let miss = d + rel * t
            let missDist = miss.Length()
            if missDist >= apart { continue }
            // Step to the side of the miss (to the right if it's dead
            // ahead), more the sooner and the closer.
            let side = missDist > 1e-3 ? miss / missDist : right(want)
            let urgency = (1 - t / Horizon) * (1 - missDist / apart)
            dodge += side * (urgency * math.Max(speed, 1))
        }
        // Obstacles: as a walker standing still that never gives way; and
        // since they can't be walked through, touching one takes away any
        // speed into it (after the cap below, so it always wins).
        var touching: [geom.Vec3] = []
        for j in NearObstacles(me.Position, within: reach) {
            let o = Obstacles[j]
            let apart = me.Radius + o.Radius + Gap
            var d = me.Position - o.Position
            d.Y = 0
            let dist = d.Length()
            if dist < apart {
                let away = dist > 1e-4 ? d / dist : right(want)
                touching.append(away * ((apart - dist) / apart))
            }
            let rel2 = want.LengthSquared()
            if rel2 < 1e-6 { continue }
            let t = -d.Dot(want) / rel2
            if t <= 0 || t > Horizon { continue }
            let miss = d + want * t
            let missDist = miss.Length()
            if missDist >= apart { continue }
            let side = missDist > 1e-3 ? miss / missDist : right(want)
            let urgency = (1 - t / Horizon) * (1 - missDist / apart)
            dodge += side * (urgency * math.Max(speed, 1) * 1.5)
        }
        var v = want + dodge * me.Yield + push * me.Yield
        let cap = math.Max(speed, push.Length() > 0 ? 0.8 : 0)
        let len = v.Length()
        if len > cap && len > 1e-6 { v = v * (cap / len) }
        for t in touching {
            let away = t.Normalized()
            let into = v.Dot(away)
            if into < 0 {
                v -= away * into
                // Blocked head on: slide round it, keeping right.
                if v.Length() < speed * 0.4 {
                    let round = geom.Vec3(away.Z, 0, -away.X)
                    v += (round.Dot(right(want)) >= 0 ? round : -round) * (speed * 0.6)
                }
            }
            v += t * 3
        }
        return v
    }

    func cellOf(x: float32) -> int {
        return int(math.Floor(x / Cell))
    }

    func key(x: int, z: int) -> int {
        return (x + (1 << 20)) << 21 | (z + (1 << 20))
    }
}

// right is to the right of the way a walker wants to go: when two meet
// head on, each keeps right, so they pass on opposite sides.
func right(want: geom.Vec3) -> geom.Vec3 {
    var f = want.LengthSquared() > 1e-6 ? want.Normalized() : geom.Vec3(0, 0, 1)
    f.Y = 0
    return geom.Vec3(-f.Z, 0, f.X)
}
