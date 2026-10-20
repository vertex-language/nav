// Package grid finds ways through worlds made of cells: block worlds, tile
// maps, voxel volumes. An agent stands in a cell when the cells its body
// fills are clear and the one under its feet holds it up (or it can swim
// where it is). From there it can go to the eight cells around, stepping
// up as high as it can climb and dropping as far as it will fall.
//
// The world is three questions asked of a cell (`Terrain`), so the same
// search runs over a voxel.Grid, a tile map or a test's closure. Searches
// are bounded by nodes and distance, so they cost the same in an endless
// world as in a small one, and an unreachable goal gives the way to as
// near it as the agent can get.
package grid

import (
    "math"
    "math/geom"
)

/// Terrain is what a search asks of a cell.
public struct Terrain {
    /// Solid is whether a cell blocks a body and can be stood on.
    public var Solid: (geom.IVec3) -> bool
    /// Fluid is whether a cell can be swum in: it holds an agent up
    /// without being stood on.
    public var Fluid: (geom.IVec3) -> bool
    /// Cost is the extra cost of standing in a cell, on top of the
    /// distance walked; negative means never (fire, cactus, a ledge).
    public var Cost: (geom.IVec3) -> float32

    public init(solid: @escaping (geom.IVec3) -> bool,
                fluid: @escaping (geom.IVec3) -> bool = { _ in false },
                cost: @escaping (geom.IVec3) -> float32 = { _ in 0 }) {
        Solid = solid
        Fluid = fluid
        Cost = cost
    }
}

/// Agent is the body a path is for.
public struct Agent {
    /// Height is how many cells tall the body is.
    public var Height: int32 = 1
    /// StepUp is how many cells it climbs in one step (a jump).
    public var StepUp: int32 = 1
    /// MaxDrop is how far it will fall to get somewhere.
    public var MaxDrop: int32 = 3
    /// Swims is whether it goes through fluid cells at all.
    public var Swims = true
    /// SwimCost is the extra cost of each cell spent swimming.
    public var SwimCost: float32 = 4

    public init(height: int32 = 1, stepUp: int32 = 1, maxDrop: int32 = 3, swims: bool = true) {
        Height = height
        StepUp = stepUp
        MaxDrop = maxDrop
        Swims = swims
    }
}

/// Limits bound a search.
public struct Limits {
    /// Nodes is how many cells it may expand before it settles for the
    /// nearest it found.
    public var Nodes = 1200
    /// Distance is how far from the start, across, it may look.
    public var Distance: int32 = 48

    public init(nodes: int = 1200, distance: int32 = 48) {
        Nodes = nodes
        Distance = distance
    }
}

/// Path is a way from one cell to another: the cells an agent's feet
/// pass through, the start first.
public struct Path {
    public var Cells: [geom.IVec3]
    /// Complete is whether it ends at the goal; an incomplete path ends
    /// as near it as the search could get.
    public var Complete: bool
    /// Cost is its length, with climbs, swims and terrain costs added.
    public var Cost: float32

    public init(cells: [geom.IVec3], complete: bool, cost: float32) {
        Cells = cells
        Complete = complete
        Cost = cost
    }

    public var End: geom.IVec3 { return Cells[Cells.count - 1] }
}

let up = geom.IVec3(int32(0), 1, 0)

/// Clear is whether an agent's body fits with its feet in c.
public func Clear(_ c: geom.IVec3, _ agent: Agent, _ t: Terrain) -> bool {
    var i: int32 = 0
    while i < agent.Height {
        if t.Solid(c + up * i) { return false }
        i += 1
    }
    return true
}

/// Stands is whether an agent can be with its feet in c: its body fits,
/// and the cell below holds it up or it is swimming, and the cell isn't
/// one to avoid.
public func Stands(_ c: geom.IVec3, _ agent: Agent, _ t: Terrain) -> bool {
    if !Clear(c, agent, t) { return false }
    let fluid = t.Fluid(c)
    if fluid && !agent.Swims { return false }
    if !fluid && !t.Solid(c - up) { return false }
    return t.Cost(c) >= 0
}

/// Settle is the standable cell an agent at c would end up in: c itself,
/// or the first below it within `drop`, or, when c is inside something,
/// the first clear one above it within `rise`. Nil when there is none.
public func Settle(_ c: geom.IVec3, _ agent: Agent, _ t: Terrain, drop: int32 = 8, rise: int32 = 8) -> geom.IVec3? {
    if Stands(c, agent, t) { return c }
    if t.Solid(c) {
        var k: int32 = 1
        while k <= rise {
            let a = c + up * k
            if !t.Solid(a) { return Stands(a, agent, t) ? a : nil }
            k += 1
        }
        return nil
    }
    var k: int32 = 1
    while k <= drop {
        let b = c - up * k
        if t.Solid(b) { return nil }
        if Stands(b, agent, t) { return b }
        k += 1
    }
    return nil
}

