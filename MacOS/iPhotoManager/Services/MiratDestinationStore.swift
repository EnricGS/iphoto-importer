import Foundation

/// Persistència a disc de la llista de destins Mirat configurats.
/// Fitxer: ~/Library/Application Support/iPhotoManager/mirat-destinations.json
final class MiratDestinationStore {

    private let fileURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder = JSONDecoder()

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = base.appendingPathComponent("iPhotoManager", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        self.fileURL = folder.appendingPathComponent("mirat-destinations.json")
    }

    /// Carrega la llista (buida si el fitxer no existeix o està malmès).
    func load() -> [MiratDestination] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([MiratDestination].self, from: data)
        } catch {
            return []
        }
    }

    /// Desa la llista sencera (reemplaça el fitxer).
    func save(_ destinations: [MiratDestination]) {
        do {
            let data = try encoder.encode(destinations)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // No és crític: es perdrà la configuració però l'app continuarà.
        }
    }
}
