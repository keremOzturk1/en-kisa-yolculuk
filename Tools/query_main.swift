import Foundation

// Ad-hoc route query against any network.json, without Xcode.
// Driven by Tools/route.sh — see that script for usage.

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: route.sh <network.json> [<from-id> <to-id>]")
    exit(2)
}

do {
    let network = try NetworkLoader.load(contentsOf: URL(fileURLWithPath: args[1]))
    let service = RouteService(network: network)

    guard args.count >= 4 else {
        // No endpoints given: list what is available.
        print("\(network.stations.count) stations, \(network.lines.count) lines, \(network.segments.count) segments\n")
        let graph = LineExpandedGraph(network: network)
        print("station ids:")
        for station in network.stationsSortedByName {
            let lines = graph.platforms(at: station.id).map { graph.node(at: $0).line }.sorted()
            print("  \(station.id.padding(toLength: max(28, station.id.count), withPad: " ", startingAt: 0)) \(station.name)  [\(lines.joined(separator: ", "))]")
        }
        exit(0)
    }

    let routes = try service.routes(from: args[2], to: args[3])
    let origin = network.station(args[2])!.name
    let destination = network.station(args[3])!.name
    print("\(origin) → \(destination)\n")
    for route in routes {
        print("[\(route.criteria.map(\.title).joined(separator: " + "))]  \(route.totalMinutesText) dk · \(route.transferCount) aktarma · \(route.stopCount) durak")
        if let walk = route.leadingWalkMinutes, let first = route.legs.first {
            print("  ● \(route.origin.name)")
            print("  ┆   yürüyüş → \(first.boarding.name)  ·  \(formatMinutes(walk)) dk")
        }
        for (index, leg) in route.legs.enumerated() {
            let point: String
            if index == 0 {
                point = "\(leg.boarding.name) (\(leg.line.id))"
            } else {
                let previous = route.legs[index - 1]
                // Inside a complex the two lines use different official names.
                let where_ = previous.alighting.name == leg.boarding.name
                    ? leg.boarding.name
                    : "\(previous.alighting.name) → \(leg.boarding.name)"
                point = "\(where_) (\(previous.line.id) → \(leg.line.id))"
            }
            print("  ● \(point)")
            print("  │   \(leg.line.id) · \(leg.directionText ?? "yön yok")  ·  \(leg.stopCount) durak · \(leg.minutesText) dk")
        }
        if let last = route.legs.last {
            print("  ● \(last.alighting.name) (\(last.line.id))")
            if let walk = route.trailingWalkMinutes {
                print("  ┆   yürüyüş → \(route.destination.name)  ·  \(formatMinutes(walk)) dk")
                print("  ● \(route.destination.name)")
            }
        }
        print("")
    }
} catch {
    print("FATAL: \(error.localizedDescription)")
    exit(1)
}
