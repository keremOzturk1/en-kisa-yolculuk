import Foundation

/// Loads `network.json` from the app bundle.
///
/// Dropping in the real Istanbul data is a **file replacement only**: keep the
/// filename and the schema, and nothing here or downstream changes.
enum NetworkLoader {

    enum LoaderError: LocalizedError {
        case fileNotFound(String)
        case decodingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let name):
                return "'\(name).json' is not in the app bundle."
            case .decodingFailed(let error):
                return "network.json could not be decoded: \(error)"
            }
        }
    }

    static let defaultResourceName = "network"

    static func load(
        resourceName: String = defaultResourceName,
        in bundle: Bundle = .main
    ) throws -> MetroNetwork {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoaderError.fileNotFound(resourceName)
        }
        return try load(contentsOf: url)
    }

    /// Split out so tests / the CLI harness can load a file by path.
    static func load(contentsOf url: URL) throws -> MetroNetwork {
        let data = try Data(contentsOf: url)
        let network: MetroNetwork
        do {
            network = try JSONDecoder().decode(MetroNetwork.self, from: data)
        } catch {
            throw LoaderError.decodingFailed(error)
        }
        try network.validate()
        return network
    }
}
