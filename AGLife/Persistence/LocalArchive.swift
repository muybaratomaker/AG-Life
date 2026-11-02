import Foundation

struct LocalArchive {
    let url: URL

    static func applicationArchive() throws -> LocalArchive {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AGLife", isDirectory: true)
        return LocalArchive(url: directory.appendingPathComponent("life.json"))
    }

    func load() throws -> LifeData {
        guard FileManager.default.fileExists(atPath: url.path) else { return LifeData() }
        var data = try JSONDecoder().decode(LifeData.self, from: Data(contentsOf: url))
        guard (1...2).contains(data.version) else {
            throw NSError(domain: "AGLife", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Versione dell’archivio non supportata."])
        }
        // Reading never rewrites the original. The next successful atomic save persists v2.
        data.version = 2
        return data
    }

    func save(_ data: LifeData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: url, options: .atomic)
    }
}
