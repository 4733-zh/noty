import AppKit
import SwiftUI

/// A reusable workflow label. Definitions live in preferences so people can
/// make this fit their own process; a note only stores the stable id.
struct NoteStatus: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var colorHex: String

    init(id: String = UUID().uuidString, name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    var color: Color {
        let hex = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return .gray }
        return Color(.sRGB,
                     red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255,
                     opacity: 1)
    }

    static func hex(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        return String(format: "%02X%02X%02X",
                      Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()),
                      Int((ns.blueComponent * 255).rounded()))
    }
}

/// The same small, readable token used beside a note title everywhere in the
/// app. It deliberately uses the workflow colour, rather than the note colour.
struct NoteStatusBadge: View {
    let status: NoteStatus
    var ink: Color = .primary

    var body: some View {
        Text(status.name)
            .font(.system(size: 9.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(ink.opacity(0.88))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(status.color.opacity(0.28)))
            .overlay(Capsule().strokeBorder(status.color.opacity(0.62), lineWidth: 0.8))
            .accessibilityLabel(L10n.format("status.accessibility", status.name))
    }
}

/// A line's status is plain text with a small, hidden stable-id trailer. The
/// readable label survives exports while the trailer keeps renames and colour
/// changes tied to the same Settings definition.
enum LineStatus {
    private static let token = try! NSRegularExpression(pattern: "<noty-status:([A-Za-z0-9-]+)>")

    struct Match {
        let id: String
        let markerRange: NSRange
        let displayRange: NSRange?
        let presentationRange: NSRange
    }

    static func match(in text: String) -> Match? {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        guard let found = token.firstMatch(in: text, range: all) else { return nil }
        let id = ns.substring(with: found.range(at: 1))
        let marker = found.range
        var display: NSRange?
        if marker.location > 0, ns.character(at: marker.location - 1) == 0x3015 { // 〕
            let before = ns.substring(to: marker.location) as NSString
            let opening = before.range(of: "〔", options: .backwards)
            if opening.location != NSNotFound {
                display = NSRange(location: opening.location,
                                  length: marker.location - opening.location)
            }
        }
        let start: Int
        if let display {
            // Include the visual gap before a tag when replacing or clearing it.
            var p = display.location
            while p > 0, ns.character(at: p - 1) == 0x20 { p -= 1 }
            start = p
        } else {
            start = marker.location
        }
        return Match(id: id, markerRange: marker, displayRange: display,
                     presentationRange: NSRange(location: start,
                                                length: NSMaxRange(marker) - start))
    }

    static func statusID(in line: String) -> String? { match(in: line)?.id }

    static func stripping(from text: String) -> String {
        var output = text
        while let found = match(in: output) {
            output = (output as NSString).replacingCharacters(in: found.presentationRange, with: "")
        }
        return output
    }

    static func replacing(in line: String, with status: NoteStatus?) -> String {
        let ns = line as NSString
        if let match = match(in: line) {
            return ns.replacingCharacters(in: match.presentationRange,
                                          with: status.map(inline) ?? "")
        }
        guard let status else { return line }
        let newline = line.hasSuffix("\n") ? "\n" : ""
        let body = newline.isEmpty ? line : String(line.dropLast())
        return body + inline(status) + newline
    }

    static func removing(_ statusID: String, from body: String) -> String {
        var output = body
        while let match = match(in: output), match.id == statusID {
            let ns = output as NSString
            output = ns.replacingCharacters(in: match.presentationRange, with: "")
        }
        // A document can have more than one labelled line. Work backwards so
        // UTF-16 ranges from the original body never drift between removals.
        let ns = output as NSString
        let all = NSRange(location: 0, length: ns.length)
        let matches = token.matches(in: output, range: all).reversed()
        for marker in matches {
            guard ns.substring(with: marker.range(at: 1)) == statusID else { continue }
            let line = ns.lineRange(for: marker.range)
            let lineText = ns.substring(with: line)
            guard let local = match(in: lineText) else { continue }
            let global = NSRange(location: line.location + local.presentationRange.location,
                                 length: local.presentationRange.length)
            output = (output as NSString).replacingCharacters(in: global, with: "")
        }
        return output
    }

    static func updatingLabel(for status: NoteStatus, in body: String) -> String {
        let source = body as NSString
        let all = NSRange(location: 0, length: source.length)
        let markers = token.matches(in: body, range: all).reversed()
        var output = body
        for marker in markers {
            guard source.substring(with: marker.range(at: 1)) == status.id else { continue }
            let line = source.lineRange(for: marker.range)
            let lineText = source.substring(with: line)
            guard let local = match(in: lineText) else { continue }
            let global = NSRange(location: line.location + local.presentationRange.location,
                                 length: local.presentationRange.length)
            output = (output as NSString).replacingCharacters(in: global, with: inline(status))
        }
        return output
    }

    private static func inline(_ status: NoteStatus) -> String {
        let name = status.name
            .replacingOccurrences(of: "〔", with: "")
            .replacingOccurrences(of: "〕", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.isEmpty ? L10n.text("status.new") : name
        return " 〔\(label)〕<noty-status:\(status.id)>"
    }
}

/// Compact menu shared by the deck, detached note and library. A removed status
/// is intentionally treated as unset, so stale configuration never leaks into
/// the interface.
struct NoteStatusMenu: View {
    let selectedID: String?
    var ink: Color = .primary
    let onSelect: (String?) -> Void

    private var selected: NoteStatus? { Settings.noteStatuses.first { $0.id == selectedID } }

    var body: some View {
        Menu {
            Button {
                onSelect(nil)
            } label: {
                Label(L10n.text("status.none"), systemImage: selected == nil ? "checkmark" : "minus.circle")
            }
            if !Settings.noteStatuses.isEmpty { Divider() }
            ForEach(Settings.noteStatuses) { status in
                Button {
                    onSelect(status.id)
                } label: {
                    Label {
                        Text(status.name)
                    } icon: {
                        Image(systemName: selected?.id == status.id ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            }
        } label: {
            if let selected {
                NoteStatusBadge(status: selected, ink: ink)
            } else {
                Image(systemName: "tag")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.48))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(selected?.name ?? L10n.text("status.choose"))
    }
}
