import AppKit

/// Settings window with General, Appearance and Fonts toolbar tabs.
/// Every change is passed to `onChange`, which applies and saves it.
final class SettingsWindowController: NSWindowController {
    private static let systemFontTitle = "System Monospaced (SF Mono)"
    private static let previewText = "~/Projects/chatty \u{e0a0} main\n$ ls\nsrc  docs  README.md  0O 1lI {}"

    private var settings: Settings
    private let onChange: (Settings) -> Void

    private let shellField = NSTextField()
    private let directoryField = NSTextField()
    private let scrollbackField = NSTextField()

    private let foregroundWell = NSColorWell()
    private let backgroundWell = NSColorWell()
    private let cursorWell = NSColorWell()
    private let selectionWell = NSColorWell()
    private let cursorStyleControl = NSSegmentedControl(labels: ["Block", "Underline", "Bar"],
                                                        trackingMode: .selectOne, target: nil, action: nil)
    private let paddingField = NSTextField(), paddingStepper = NSStepper()
    private let opacitySlider = NSSlider(value: 1, minValue: 0.3, maxValue: 1, target: nil, action: nil)
    private let opacityLabel = NSTextField(labelWithString: "")

    private let familyPopup = NSPopUpButton()
    private let sizeField = NSTextField(), sizeStepper = NSStepper()
    private let lineHeightField = NSTextField(), lineHeightStepper = NSStepper()
    private let previewBox = NSView()
    private let preview = NSTextField(labelWithString: "")

    private var steppers: [(NSTextField, NSStepper)] {
        [(paddingField, paddingStepper), (sizeField, sizeStepper), (lineHeightField, lineHeightStepper)]
    }

    init(settings: Settings, onChange: @escaping (Settings) -> Void) {
        self.settings = settings
        self.onChange = onChange
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)

        tabs.addTabViewItem(tab("General", symbol: "gearshape", generalPane()))
        tabs.addTabViewItem(tab("Appearance", symbol: "paintpalette", appearancePane()))
        tabs.addTabViewItem(tab("Fonts", symbol: "textformat", fontsPane()))
        showValues()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Panes

