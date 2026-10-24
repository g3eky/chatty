import AppKit
import SwiftUI

/// Settings window with General, Appearance and Fonts toolbar tabs, each a SwiftUI grouped form.
/// Every change is passed to `onChange`, which applies and saves it.
final class SettingsWindowController: NSWindowController {
    init(settings: Settings, onChange: @escaping (Settings) -> Void) {
        let model = SettingsModel(settings: settings, onChange: onChange)
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)

        tabs.addTabViewItem(Self.tab("General", symbol: "gearshape", height: 300, GeneralSettings(model: model)))
        tabs.addTabViewItem(Self.tab("Appearance", symbol: "paintpalette", height: 480,
                                     AppearanceSettings(model: model)))
        tabs.addTabViewItem(Self.tab("Fonts", symbol: "textformat", height: 370, FontSettings(model: model)))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Tabs share one width so controls don't shift sideways; each is as tall as its content.
    private static func tab(_ title: String, symbol: String, height: CGFloat, _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view.formStyle(.grouped).frame(width: 480, height: height))
        controller.sizingOptions = .preferredContentSize
        controller.safeAreaRegions = []  // the toolbar is outside the content view; don't inset for it twice
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

@Observable
private final class SettingsModel {
    var settings: Settings {
        didSet { if settings != oldValue { onChange(settings) } }
    }
    @ObservationIgnored private let onChange: (Settings) -> Void

    init(settings: Settings, onChange: @escaping (Settings) -> Void) {
        self.settings = settings
        self.onChange = onChange
    }
}

// MARK: - Tabs

private struct GeneralSettings: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                TextField("Shell", text: $model.settings.general.shell.orEmpty,
                          prompt: Text(ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"))
                LabeledContent("Working directory") {
                    HStack {
                        TextField("Working directory", text: $model.settings.general.workingDirectory.orEmpty,
                                  prompt: Text("~"))
                            .labelsHidden()
                        Button("Choose…", action: chooseDirectory)
                    }
                }
            } header: {
                Text("Session")
            } footer: {
                Text("Used for new sessions, so changes take effect the next time Chatty starts. "
                    + "Leave empty to use your login shell and home folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("History") {
                LabeledContent("Scrollback") {
                    HStack {
                        TextField("Scrollback", value: $model.settings.general.scrollback, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("lines")
                    }
                }
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.general.workingDirectory = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}

private struct AppearanceSettings: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section("Colors") {
                ColorPicker("Text", selection: $model.settings.appearance.foreground.color, supportsOpacity: false)
                ColorPicker("Background", selection: $model.settings.appearance.background.color,
                            supportsOpacity: false)
                ColorPicker("Cursor", selection: $model.settings.appearance.cursor.color, supportsOpacity: false)
                ColorPicker("Selection", selection: $model.settings.appearance.selection.color,
                            supportsOpacity: false)
            }
            Section("Cursor") {
                Picker("Style", selection: $model.settings.appearance.cursorStyle) {
                    ForEach(Settings.CursorStyle.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }
                .pickerStyle(.segmented)
            }
            Section("Window") {
                LabeledContent("Padding") {
                    ValueStepper(text: "\(Int(model.settings.appearance.padding)) pt",
                                 value: $model.settings.appearance.padding, range: 0...40)
                }
                LabeledContent("Background opacity") {
                    HStack {
                        Slider(value: $model.settings.appearance.opacity.rounded(to: 0.01), in: 0.3...1)
                        Text("\(Int((model.settings.appearance.opacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    .frame(width: 220)
                }
            }
        }
    }
}

private struct FontSettings: View {
    @Bindable var model: SettingsModel
    private let families: [String]

    init(model: SettingsModel) {
        self.model = model
        var families = Set(NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask)?
            .compactMap { NSFont(name: $0, size: 12)?.familyName } ?? [])
        if let family = model.settings.fonts.family { families.insert(family) }
        self.families = families.sorted()
    }

    var body: some View {
        let fonts = model.settings.fonts
        let font = GlyphAtlas.font(fonts, bold: false)
        Form {
            Section("Font") {
                Picker("Family", selection: $model.settings.fonts.family) {
                    Text("System Monospaced (SF Mono)").tag(String?.none)
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                LabeledContent("Size") {
                    ValueStepper(text: "\(Int(fonts.size)) pt", value: $model.settings.fonts.size, range: 6...72)
                }
                LabeledContent("Line height") {
                    ValueStepper(text: String(format: "%.1f", fonts.lineHeight),
                                 value: $model.settings.fonts.lineHeight.rounded(to: 0.1), range: 1...2, step: 0.1)
                }
            }
            Section("Preview") {
                Text("~/Projects/chatty \u{e0a0} main\n$ ls\nsrc  docs  README.md  0O 1lI {}")
                    .font(Font(font))
                    .lineSpacing((font.ascender - font.descender + font.leading) * (fonts.lineHeight - 1))
                    .foregroundStyle(model.settings.appearance.foreground.color.wrappedValue)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(model.settings.appearance.background.color.wrappedValue,
                                in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

/// The value text followed by stepper arrows, right-aligned in a form row.
private struct ValueStepper: View {
    let text: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        HStack(spacing: 6) {
            Text(text).monospacedDigit()
            Stepper(text, value: $value, in: range, step: step).labelsHidden()
        }
    }
}

// MARK: - Bindings

private extension Binding where Value == String? {
    /// Empty text means "unset".
    var orEmpty: Binding<String> {
        Binding<String>(get: { wrappedValue ?? "" }, set: { wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

private extension Binding where Value == Double {
    /// Rounds written values so the config file doesn't collect float noise like 1.2000000000000002.
    func rounded(to step: Double) -> Binding<Double> {
        Binding(get: { wrappedValue }, set: { wrappedValue = ($0 / step).rounded() * step })
    }
}

private extension String {
    /// A "#RRGGBB" string viewed as a SwiftUI color.
    var color: Binding<Color> {
        let c = SIMD4<Float>(hex: self)
        return .constant(Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z)))
    }
}

private extension Binding where Value == String {
    /// Edits a "#RRGGBB" string through a color picker.
    var color: Binding<Color> {
        Binding<Color>(get: { wrappedValue.color.wrappedValue }, set: { newColor in
            let c = NSColor(newColor).usingColorSpace(.sRGB) ?? .black
            wrappedValue = SIMD4<Float>(Float(c.redComponent), Float(c.greenComponent),
                                        Float(c.blueComponent), 1).hex
        })
    }
}