// The eight ways across: four straight, then four diagonal.
let dx: [int32] = [1, -1, 0, 0, 1, 1, -1, -1]
let dz: [int32] = [0, 0, 1, -1, 1, -1, 1, -1]

// key packs a cell into an int: 21 bits an axis, which is ±1 million
// cells, far more than a search reaches.
func key(_ c: geom.IVec3) -> int {
    let m = 0x1fffff
    return ((int(c.X) & m) << 42) | ((int(c.Y) & m) << 21) | (int(c.Z) & m)
}

// heuristic is the octile distance across plus the climb: never more
// than a path's true cost, so A* stays optimal.
func heuristic(_ a: geom.IVec3, _ b: geom.IVec3) -> float32 {
    let x = float32(abs(a.X - b.X)), z = float32(abs(a.Z - b.Z)), y = float32(abs(a.Y - b.Y))
    return math.Max(x, z) + 0.41421356 * math.Min(x, z) + y * 0.5
}

/// Find is the cheapest way for an agent from one cell to another, by A*.
/// `from` is settled onto the ground first. When the goal can't be
/// reached within the limits the path goes to the nearest cell it found,
/// with Complete false; nil only when `from` has nowhere to stand.
public func Find(from: geom.IVec3, to goal: geom.IVec3, agent: Agent, terrain t: Terrain,
                 limits: Limits = Limits()) -> Path? {
    guard let start = Settle(from, agent, t, drop: 2, rise: 1) else { return nil }
    var cells: [geom.IVec3] = [start]
    var g: [float32] = [0]
    var parent: [int32] = [-1]
    var closed: [bool] = [false]
    var index: [int: int32] = [key(start): 0]
    var open = heap()
    open.push(heuristic(start, goal), 0)
    var best: int32 = 0
    var bestH = heuristic(start, goal)
    var expanded = 0

    // add offers a way to cell c from node n at a step cost.
    func add(_ c: geom.IVec3, _ n: int32, _ step: float32) {
        let cost = g[int(n)] + step + t.Cost(c) + (t.Fluid(c) ? agent.SwimCost : 0)
        let k = key(c)
        if let i = index[k] {
            if closed[int(i)] || cost >= g[int(i)] { return }
            g[int(i)] = cost
            parent[int(i)] = n
            open.push(cost + heuristic(c, goal), i)
            return
        }
        let i = int32(cells.count)
        cells.append(c)
        g.append(cost)
        parent.append(n)
        closed.append(false)
        index[k] = i
        open.push(cost + heuristic(c, goal), i)
    }

    var found = false
    while let n = open.pop() {
        if closed[int(n)] { continue }
        closed[int(n)] = true
        let c = cells[int(n)]
        if c == goal {
            best = n
            found = true
            break
        }
        let h = heuristic(c, goal)
        if h < bestH {
            bestH = h
            best = n
        }
        expanded += 1
        if expanded >= limits.Nodes { break }

        for d in 0..<8 {
            let side = geom.IVec3(dx[d], 0, dz[d])
            let next = c + side
            if abs(next.X - start.X) > limits.Distance || abs(next.Z - start.Z) > limits.Distance { continue }
            let diagonal = d >= 4
            // No cutting corners: both cells beside a diagonal step must
            // be open at this level.
            if diagonal && (!Clear(c + geom.IVec3(dx[d], 0, 0), agent, t) || !Clear(c + geom.IVec3(int32(0), 0, dz[d]), agent, t)) {
                continue
            }
            let across: float32 = diagonal ? 1.41421356 : 1
            if Clear(next, agent, t) {
                if Stands(next, agent, t) {
                    add(next, n, across)
                } else if !t.Fluid(next) {
                    // Nothing underfoot: fall to the first place to stand.
                    var k: int32 = 1
                    while k <= agent.MaxDrop {
                        let b = next - up * k
                        if t.Solid(b) { break }
                        if Stands(b, agent, t) {
                            add(b, n, across + float32(k) * 0.25)
                            break
                        }
                        k += 1
                    }
                }
            } else if !diagonal {
                // Something in the way: climb onto it, if there's headroom
                // above us to jump.
                var k: int32 = 1
                while k <= agent.StepUp {
                    if t.Solid(c + up * (agent.Height + k - 1)) { break }
                    let a = next + up * k
                    if Stands(a, agent, t) {
                        add(a, n, across + float32(k) * 0.5)
                        break
                    }
                    k += 1
                }
            }
        }
    }

    var length = 0
    var i = best
    while i >= 0 {
        length += 1
        i = parent[int(i)]
    }
    var way = [geom.IVec3](repeating: start, count: length)
    i = best
    var at = length - 1
    while i >= 0 {
        way[at] = cells[int(i)]
        at -= 1
        i = parent[int(i)]
    }
    return Path(cells: way, complete: found, cost: g[int(best)])
}

