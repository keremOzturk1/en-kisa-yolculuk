import SwiftUI

/// The row that sits above every list of alternatives.
///
/// Same visual grammar as `RouteSummaryCard` — capsule badge, then the content —
/// with one deliberate difference: **no metric row**. It reports no minutes, no
/// transfers and no stops, because it is an offer rather than a computed route
/// (see `Chauffeur`).
///
/// The badge is `Brand.red` where the criteria badges are `.tint`, so the card
/// reads as belonging to the app rather than to the search results.
struct RideWithMeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Chauffeur.badge, systemImage: "car.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Brand.red.opacity(0.12), in: Capsule())

            Text(Chauffeur.cardTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                Text(Chauffeur.plate)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Brand.red, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text("·")
                    .foregroundStyle(.secondary)

                Text(Chauffeur.cardSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        List {
            RideWithMeCard()
        }
    }
}
