import SwiftUI

/// One route, shown as the points that actually require a decision:
/// **boarding → each transfer → final stop**. Intermediate stations are
/// summarised as a count rather than listed.
///
/// Every point names its line(s) in the line's own colour; a transfer point
/// shows `(X → Y)`. Each ride between two points states the direction, i.e. the
/// terminus of that line in the direction of travel — exactly what the platform
/// sign reads. The final stop shows no direction, because there is nothing left
/// to board.
struct RouteDetailView: View {
    let route: Route

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryHeader

                // The journey can begin away from the boarding station: at a
                // split interchange you walk in first.
                if let walk = route.leadingWalkMinutes, let first = route.legs.first {
                    // Labelled with the lines that serve this station, NOT the
                    // line boarded after the walk — a Metrobüs stop is not on
                    // the metro you catch at the station next door.
                    StopPointRow(station: route.origin, arrivingAt: nil,
                                 kind: .walkEndpoint(lines: route.originLines))
                    WalkRow(minutes: walk, to: first.boarding.name)
                }

                ForEach(Array(route.legs.enumerated()), id: \.element.id) { index, leg in
                    // The point you are standing at before riding this leg:
                    // the origin for the first leg, a transfer for the rest.
                    StopPointRow(
                        station: leg.boarding,
                        // Inside an interchange complex the two lines' stations
                        // carry different official names, so the row must show
                        // where you get off as well as where you get on.
                        arrivingAt: index == 0 ? nil : route.legs[index - 1].alighting,
                        kind: index == 0
                            ? .origin(line: leg.line)
                            : .transfer(from: route.legs[index - 1].line, to: leg.line)
                    )
                    RideRow(leg: leg)
                }

                if let last = route.legs.last {
                    StopPointRow(station: last.alighting, arrivingAt: nil,
                                 kind: .destination(line: last.line))
                    if let walk = route.trailingWalkMinutes {
                        WalkRow(minutes: walk, to: route.destination.name)
                        StopPointRow(station: route.destination, arrivingAt: nil,
                                     kind: .walkEndpoint(lines: route.destinationLines))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .navigationTitle(route.primaryCriterion.title)
    }

    private var summaryHeader: some View {
        HStack(spacing: 0) {
            stat(route.totalMinutesText, "dakika")
            Divider().frame(height: 34)
            stat("\(route.transferCount)", "aktarma")
            Divider().frame(height: 34)
            stat("\(route.stopCount)", "durak")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 23, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Points

/// What a point on the route is, and which line(s) it names.
enum StopPointKind {
    case origin(line: Line)
    case transfer(from: Line, to: Line)
    case destination(line: Line)
    /// A station you walk to or from. It belongs to its own lines, which are
    /// usually *not* the line ridden on the adjacent leg.
    case walkEndpoint(lines: [Line])

    /// The colour of the dot — the line you are *leaving on* where there is
    /// one, otherwise the line you arrived on.
    var markerColor: Color {
        switch self {
        case .origin(let line):         return line.color
        case .transfer(_, let to):      return to.color
        case .destination(let line):    return line.color
        case .walkEndpoint(let lines):  return lines.first?.color ?? .secondary
        }
    }

    var isTransfer: Bool {
        if case .transfer = self { return true }
        return false
    }
}

/// A station on the route: name, then its line(s) in parentheses, coloured.
struct StopPointRow: View {
    let station: Station
    /// Where you get *off*, when that is a differently-named station of the
    /// same interchange complex (M7 "Mecidiyeköy" → M2 "Şişli-Mecidiyeköy").
    /// Nil when arrival and departure are the same station.
    let arrivingAt: Station?
    let kind: StopPointKind

    /// True when the transfer walks between two separate stations.
    private var spansTwoStations: Bool {
        guard let arrivingAt else { return false }
        return arrivingAt.id != station.id
    }

    /// Only worth printing both names when they actually read differently —
    /// a Metrobüs stop and the rail station beside it often share a name, and
    /// "Zeytinburnu → Zeytinburnu" is noise. The line badges disambiguate.
    private var showsBothNames: Bool {
        guard let arrivingAt, spansTwoStations else { return false }
        return arrivingAt.name != station.name
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            marker

            VStack(alignment: .leading, spacing: 3) {
                if showsBothNames, let arrivingAt {
                    Text("\(arrivingAt.name) → \(station.name)")
                        .font(.system(size: 17, weight: .semibold))
                } else {
                    Text(station.name)
                        .font(.system(size: 17, weight: .semibold))
                }

                lineLabel
                    .font(.system(size: 14, weight: .medium))

                if kind.isTransfer {
                    Text(spansTwoStations ? "aktarma · yürüme" : "aktarma")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// `(M4)` for a plain stop, `(M4 → B1)` at a transfer — each id in its own
    /// line colour, built by concatenating Text so it wraps as one run.
    private var lineLabel: Text {
        switch kind {
        case .origin(let line), .destination(let line):
            return Text("(") + tinted(line) + Text(")")
        case .transfer(let from, let to):
            return Text("(") + tinted(from) + Text(" → ") + tinted(to) + Text(")")
        case .walkEndpoint(let lines):
            guard let first = lines.first else { return Text("") }
            return lines.dropFirst().reduce(Text("(") + tinted(first)) {
                $0 + Text(", ") + tinted($1)
            } + Text(")")
        }
    }

    private func tinted(_ line: Line) -> Text {
        Text(line.id).foregroundColor(line.color).bold()
    }

    private var marker: some View {
        Circle()
            .strokeBorder(kind.markerColor, lineWidth: 4)
            .background(Circle().fill(.background))
            .frame(width: 17, height: 17)
            .padding(.top, 2)
    }
}

/// A walk between two stations of one interchange complex, at the start or end
/// of a journey. Drawn with a dashed spine so it never reads as a ride.
struct WalkRow: View {
    let minutes: Double
    let to: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 5, dash: [4, 5]))
                .foregroundStyle(.secondary)
                .frame(width: 5)
                .frame(minHeight: 44)
                .padding(.leading, 6)

            VStack(alignment: .leading, spacing: 3) {
                Label("\(to) istasyonuna yürüyün", systemImage: "figure.walk")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(formatMinutes(minutes)) dk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Rides

/// The ride between two points: which line, which direction, how long.
struct RideRow: View {
    let leg: RouteLeg

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // The coloured spine connecting the two station dots.
            Rectangle()
                .fill(leg.line.color)
                .frame(width: 5)
                .frame(minHeight: 52)
                .clipShape(Capsule())
                .padding(.leading, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    LineBadge(line: leg.line, size: 12)
                    if let direction = leg.directionText {
                        Text(direction)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(leg.line.color)
                    }
                }
                Text("\(leg.stopCount) durak · \(leg.minutesText) dk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
