import Foundation
import SwiftUI

/// App-wide state: holds the loaded network, the RouteService and the current
/// search. Kept deliberately thin — the routing logic lives in `RouteService`.
@MainActor
final class AppState: ObservableObject {

    enum LoadState {
        case loading
        case ready(RouteService)
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published var originID: StationID?
    @Published var destinationID: StationID?
    @Published private(set) var routes: [Route] = []
    @Published private(set) var routingError: String?

    init() {
        load()
    }

    /// Test / preview seam.
    init(network: MetroNetwork) {
        loadState = .ready(RouteService(network: network))
    }

    func load() {
        do {
            loadState = .ready(RouteService(network: try NetworkLoader.load()))
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    var service: RouteService? {
        if case .ready(let service) = loadState { return service }
        return nil
    }

    var network: MetroNetwork? { service?.network }

    var canSearch: Bool {
        guard let originID, let destinationID else { return false }
        return originID != destinationID
    }

    func station(_ id: StationID?) -> Station? {
        guard let id else { return nil }
        return network?.station(id)
    }

    func search() {
        guard let service, let originID, let destinationID else { return }
        routingError = nil
        do {
            routes = try service.routes(from: originID, to: destinationID)
        } catch {
            routes = []
            routingError = error.localizedDescription
        }
    }

    func swapEndpoints() {
        let previousOrigin = originID
        originID = destinationID
        destinationID = previousOrigin
    }
}
