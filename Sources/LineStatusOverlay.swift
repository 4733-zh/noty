import AppKit

/// Shared behaviour for the small overlay controls that sit on checklist rows:
/// hover/press tracking, hand cursor, click-outside cancellation and a11y.
/// Subclasses only supply geometry and drawing.
class LineStatusOverlayButton: NSView {
    var onOpen: (() -> Void)?

    /// Identifies kind + content: the overlay manager only recycles an
    /// existing control when this is unchanged for the same line.
    var reuseKey: String { "" }

    var isHovering = false { didSet { needsDisplay = true } }
    var isPressing = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved,
                                                 .cursorUpdate, .activeAlways],
                                       owner: self))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Repositioning under a stationary cursor (scrolling, typing above)
        // fires no enter/exit events, so re-derive the hover state directly.
        syncHover()
    }

    override func mouseEntered(with event: NSEvent) { syncHover() }
    override func mouseExited(with event: NSEvent) { syncHover() }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseDown(with event: NSEvent) {
        isPressing = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isPressing = isMousePoint(point, in: bounds)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isPressing, isMousePoint(point, in: bounds) { onOpen?() }
        isPressing = false
    }

    private func syncHover() {
        guard let window else {
            isHovering = false
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        isHovering = isMousePoint(point, in: bounds)
    }

    /// Capsule geometry shared by both controls: full-width pill around the
    /// given text, inset half a point so the 1pt stroke stays inside the frame.
    func capsule(insetBy inset: CGFloat = 0.5) -> NSBezierPath {
        NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                     xRadius: bounds.height / 2, yRadius: bounds.height / 2)
    }

    func drawLabel(_ label: String, font: NSFont, color: NSColor, centeredIn bounds: NSRect) {
        let size = (label as NSString).size(withAttributes: [.font: font])
        (label as NSString).draw(at: NSPoint(x: bounds.origin.x + (bounds.width - size.width) / 2,
                                             y: bounds.origin.y + (bounds.height - size.height) / 2),
                                 withAttributes: [.font: font, .foregroundColor: color])
    }
}

/// A small inline control for checklist rows that have not been given a status
/// yet. Drawn by hand so it reads as a quiet "add" chip — a dashed capsule that
/// warms to the accent colour on hover — rather than a default bezel button.
final class LineStatusQuickButton: LineStatusOverlayButton {
    private let title = L10n.text("status.add_short")

    /// Fits the localized label, so the chip hugs "+ Status" and "＋状态" alike.
    static let preferredSize: NSSize = {
        let font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        let width = (L10n.text("status.add_short") as NSString)
            .size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(width) + 12, height: 16)
    }()

    /// Used when a line runs too close to the right edge to fit the whole
    /// label — a bare plus never covers the text it belongs to.
    static let compactSize = NSSize(width: 16, height: 16)

    var isCompact = false { didSet { if oldValue != isCompact { needsDisplay = true } } }

    override var reuseKey: String { isCompact ? "chip+" : "chip-full" }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = L10n.text("status.choose")
        setAccessibilityLabel(L10n.text("status.choose"))
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = capsule(insetBy: 0.5)
        let accent = NSColor.controlAccentColor
        let tint: NSColor
        if isPressing {
            accent.withAlphaComponent(0.16).setFill()
            capsule.fill()
            tint = accent
        } else if isHovering {
            accent.withAlphaComponent(0.08).setFill()
            capsule.fill()
            tint = accent
        } else {
            // Idle stays almost invisible: it is a placeholder, not a control
            // competing with the note's own text and status badges.
            tint = .secondaryLabelColor
        }

        // Dashed while idle reads as "add here"; solid on hover confirms it.
        capsule.lineWidth = 1
        if isHovering || isPressing {
            accent.withAlphaComponent(0.5).setStroke()
        } else {
            tint.withAlphaComponent(0.22).setStroke()
            capsule.setLineDash([2, 2], count: 2, phase: 0)
        }
        capsule.stroke()

        let compact = isCompact
        let font = compact ? NSFont.systemFont(ofSize: 11, weight: .medium)
                           : NSFont.systemFont(ofSize: 9.5, weight: .medium)
        let label: NSString = compact ? "+" : title as NSString
        let size = label.size(withAttributes: [.font: font])
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                               y: (bounds.height - size.height) / 2),
                   withAttributes: [.font: font,
                                    .foregroundColor: tint.withAlphaComponent(isHovering || isPressing ? 1 : 0.75)])
    }
}