    private func generalPane() -> NSView {
        shellField.placeholderString = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        directoryField.placeholderString = "~"
        for field in [shellField, directoryField] {
            setUp(field)
            field.widthAnchor.constraint(equalToConstant: 240).isActive = true
        }
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseDirectory))
        setUp(scrollbackField, formatter: numberFormatter(min: 0, max: 1_000_000, digits: 0), width: 80)
        return form([
            ("Shell", shellField),
            ("Working directory", NSStackView(views: [directoryField, choose])),
            ("Scrollback", NSStackView(views: [scrollbackField, NSTextField(labelWithString: "lines")])),
        ], note: "Shell and working directory are used for new sessions, so they take effect the next time "
            + "Chatty starts. Leave them empty to use your login shell and home folder.")
    }

    private func appearancePane() -> NSView {
        for well in [foregroundWell, backgroundWell, cursorWell, selectionWell] {
            well.target = self
            well.action = #selector(changed(_:))
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }
        cursorStyleControl.target = self
        cursorStyleControl.action = #selector(changed(_:))
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(changed(_:))
        opacitySlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return form([
            ("Text", foregroundWell),
            ("Background", backgroundWell),
            ("Cursor", cursorWell),
            ("Selection", selectionWell),
            ("Cursor style", cursorStyleControl),
            ("Padding", NSStackView(views: [stepper(paddingField, paddingStepper, min: 0, max: 40, step: 1, digits: 0),
                                           NSTextField(labelWithString: "pt")])),
            ("Background opacity", NSStackView(views: [opacitySlider, opacityLabel])),
        ])
    }

    private func fontsPane() -> NSView {
        var families = Set(NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask)?
            .compactMap { NSFont(name: $0, size: 12)?.familyName } ?? [])
        if let family = settings.fonts.family { families.insert(family) }
        familyPopup.addItem(withTitle: Self.systemFontTitle)
        familyPopup.addItems(withTitles: families.sorted())
        familyPopup.target = self
        familyPopup.action = #selector(changed(_:))

        previewBox.wantsLayer = true
        previewBox.layer?.cornerRadius = 6
        preview.translatesAutoresizingMaskIntoConstraints = false
        previewBox.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: previewBox.topAnchor, constant: 10),
            preview.bottomAnchor.constraint(equalTo: previewBox.bottomAnchor, constant: -10),
            preview.leadingAnchor.constraint(equalTo: previewBox.leadingAnchor, constant: 12),
            preview.trailingAnchor.constraint(lessThanOrEqualTo: previewBox.trailingAnchor, constant: -12),
            previewBox.widthAnchor.constraint(equalToConstant: 300),
        ])
        return form([
            ("Family", familyPopup),
            ("Size", NSStackView(views: [stepper(sizeField, sizeStepper, min: 6, max: 72, step: 1, digits: 0),
                                        NSTextField(labelWithString: "pt")])),
            ("Line height", stepper(lineHeightField, lineHeightStepper, min: 1, max: 2, step: 0.1, digits: 1)),
            ("Preview", previewBox),
        ])
    }

    // MARK: - Building blocks

    private func tab(_ title: String, symbol: String, _ view: NSView) -> NSTabViewItem {
        let controller = NSViewController()
        controller.view = view
        controller.title = title
        controller.preferredContentSize = view.fittingSize
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    /// Right-aligned labels next to their controls, with an optional footnote below.
    private func form(_ rows: [(String, NSView)], note: String? = nil) -> NSView {
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0 + ":"), $0.1] })
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 12
        grid.columnSpacing = 8
        var views: [NSView] = [grid]
        if let note {
            let label = NSTextField(wrappingLabelWithString: note)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = 436
            views.append(label)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 32, bottom: 24, right: 32)
        stack.widthAnchor.constraint(equalToConstant: 500).isActive = true
        return stack
    }

    private func setUp(_ field: NSTextField, formatter: NumberFormatter? = nil, width: CGFloat? = nil) {
        field.formatter = formatter
        field.target = self
        field.action = #selector(changed(_:))
        field.cell?.sendsActionOnEndEditing = true
        if let width { field.widthAnchor.constraint(equalToConstant: width).isActive = true }
    }

    private func stepper(_ field: NSTextField, _ stepper: NSStepper,
                         min: Double, max: Double, step: Double, digits: Int) -> NSView {
        setUp(field, formatter: numberFormatter(min: min, max: max, digits: digits), width: 48)
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = step
        stepper.target = self
        stepper.action = #selector(changed(_:))
        return NSStackView(views: [field, stepper])
    }

    private func numberFormatter(min: Double, max: Double, digits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = min as NSNumber
        formatter.maximum = max as NSNumber
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter
    }

    // MARK: - Values

    private func showValues() {
        shellField.stringValue = settings.general.shell ?? ""
        directoryField.stringValue = settings.general.workingDirectory ?? ""
        scrollbackField.integerValue = settings.general.scrollback

        let a = settings.appearance
        foregroundWell.color = Self.color(a.foreground)
        backgroundWell.color = Self.color(a.background)
        cursorWell.color = Self.color(a.cursor)
        selectionWell.color = Self.color(a.selection)
        cursorStyleControl.selectedSegment = Settings.CursorStyle.allCases.firstIndex(of: a.cursorStyle) ?? 0
        paddingField.doubleValue = a.padding
        opacitySlider.doubleValue = a.opacity

        familyPopup.selectItem(withTitle: settings.fonts.family ?? Self.systemFontTitle)
        sizeField.doubleValue = settings.fonts.size
        lineHeightField.doubleValue = settings.fonts.lineHeight
        for (field, stepper) in steppers { stepper.doubleValue = field.doubleValue }
        updateLabels()
    }

    @objc private func changed(_ sender: Any?) {
        for (field, stepper) in steppers {
            if sender as AnyObject === stepper { field.doubleValue = stepper.doubleValue }
            stepper.doubleValue = field.doubleValue
        }
        let old = settings
        settings.general.shell = shellField.stringValue.isEmpty ? nil : shellField.stringValue
        settings.general.workingDirectory = directoryField.stringValue.isEmpty ? nil : directoryField.stringValue
        settings.general.scrollback = scrollbackField.integerValue

        settings.appearance.foreground = Self.hex(foregroundWell.color)
        settings.appearance.background = Self.hex(backgroundWell.color)
        settings.appearance.cursor = Self.hex(cursorWell.color)
        settings.appearance.selection = Self.hex(selectionWell.color)
        settings.appearance.cursorStyle = Settings.CursorStyle.allCases[max(0, cursorStyleControl.selectedSegment)]
        settings.appearance.padding = paddingField.doubleValue
        settings.appearance.opacity = (opacitySlider.doubleValue * 100).rounded() / 100

        let family = familyPopup.titleOfSelectedItem
        settings.fonts.family = family == Self.systemFontTitle ? nil : family
        settings.fonts.size = sizeField.doubleValue
        settings.fonts.lineHeight = (lineHeightField.doubleValue * 10).rounded() / 10

        updateLabels()
        if settings != old { onChange(settings) }
    }

    @objc private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.beginSheetModal(for: window!) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            directoryField.stringValue = (url.path as NSString).abbreviatingWithTildeInPath
            changed(directoryField)
        }
    }

    private func updateLabels() {
        opacityLabel.stringValue = "\(Int((settings.appearance.opacity * 100).rounded()))%"

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = settings.fonts.lineHeight
        preview.attributedStringValue = NSAttributedString(string: Self.previewText, attributes: [
            .font: GlyphAtlas.font(settings.fonts, bold: false),
            .foregroundColor: Self.color(settings.appearance.foreground),
            .paragraphStyle: paragraph,
        ])
        previewBox.layer?.backgroundColor = Self.color(settings.appearance.background).cgColor
    }

    private static func color(_ hex: String) -> NSColor {
        let c = SIMD4<Float>(hex: hex)
        return NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    private static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return SIMD4<Float>(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1).hex
    }
}
