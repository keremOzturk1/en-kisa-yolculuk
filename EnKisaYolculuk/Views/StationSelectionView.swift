import SwiftUI

/// Searchable station list, pushed from the picker rows.
///
/// Replaces an inline `Picker`: with 300+ stations a menu is unusable — and in
/// practice refused to open at all — so choosing a station needs a list you can
/// type into.
struct StationSelectionView: View {
    let title: String
    let entries: [MetroNetwork.StationEntry]
    @Binding var selection: StationID?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [MetroNetwork.StationEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        // localizedStandardContains is diacritic- and case-insensitive, so
        // "sisli" finds "Şişli-Mecidiyeköy".
        return entries.filter { $0.label.localizedStandardContains(trimmed) }
    }

    var body: some View {
        List(filtered) { entry in
            Button {
                selection = entry.station.id
                dismiss()
            } label: {
                HStack {
                    Text(entry.label)
                        .foregroundStyle(.primary)
                    Spacer()
                    if entry.station.id == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .accessibilityIdentifier("stationOption")
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "İstasyon ara")
        .navigationTitle(title)
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}