/// Pick chooses somewhere for an agent to go near `around`, as a random
/// stroll does: `tries` random cells up to `across` away and `vertical`
/// up or down, each settled onto the ground, scored by `score` (higher is
/// better, negative is never), and the best kept. `random` gives numbers
/// in [0, 1). Nil when no try found anywhere to stand.
public func Pick(around: geom.IVec3, across: int32, vertical: int32, tries: int, agent: Agent, terrain t: Terrain,
                 random: () -> float32, score: (geom.IVec3) -> float32 = { _ in 0 }) -> geom.IVec3? {
    var best: geom.IVec3? = nil
    var bestScore: float32 = -1
    for _ in 0..<tries {
        let x = int32(math.Floor(random() * float32(2 * across + 1))) - across
        let y = int32(math.Floor(random() * float32(2 * vertical + 1))) - vertical
        let z = int32(math.Floor(random() * float32(2 * across + 1))) - across
        guard let c = Settle(around + geom.IVec3(x, y, z), agent, t, drop: vertical * 2, rise: vertical * 2) else { continue }
        let s = score(c)
        if s >= 0 && (best == nil || s > bestScore) {
            best = c
            bestScore = s
        }
    }
    return best
}

/// Waypoint is where a follower should head next.
public struct Waypoint {
    /// The middle of the next cell's floor.
    public var Target: geom.DVec3
    /// The next cell is higher than the feet: jump.
    public var Jump: bool
    /// How many cells are left after this one.
    public var Remaining: int
}

/// Follower walks a body along a path: it says where to head, and moves
/// on as each cell is reached.
public struct Follower {
    public var Path: Path
    /// The next cell to reach.
    public var Index: int

    public init(_ path: Path) {
        Path = path
        Index = path.Cells.count > 1 ? 1 : path.Cells.count
    }

    /// Done is whether every cell has been reached.
    public var Done: bool { return Index >= Path.Cells.count }

    /// Next is where to head from feet at `p`, moving past every cell
    /// within `reach` of it across (and less than a cell below or above);
    /// nil when the path is done.
    public mutating func Next(from p: geom.DVec3, reach: float64 = 0.4) -> Waypoint? {
        while Index < Path.Cells.count {
            let c = Path.Cells[Index]
            let x = float64(c.X) + 0.5 - p.X, z = float64(c.Z) + 0.5 - p.Z
            if x * x + z * z < reach * reach && math.Abs(float64(c.Y) - p.Y) < 1.0 {
                Index += 1
            } else {
                break
            }
        }
        if Done { return nil }
        let c = Path.Cells[Index]
        return Waypoint(Target: geom.DVec3(float64(c.X) + 0.5, float64(c.Y), float64(c.Z) + 0.5),
                        Jump: float64(c.Y) > math.Floor(p.Y + 0.01),
                        Remaining: Path.Cells.count - Index - 1)
    }
}

// heap is a binary min-heap of (priority, node).
struct heap {
    var f: [float32] = []
    var n: [int32] = []

    init() {}

    mutating func push(_ p: float32, _ node: int32) {
        f.append(p)
        n.append(node)
        var i = f.count - 1
        while i > 0 {
            let up = (i - 1) / 2
            if f[up] <= f[i] { break }
            f.swapAt(up, i)
            n.swapAt(up, i)
            i = up
        }
    }

    mutating func pop() -> int32? {
        if f.isEmpty { return nil }
        let top = n[0]
        let last = f.count - 1
        f[0] = f[last]
        n[0] = n[last]
        f.removeLast()
        n.removeLast()
        var i = 0
        while true {
            let l = i * 2 + 1, r = l + 1
            var m = i
            if l < f.count && f[l] < f[m] { m = l }
            if r < f.count && f[r] < f[m] { m = r }
            if m == i { break }
            f.swapAt(m, i)
            n.swapAt(m, i)
            i = m
        }
        return top
    }
}
