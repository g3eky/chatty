import AppKit

/// Settings dialog. Every change is passed to `onChange`, which applies and saves it.
final class SettingsWindowController: NSWindowController {
    private static let systemFontTitle = "System Monospaced (SF Mono)"

    private var settings: Settings
    private let onChange: (Settings) -> Void
    private let familyPopup = NSPopUpButton()
    private let sizeField = NSTextField()
    private let sizeStepper = NSStepper()

    init(settings: Settings, onChange: @escaping (Settings) -> Void) {
        self.settings = settings
        self.onChange = onChange
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let manager = NSFontManager.shared
        var families = Set(manager.availableFontNames(with: .fixedPitchFontMask)?
            .compactMap { NSFont(name: $0, size: 12)?.familyName } ?? [])
        if let family = settings.fonts.family { families.insert(family) }
        familyPopup.addItem(withTitle: Self.systemFontTitle)
        familyPopup.addItems(withTitles: families.sorted())
        familyPopup.selectItem(withTitle: settings.fonts.family ?? Self.systemFontTitle)
        familyPopup.target = self
        familyPopup.action = #selector(changed(_:))

        let formatter = NumberFormatter()
        formatter.minimum = 6
        formatter.maximum = 72
        sizeField.formatter = formatter
        sizeField.doubleValue = settings.fonts.size
        sizeField.target = self
        sizeField.action = #selector(changed(_:))
        sizeField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        sizeStepper.minValue = 6
        sizeStepper.maxValue = 72
        sizeStepper.increment = 1
        sizeStepper.doubleValue = settings.fonts.size
        sizeStepper.target = self
        sizeStepper.action = #selector(changed(_:))

        let heading = NSTextField(labelWithString: "Fonts")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Family:"), familyPopup],
            [NSTextField(labelWithString: "Size:"), NSStackView(views: [sizeField, sizeStepper])],
        ])
        grid.column(at: 0).xPlacement = .trailing
        let stack = NSStackView(views: [heading, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func changed(_ sender: NSControl) {
        let size = sender === sizeStepper ? sizeStepper.doubleValue : sizeField.doubleValue
        sizeField.doubleValue = size
        sizeStepper.doubleValue = size
        let title = familyPopup.titleOfSelectedItem
        settings.fonts.family = title == Self.systemFontTitle ? nil : title
        settings.fonts.size = size
        onChange(settings)
    }
}
