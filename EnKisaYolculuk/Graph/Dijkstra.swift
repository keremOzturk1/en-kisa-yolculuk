import Foundation

/// Plain Dijkstra over `LineExpandedGraph`, generalised in exactly one way: the
/// ordering on `PathCost` is supplied by the caller (`RouteCriterion`).
///
/// This is still ordinary Dijkstra, not a variant: every cost component is
/// non-negative and additive, and each criterion's ordering is a lexicographic
/// order on those components, so the "shortest prefix" property holds and the
/// algorithm is optimal for each criterion.
enum Dijkstra {

    struct Result {
        /// Node indexes into `LineExpandedGraph.nodes`, origin first.
        let path: [Int]
        let cost: PathCost
    }

    /// Multi-source / multi-target shortest path.
    ///
    /// `sources` and `targets` are the platform sets of the origin and
    /// destination stations — the virtual START/END nodes of CONTEXT §4.2,
    /// whose 0-weight edges are folded into the seeding and termination.
    static func shortestPath(
        in graph: LineExpandedGraph,
        from sources: [Int],
        to targets: Set<Int>,
        criterion: RouteCriterion
    ) -> Result? {
        guard !sources.isEmpty, !targets.isEmpty else { return nil }

        let count = graph.nodeCount
        var best = [PathCost?](repeating: nil, count: count)
        var parent = [Int](repeating: -1, count: count)
        var settled = [Bool](repeating: false, count: count)

        var queue = CostPriorityQueue(isLower: criterion.isLower)
        for source in sources {
            // A source platform that is *also* a target means origin ==
            // destination; handled by the caller, but harmless here.
            best[source] = .zero
            queue.push(node: source, cost: .zero)
        }

        while let current = queue.pop() {
            if settled[current.node] { continue }
            settled[current.node] = true

            if targets.contains(current.node) {
                return Result(path: reconstructPath(to: current.node, parent: parent),
                              cost: current.cost)
            }

            for edge in graph.adjacency[current.node] where !settled[edge.to] {
                let candidate = current.cost.adding(minutes: edge.minutes, isTransfer: edge.isTransfer)
                if best[edge.to] == nil || criterion.isLower(candidate, best[edge.to]!) {
                    best[edge.to] = candidate
                    parent[edge.to] = current.node
                    queue.push(node: edge.to, cost: candidate)
                }
            }
        }

        return nil // destination unreachable from origin
    }

    private static func reconstructPath(to node: Int, parent: [Int]) -> [Int] {
        var path: [Int] = []
        var cursor = node
        while cursor != -1 {
            path.append(cursor)
            cursor = parent[cursor]
        }
        return path.reversed()
    }
}

/// Lazy-deletion binary min-heap keyed by a caller-supplied ordering.
/// (Swift has no stdlib priority queue; this keeps the dependency count at 0.)
private struct CostPriorityQueue {
    private struct Element {
        let node: Int
        let cost: PathCost
    }

    private var storage: [Element] = []
    private let isLower: (PathCost, PathCost) -> Bool

    init(isLower: @escaping (PathCost, PathCost) -> Bool) {
        self.isLower = isLower
    }

    mutating func push(node: Int, cost: PathCost) {
        storage.append(Element(node: node, cost: cost))
        siftUp(from: storage.count - 1)
    }

    mutating func pop() -> (node: Int, cost: PathCost)? {
        guard let first = storage.first else { return nil }
        storage.swapAt(0, storage.count - 1)
        storage.removeLast()
        if !storage.isEmpty { siftDown(from: 0) }
        return (first.node, first.cost)
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard isLower(storage[child].cost, storage[parent].cost) else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = 2 * parent + 1
            let right = left + 1
            var smallest = parent
            if left < storage.count, isLower(storage[left].cost, storage[smallest].cost) {
                smallest = left
            }
            if right < storage.count, isLower(storage[right].cost, storage[smallest].cost) {
                smallest = right
            }
            if smallest == parent { return }
            storage.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
