import Foundation
import Yams

/// User settings, stored as YAML in ~/.config/chatty/config.yaml. Missing keys use the defaults below.
struct Settings: Codable, Equatable {
    struct General: Codable, Equatable {
        var shell: String?             // nil uses $SHELL
        var workingDirectory: String?  // nil uses the home folder; "~" is expanded
        var scrollback = 10000
    }

    enum CursorStyle: String, Codable, CaseIterable {
        case block, underline, bar
    }

    struct Appearance: Codable, Equatable {
        var foreground = "#DBDBDB"
        var background = "#1C1C1F"
        var cursor = "#DBDBDB"
        var selection = "#425C8C"
        var padding: Double = 4
        var opacity: Double = 1
        var cursorStyle = CursorStyle.block
    }

    struct Fonts: Codable, Equatable {
        var family: String?  // nil uses the system monospaced font (SF Mono)
        var size: Double = 13
        var lineHeight: Double = 1
    }

    var general = General()
    var appearance = Appearance()
    var fonts = Fonts()

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
        // Yams writes floats in scientific notation (13 → 1.3e+1); write them plainly instead.
        let yaml = try YAMLEncoder().encode(self).replacing(#/-?\d+(\.\d+)?e[+-]\d+/#) { match in
            Double(match.output.0).map { String($0) } ?? String(match.output.0)
        }
        try yaml.write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }
}

// Decoders live in extensions so the structs keep their default `init()`.
extension Settings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        general = try c.value(.general, default: General())
        appearance = try c.value(.appearance, default: Appearance())
        fonts = try c.value(.fonts, default: Fonts())
    }
}

extension Settings.General {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self), d = Self()
        shell = try c.decodeIfPresent(String.self, forKey: .shell)
        workingDirectory = try c.decodeIfPresent(String.self, forKey: .workingDirectory)
        scrollback = try c.value(.scrollback, default: d.scrollback)
    }
}

extension Settings.Appearance {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self), d = Self()
        foreground = try c.value(.foreground, default: d.foreground)
        background = try c.value(.background, default: d.background)
        cursor = try c.value(.cursor, default: d.cursor)
        selection = try c.value(.selection, default: d.selection)
        padding = try c.value(.padding, default: d.padding)
        opacity = try c.value(.opacity, default: d.opacity)
        cursorStyle = try c.value(.cursorStyle, default: d.cursorStyle)
    }
}

extension Settings.Fonts {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self), d = Self()
        family = try c.decodeIfPresent(String.self, forKey: .family)
        size = try c.value(.size, default: d.size)
        lineHeight = try c.value(.lineHeight, default: d.lineHeight)
    }
}

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default value: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? value
    }
}

/// "#RRGGBB" ↔ RGBA components in 0...1.
extension SIMD4 where Scalar == Float {
    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(Float(v >> 16 & 0xff) / 255, Float(v >> 8 & 0xff) / 255, Float(v & 0xff) / 255, 1)
    }

    var hex: String {
        let c = (self * Float(255)).rounded(.toNearestOrAwayFromZero)
        return String(format: "#%02X%02X%02X", Int(c.x), Int(c.y), Int(c.z))
    }
}