/// The visible counterpart of an assigned status, mirroring the shape and
/// colours of `NoteStatusBadge` so the editor, deck and library read alike.
/// It floats over the reserved inline text and opens the same status menu.
final class LineStatusBadgeButton: LineStatusOverlayButton {
    private let label: String
    private let color: NSColor
    private let identity: String

    init(label: String, color: NSColor, identity: String, frame frameRect: NSRect) {
        self.label = label
        self.color = color
        self.identity = identity
        super.init(frame: frameRect)
        toolTip = L10n.text("status.choose")
        setAccessibilityLabel(L10n.format("status.accessibility", label))
    }

    required init?(coder: NSCoder) { nil }

    override var reuseKey: String { "badge|\(identity)" }

    static func size(for label: String) -> NSSize {
        let font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let width = (label as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(width) + 12, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = capsule(insetBy: 0.5)
        let fillAlpha: CGFloat = isPressing ? 0.45 : (isHovering ? 0.36 : 0.26)
        let strokeAlpha: CGFloat = isPressing ? 0.95 : (isHovering ? 0.8 : 0.55)

        color.withAlphaComponent(fillAlpha).setFill()
        capsule.fill()
        capsule.lineWidth = 1
        color.withAlphaComponent(strokeAlpha).setStroke()
        capsule.stroke()

        drawLabel(label,
                  font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
                  color: .labelColor.withAlphaComponent(0.88),
                  centeredIn: bounds)
    }
}

/// Derived controls, one per checklist row: an "add" chip for unlabelled rows
/// and a coloured badge for labelled ones. They never alter note text
/// themselves: choosing a status delegates back to `EditorBridge`.
final class LineStatusOverlayManager: NSObject {
    private weak var textView: TaskTextView?
    private var buttons: [Int: LineStatusOverlayButton] = [:]
    private var observers: [NSObjectProtocol] = []

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func attach(to textView: TaskTextView, scrollView: NSScrollView) {
        self.textView = textView
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification,
                                            object: clip, queue: .main) { [weak self] _ in
            self?.reposition()
        })
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification,
                                            object: clip, queue: .main) { [weak self] _ in
            self?.refresh()
        })
    }

    func refresh() { reposition() }

    private func reposition() {
        guard let tv = textView, let storage = tv.textStorage,
              let layout = tv.layoutManager, let container = tv.textContainer else {
            removeAll(); return
        }
        layout.ensureLayout(for: container)
        let text = storage.string as NSString
        var wanted: [Int: LineStatusOverlayButton] = [:]
        let all = NSRange(location: 0, length: text.length)
        text.enumerateSubstrings(in: all, options: .byLines) { [weak self] line, range, _, _ in
            guard let self, let line, Tasks.isTask(line), range.length > 0 else { return }
            guard container.size.width > 0 else { return }
            if let match = LineStatus.match(in: line) {
                if let badge = self.badgeButton(for: match, line: line, lineRange: range,
                                                layout: layout, container: container, tv: tv) {
                    wanted[range.location] = badge
                }
            } else if let chip = self.chipButton(lineLocation: range.location, lineRange: range,
                                                 layout: layout, container: container, tv: tv) {
                wanted[range.location] = chip
            }
        }

        for (location, button) in buttons where wanted[location] == nil {
            button.removeFromSuperview()
            buttons.removeValue(forKey: location)
        }
        for (location, button) in wanted {
            // Reuse only when the control is still the same kind with the same
            // content — assigning a status turns a chip into a badge, and a
            // renamed or recoloured status must not keep its stale drawing.
            if let existing = buttons[location], existing.reuseKey == button.reuseKey {
                existing.frame = button.frame
            } else {
                buttons[location]?.removeFromSuperview()
                tv.addSubview(button)
                buttons[location] = button
            }
        }
    }

    /// Positions the add chip after a line's last character, degrading to a
    /// bare plus when the line runs close to the right edge — and hiding
    /// entirely rather than covering the text it belongs to.
    private func chipButton(lineLocation: Int, lineRange: NSRange,
                            layout: NSLayoutManager, container: NSTextContainer,
                            tv: TaskTextView) -> LineStatusOverlayButton? {
        let last = NSRange(location: NSMaxRange(lineRange) - 1, length: 1)
        let glyphs = layout.glyphRange(forCharacterRange: last, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        // The used rect is where the text actually stops, so the chip sits
        // after the last character instead of the container edge.
        let used = layout.lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphs) - 1,
                                               effectiveRange: nil)
        let chip = LineStatusQuickButton.preferredSize
        let room = container.size.width - used.maxX
        let compact = room < chip.width + 4
        let size = compact ? LineStatusQuickButton.compactSize : chip
        guard room >= size.width + 2 else { return nil }
        let lineRect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        var rect = NSRect(origin: NSPoint(x: tv.textContainerOrigin.x + used.maxX + 4,
                                          y: 0),
                          size: size)
        // Centre the chip against the line's own height instead of a fixed
        // offset, so it stays optically aligned at any editor font size.
        rect.origin.y = lineRect.origin.y + tv.textContainerOrigin.y
            + max(1, (lineRect.height - size.height) / 2)
        rect.origin.x = min(rect.origin.x,
                            max(tv.textContainerOrigin.x,
                                tv.bounds.maxX - rect.width - 2))
        let button = LineStatusQuickButton(frame: rect)
        button.isCompact = compact
        button.onOpen = { [weak tv, weak button] in
            guard let tv, let button else { return }
            tv.showLineStatusMenu(forLineAt: lineLocation,
                                  at: NSPoint(x: 2, y: button.bounds.height), in: button)
        }
        return button
    }

    /// Floats a coloured badge over the reserved inline status text, centred
    /// within the space its characters already occupy.
    private func badgeButton(for match: LineStatus.Match, line: String,
                             lineRange: NSRange, layout: NSLayoutManager,
                             container: NSTextContainer,
                             tv: TaskTextView) -> LineStatusBadgeButton? {
        guard let display = match.displayRange else { return nil }
        // match ranges are local to the line; layout wants storage coordinates.
        let chars = NSRange(location: lineRange.location + display.location,
                            length: display.length)
        let glyphs = layout.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let ns = line as NSString
        let label = ns.substring(with: display)
            .trimmingCharacters(in: CharacterSet(charactersIn: "〔〕 \u{3000}"))
        guard !label.isEmpty else { return nil }
        let status = Settings.noteStatuses.first { $0.id == match.id }
        let color = NSColor(status?.color ?? .gray)
        let identity = "\(match.id)|\(label)|\(status?.colorHex ?? "gray")"

        let reserved = layout.boundingRect(forGlyphRange: glyphs, in: container)
        let size = LineStatusBadgeButton.size(for: label)
        var rect = NSRect(origin: .zero, size: size)
        rect.origin.x = reserved.origin.x + tv.textContainerOrigin.x
            + (reserved.width - size.width) / 2
        rect.origin.y = reserved.origin.y + tv.textContainerOrigin.y
            + (reserved.height - size.height) / 2
        let button = LineStatusBadgeButton(label: label, color: color, identity: identity,
                                           frame: rect)
        button.onOpen = { [weak tv, weak button] in
            guard let tv, let button else { return }
            tv.showLineStatusMenu(forLineAt: lineRange.location,
                                  at: NSPoint(x: 2, y: button.bounds.height), in: button)
        }
        return button
    }

    private func removeAll() {
        buttons.values.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
    }
}
