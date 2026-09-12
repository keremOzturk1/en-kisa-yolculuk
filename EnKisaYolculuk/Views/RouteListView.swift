import SwiftUI

/// The three alternatives. STUB — real visual design comes later.
struct RouteListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            if appState.routes.isEmpty {
                ContentUnavailableView("Rota bulunamadı", systemImage: "questionmark.circle")
            } else {
                ForEach(appState.routes) { route in
                    NavigationLink {
                        RouteDetailView(route: route)
                    } label: {
                        RouteSummaryCard(route: route)
                    }
                    .accessibilityIdentifier("routeCard")
                }
            }
        }
        .navigationTitle("Alternatifler")
    }
}

/// One row: criteria labels, the headline numbers, and the line sequence.
struct RouteSummaryCard: View {
    let route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(route.criteria) { criterion in
                    Label(criterion.title, systemImage: criterion.systemImageName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(route.totalMinutesText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("dk")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                // Each icon is bound tightly to its own number, and the two
                // metrics are pushed well apart — otherwise the transfer count
                // reads as if it belonged to the stop icon beside it. The unit
                // words remove the ambiguity outright.
                HStack(spacing: 16) {
                    metric("arrow.triangle.swap", route.transferCount, "aktarma")
                    metric("smallcircle.filled.circle", route.stopCount, "durak")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // The line sequence, e.g.  M4 › B1
            HStack(spacing: 6) {
                ForEach(Array(route.legs.enumerated()), id: \.offset) { index, leg in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    LineBadge(line: leg.line, size: 13)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// Icon + number + unit, kept as one visually tight group.
    private func metric(_ systemImage: String, _ value: Int, _ unit: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text("\(value)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(unit)
        }
        .fixedSize()
    }
}

#Preview {
    NavigationStack {
        RouteListView().environmentObject(AppState())
    }
}
