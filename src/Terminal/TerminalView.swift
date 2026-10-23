import AppKit
import SwiftTerm

/// Metal-backed view that owns the SwiftTerm `Terminal` and the shell process, and handles input.
final class TerminalView: NSView, TerminalDelegate, LocalProcessDelegate, NSTextInputClient {
    private let renderer: Renderer
    private let metalLayer = CAMetalLayer()
    private var terminal: Terminal!
    private var process: LocalProcess!
    private var displayLink: CADisplayLink?
    private var needsRender = true
    private var cursorVisible = true
    private var scrollTop: Int?  // scroll-invariant row at the top while scrolled back; nil follows output
    private var scrollRemainder: CGFloat = 0
    private var selection: (start: Position, end: Position)?  // scroll-invariant rows, inclusive
    private var markedText = ""

    init(cols: Int, rows: Int, fonts: Settings.Fonts) {
        renderer = Renderer(fonts: fonts, scale: NSScreen.main?.backingScaleFactor ?? 2)
        super.init(frame: .zero)
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.contentsScale = renderer.scale
        wantsLayer = true
        terminal = Terminal(delegate: self, options: TerminalOptions(cols: cols, rows: rows))
        process = LocalProcess(delegate: self, dispatchQueue: .main)
        setFrameSize(NSSize(width: CGFloat(cols) * cellSize.width, height: CGFloat(rows) * cellSize.height))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var cellSize: NSSize {
        NSSize(width: CGFloat(renderer.atlas.cellWidth) / renderer.scale,
               height: CGFloat(renderer.atlas.cellHeight) / renderer.scale)
    }

    func setFonts(_ fonts: Settings.Fonts) {
        renderer.setFonts(fonts)
        window?.contentResizeIncrements = cellSize
        updateGridSize()
    }

    func startShell() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        process.startProcess(executable: shell, args: [], environment: env.map { "\($0)=\($1)" },
                             execName: "-" + (shell as NSString).lastPathComponent,
                             currentDirectory: NSHomeDirectory())
    }

