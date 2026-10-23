import Foundation
import Yams

/// User settings, stored as YAML in ~/.config/chatty/config.yaml.
struct Settings: Codable, Equatable {
    struct Fonts: Codable, Equatable {
        var family: String?  // nil uses the system monospaced font (SF Mono)
        var size: Double = 13

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            family = try c.decodeIfPresent(String.self, forKey: .family)
            size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 13
        }
    }

    var fonts = Fonts()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fonts = try c.decodeIfPresent(Fonts.self, forKey: .fonts) ?? Fonts()
    }

    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/chatty/config.yaml")

    /// Reads the config file; a missing or unreadable file gives the defaults.
    static func load() -> Settings {
        guard let yaml = try? String(contentsOf: fileURL, encoding: .utf8) else { return Settings() }
        do {
            return try YAMLDecoder().decode(Settings.self, from: yaml)
        } catch {
            FileHandle.standardError.write(Data("config.yaml: \(error)\n".utf8))
            return Settings()
        }
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try YAMLEncoder().encode(self).write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }
}
