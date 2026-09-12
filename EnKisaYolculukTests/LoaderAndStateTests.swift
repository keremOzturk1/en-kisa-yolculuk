import Foundation
import Testing
@testable import EnKisaYolculuk

@Suite("NetworkLoader")
struct NetworkLoaderTests {

    private func temporaryFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test("A valid file loads and is validated")
    func loadsFromURL() throws {
        let url = try temporaryFile(Fixture.linear)
        defer { try? FileManager.default.removeItem(at: url) }
        let network = try NetworkLoader.load(contentsOf: url)
        #expect(network.stations.count == 3)
        #expect(network.lines.count == 1)
    }

    @Test("A missing bundle resource is reported, not crashed on")
    func missingResource() {
        #expect(throws: NetworkLoader.LoaderError.self) {
            _ = try NetworkLoader.load(resourceName: "definitely-not-here")
        }
    }

    @Test("Malformed JSON is reported as a decoding failure")
    func malformedJSON() throws {
        let url = try temporaryFile("{ this is not json")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try NetworkLoader.load(contentsOf: url)
            Issue.record("expected a loader error")
        } catch let error as NetworkLoader.LoaderError {
            guard case .decodingFailed = error else {
                Issue.record("wrong error: \(error)")
                return
            }
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("JSON that is well-formed but invalid still fails, via validate()")
    func validationRunsOnLoad() throws {
        let url = try temporaryFile("""
        {"version":1,"transferPenaltyMinutes":10,
         "stations":[{"id":"a","name":"A"}],
         "lines":[{"id":"L","name":"L"}],
         "segments":[{"line":"L","from":"a","to":"missing","minutes":1}]}
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: MetroNetwork.ValidationError.self) {
            _ = try NetworkLoader.load(contentsOf: url)
        }
    }

    @Test("The shipped network.json loads from the app bundle")
    func bundledNetworkLoads() throws {
        let network = try NetworkLoader.load()
        #expect(network.stations.count > 0)
        #expect(network.lines.count > 0)
        #expect(network.segments.count > 0)
    }
}

@MainActor
@Suite("AppState")
struct AppStateTests {

    private func readyState() throws -> AppState {
        AppState(network: try Fixture.network(Fixture.divergingCriteria))
    }

    @Test("A ready state exposes its service and network")
    func readyExposesNetwork() throws {
        let state = try readyState()
        #expect(state.service != nil)
        #expect(state.network?.stations.count == 3)
    }

    @Test("Searching is disabled until two different stations are chosen")
    func canSearchRules() throws {
        let state = try readyState()
        #expect(!state.canSearch)
        state.originID = "p"
        #expect(!state.canSearch, "destination still missing")
        state.destinationID = "p"
        #expect(!state.canSearch, "same station is not a journey")
        state.destinationID = "r"
        #expect(state.canSearch)
    }

    @Test("A successful search publishes routes and clears any error")
    func searchSucceeds() throws {
        let state = try readyState()
        state.originID = "p"
        state.destinationID = "r"
        state.search()
        #expect(!state.routes.isEmpty)
        #expect(state.routingError == nil)
    }

    @Test("A failed search clears routes and publishes a message")
    func searchFails() throws {
        let state = AppState(network: try Fixture.network(Fixture.disconnected))
        state.originID = "i1"
        state.destinationID = "j2"
        state.search()
        #expect(state.routes.isEmpty)
        #expect(state.routingError?.isEmpty == false)
    }

    @Test("A later successful search clears the previous error")
    func errorIsClearedOnRetry() throws {
        let state = try readyState()
        state.originID = "p"
        state.destinationID = "ghost"
        state.search()
        #expect(state.routingError != nil)

        state.destinationID = "r"
        state.search()
        #expect(state.routingError == nil)
        #expect(!state.routes.isEmpty)
    }

    @Test("Searching with no selection does nothing rather than crashing")
    func searchWithoutSelection() throws {
        let state = try readyState()
        state.search()
        #expect(state.routes.isEmpty)
        #expect(state.routingError == nil)
    }

    @Test("Swapping exchanges the endpoints, including when one is empty")
    func swapEndpoints() throws {
        let state = try readyState()
        state.originID = "p"
        state.destinationID = "r"
        state.swapEndpoints()
        #expect(state.originID == "r")
        #expect(state.destinationID == "p")

        state.destinationID = nil
        state.swapEndpoints()
        #expect(state.originID == nil)
        #expect(state.destinationID == "r")
    }

    @Test("Station lookup tolerates nil and unknown ids")
    func stationLookup() throws {
        let state = try readyState()
        #expect(state.station(nil) == nil)
        #expect(state.station("ghost") == nil)
        #expect(state.station("p")?.name == "P")
    }

    @Test("Loading the bundled data reaches the ready state")
    func bundledLoadSucceeds() {
        let state = AppState()
        guard case .ready = state.loadState else {
            Issue.record("expected .ready, got \(state.loadState)")
            return
        }
        #expect(state.network != nil)
    }
}
