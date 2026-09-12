import SwiftUI

/// Entry screen: pick origin + destination, then search.
/// STUB — layout and visual design are placeholders; the wiring is real.
struct StationPickerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingResults = false

    var body: some View {
        NavigationStack {
            Group {
                switch appState.loadState {
                case .loading:
                    ProgressView("Ağ yükleniyor…")
                case .failed(let message):
                    DataErrorView(message: message) { appState.load() }
                case .ready:
                    form
                }
            }
            .navigationTitle("En Kısa Yolculuk")
            .navigationDestination(isPresented: $showingResults) {
                RouteListView()
            }
        }
    }

    private var form: some View {
        Form {
            Section("Güzergah") {
                StationRow(title: "Kalkış", systemImage: "circle",
                           selection: $appState.originID)
                    .accessibilityIdentifier("originPicker")

                StationRow(title: "Varış", systemImage: "mappin.and.ellipse",
                           selection: $appState.destinationID)
                    .accessibilityIdentifier("destinationPicker")

                Button {
                    appState.swapEndpoints()
                } label: {
                    Label("Yönü Değiştir", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("swapEndpoints")
                .disabled(appState.originID == nil && appState.destinationID == nil)
            }

            if let error = appState.routingError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("routingError")
                }
            }

            Section {
                Button {
                    appState.search()
                    if appState.routingError == nil { showingResults = true }
                } label: {
                    Label("Rotaları Bul", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("findRoutes")
                .disabled(!appState.canSearch)
            }

            if let network = appState.network {
                Section {
                    Text("\(network.stations.count) istasyon · \(network.lines.count) hat · aktarma cezası \(formatMinutes(network.transferPenaltyMinutes)) dk")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dataSummary")
                } header: {
                    Text("Veri")
                }
            }
        }
    }
}

/// One origin/destination row. Pushes the searchable station list.
private struct StationRow: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let systemImage: String
    @Binding var selection: StationID?

    private var station: Station? { appState.station(selection) }

    var body: some View {
        NavigationLink {
            StationSelectionView(
                title: title,
                entries: appState.network?.pickerEntries ?? [],
                selection: $selection
            )
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(station.map { appState.network?.displayName($0) ?? $0.name } ?? "Seçiniz")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Shown when network.json is missing or malformed — the most likely failure
/// once the real data file is dropped in.
struct DataErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Ağ verisi yüklenemedi", systemImage: "exclamationmark.icloud")
        } description: {
            Text(message)
        } actions: {
            Button("Tekrar Dene", action: retry)
        }
    }
}

#Preview {
    StationPickerView().environmentObject(AppState())
}
