import Foundation

enum FixtureLoader {
    static func data(named name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    enum FixtureError: Error {
        case missing(String)
    }
}