    // MARK: - View lifecycle and rendering

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func makeBackingLayer() -> CALayer { metalLayer }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        displayLink = displayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(setNeedsRender),
                                                   name: name, object: window)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let window else { return }
        metalLayer.contentsScale = window.backingScaleFactor
        renderer.setScale(window.backingScaleFactor)
        updateGridSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateGridSize()
    }

    private func updateGridSize() {
        guard terminal != nil else { return }
        let scale = renderer.scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let cols = max(2, Int(bounds.width * scale) / renderer.atlas.cellWidth)
        let rows = max(1, Int(bounds.height * scale) / renderer.atlas.cellHeight)
        if cols != terminal.cols || rows != terminal.rows {
            terminal.resize(cols: cols, rows: rows)
            var size = getWindowSize()
            _ = process.updateWindowSize(&size)
            scrollTop = nil
            selection = nil
        }
        needsRender = true
    }

    @objc private func setNeedsRender() { needsRender = true }

    @objc private func tick() {
        guard needsRender else { return }
        needsRender = false
        renderer.draw(in: metalLayer, terminal: terminal, top: top, showCursor: cursorVisible && scrollTop == nil,
                      focused: window?.isKeyWindow == true, selection: orderedSelection, markedText: markedText)
    }

    private var liveTop: Int { terminal.buffer.totalLinesTrimmed + terminal.buffer.yDisp }
    private var top: Int { max(scrollTop ?? liveTop, terminal.buffer.totalLinesTrimmed) }

    private var orderedSelection: (start: Position, end: Position)? {
        guard let (a, b) = selection else { return nil }
        return (a.row, a.col) <= (b.row, b.col) ? (a, b) : (b, a)
    }

    // MARK: - LocalProcessDelegate

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        window?.close()
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        terminal.feed(buffer: slice)
        needsRender = true
    }

    func getWindowSize() -> winsize {
        winsize(ws_row: UInt16(terminal.rows), ws_col: UInt16(terminal.cols),
                ws_xpixel: UInt16(terminal.cols * renderer.atlas.cellWidth),
                ws_ypixel: UInt16(terminal.rows * renderer.atlas.cellHeight))
    }

    // MARK: - TerminalDelegate

    func send(source: Terminal, data: ArraySlice<UInt8>) {
        process.send(data: data)
    }

    func setTerminalTitle(source: Terminal, title: String) {
        window?.title = title.isEmpty ? "Chatty" : title
    }

    func showCursor(source: Terminal) { cursorVisible = true; needsRender = true }
    func hideCursor(source: Terminal) { cursorVisible = false; needsRender = true }
    func bell(source: Terminal) { NSSound.beep() }

    func bufferActivated(source: Terminal) {
        scrollTop = nil
        selection = nil
    }

    // MARK: - Keyboard

    private func send(_ bytes: [UInt8]) {
        scrollTop = nil
        needsRender = true
        process.send(data: bytes[...])
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags
        if mods.contains(.command) { super.keyDown(with: event); return }
        if !hasMarkedText() {
            if mods.contains(.control), !mods.contains(.option), let byte = controlByte(event) {
                send([byte])
                return
            }
            if let bytes = specialKeyBytes(event) {
                send(bytes)
                return
            }
        }
        interpretKeyEvents([event])
    }

    private func controlByte(_ event: NSEvent) -> UInt8? {
        guard let c = event.charactersIgnoringModifiers?.lowercased().unicodeScalars.first, c.isASCII else {
            return nil
        }
        switch c {
        case "a"..."z": return UInt8(c.value) - 0x60
        case "@", " ", "2": return 0
        case "[", "3": return 0x1b
        case "\\", "4": return 0x1c
        case "]", "5": return 0x1d
        case "^", "6": return 0x1e
        case "_", "-", "/", "7": return 0x1f
        case "8": return 0x7f
        default: return nil
        }
    }

    private func specialKeyBytes(_ event: NSEvent) -> [UInt8]? {
        let mods = event.modifierFlags
        let modifier = 1 + (mods.contains(.shift) ? 1 : 0) + (mods.contains(.option) ? 2 : 0)
            + (mods.contains(.control) ? 4 : 0)
        func cursorKey(_ letter: String) -> [UInt8] {
            if modifier > 1 { return Array("\u{1b}[1;\(modifier)\(letter)".utf8) }
            return Array(((terminal.applicationCursor ? "\u{1b}O" : "\u{1b}[") + letter).utf8)
        }
        if event.keyCode == 53 { return [0x1b] }  // Escape
        switch event.specialKey {
        case .upArrow?: return cursorKey("A")
        case .downArrow?: return cursorKey("B")
        case .rightArrow?: return cursorKey("C")
        case .leftArrow?: return cursorKey("D")
        case .home?: return cursorKey("H")
        case .end?: return cursorKey("F")
        case .pageUp?: return EscapeSequences.cmdPageUp
        case .pageDown?: return EscapeSequences.cmdPageDown
        case .deleteForward?: return EscapeSequences.cmdDelKey
        case .delete?: return [0x7f]
        case .tab?: return [0x09]
        case .backTab?: return EscapeSequences.cmdBackTab
        case .carriageReturn?, .enter?: return [0x0d]
        default: break
        }
        let fKeys: [NSEvent.SpecialKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
        if let key = event.specialKey, let index = fKeys.firstIndex(of: key) {
            return EscapeSequences.cmdF[index]
        }
        return nil
    }

    // MARK: - NSTextInputClient (IME)

    func insertText(_ string: Any, replacementRange: NSRange) {
        markedText = ""
        let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        send(Array(text.utf8))
    }

    override func doCommand(by selector: Selector) {}

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        needsRender = true
    }

    func unmarkText() {
        markedText = ""
        needsRender = true
    }

    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    func markedRange() -> NSRange {
        markedText.isEmpty ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: markedText.utf16.count)
    }

    func hasMarkedText() -> Bool { !markedText.isEmpty }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let cell = NSRect(x: CGFloat(terminal.buffer.x) * cellSize.width,
                          y: CGFloat(terminal.buffer.y) * cellSize.height,
                          width: cellSize.width, height: cellSize.height)
        return window?.convertToScreen(convert(cell, to: nil)) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    // MARK: - Mouse, selection, scrolling

    private func cell(for event: NSEvent) -> (col: Int, row: Int) {
        let p = convert(event.locationInWindow, from: nil)
        let col = Int(p.x / cellSize.width), row = Int(p.y / cellSize.height)
        return (min(max(col, 0), terminal.cols - 1), min(max(row, 0), terminal.rows - 1))
    }

    private func reportsMouse(_ event: NSEvent) -> Bool {
        terminal.mouseMode != .off && !event.modifierFlags.contains(.shift)
    }

    private func buttonFlags(_ button: Int, release: Bool, _ event: NSEvent) -> Int {
        let mods = event.modifierFlags
        return terminal.encodeButton(button: button, release: release, shift: false,
                                     meta: mods.contains(.option), control: mods.contains(.control))
    }

    override func mouseDown(with event: NSEvent) {
        let (col, row) = cell(for: event)
        if reportsMouse(event) {
            terminal.sendEvent(buttonFlags: buttonFlags(0, release: false, event), x: col, y: row)
            return
        }
        let p = Position(col: col, row: top + row)
        selection = (p, p)
        needsRender = true
    }

    override func mouseDragged(with event: NSEvent) {
        let (col, row) = cell(for: event)
        if reportsMouse(event) {
            if terminal.mouseMode == .buttonEventTracking || terminal.mouseMode == .anyEvent {
                terminal.sendMotion(buttonFlags: buttonFlags(0, release: false, event), x: col, y: row,
                                    pixelX: col, pixelY: row)
            }
            return
        }
        selection?.end = Position(col: col, row: top + row)
        needsRender = true
    }

    override func mouseUp(with event: NSEvent) {
        let (col, row) = cell(for: event)
        if reportsMouse(event) {
            if terminal.mouseMode != .x10 {
                terminal.sendEvent(buttonFlags: buttonFlags(0, release: true, event), x: col, y: row)
            }
            return
        }
        if let (a, b) = selection, a == b { selection = nil }
        needsRender = true
    }

    override func scrollWheel(with event: NSEvent) {
        scrollRemainder += event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / cellSize.height : event.scrollingDeltaY
        let lines = Int(scrollRemainder)
        scrollRemainder -= CGFloat(lines)
        guard lines != 0 else { return }
        if terminal.mouseMode != .off {
            let (col, row) = cell(for: event)
            let flags = buttonFlags(lines > 0 ? 4 : 5, release: false, event)
            for _ in 0..<abs(lines) { terminal.sendEvent(buttonFlags: flags, x: col, y: row) }
            return
        }
        let live = liveTop
        let target = min(max(top - lines, terminal.buffer.totalLinesTrimmed), live)
        scrollTop = target == live ? nil : target
        needsRender = true
    }

    // MARK: - Copy and paste

    @objc func copy(_ sender: Any?) {
        guard let (start, end) = orderedSelection else { return }
        var lines: [String] = []
        for row in start.row...end.row {
            guard let line = terminal.getScrollInvariantLine(row: row) else { continue }
            let from = row == start.row ? start.col : 0
            let to = min(row == end.row ? end.col : terminal.cols - 1, line.count - 1)
            var text = ""
            for col in from...max(from, to) where line[col].width > 0 {
                let t = line[col].getText()
                text += t == "\0" ? " " : t
            }
            while text.hasSuffix(" ") { text.removeLast() }
            lines.append(text)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        var bytes = Array(text.replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r").utf8)
        if terminal.bracketedPasteMode {
            bytes = EscapeSequences.bracketedPasteStart + bytes + EscapeSequences.bracketedPasteEnd
        }
        send(bytes)
    }
}
