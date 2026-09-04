#if canImport(AppKit)
import AppKit
/// `NSFont` on macOS, `UIFont` on iOS. The same `.font` attribute, two names.
typealias PlatformFont = NSFont
#else
import UIKit
typealias PlatformFont = UIFont
#endif
import Foundation

/// RTF conversion. The only place in SummonKit that touches AppKit, and only for
/// `NSAttributedString`'s document readers — no views, so tests stay headless.
public enum RTF {
    public static func plainText(from data: Data) -> String {
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return "" }
        return attributed.string
    }

    public static func attributed(from data: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    public static func data(from attributed: NSAttributedString) -> Data? {
        try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// True when the RTF carries formatting worth preserving, as opposed to being
    /// plain text that merely arrived in a rich container.
    public static func hasMeaningfulFormatting(_ data: Data) -> Bool {
        guard let attributed = attributed(from: data), attributed.length > 0 else { return false }
        var interesting = false
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, _, stop in
            for key in attrs.keys where [.font, .foregroundColor, .underlineStyle, .link].contains(key) {
                if key == .font, let font = attrs[.font] as? PlatformFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    if traits.contains(.bold) || traits.contains(.italic) { interesting = true; stop.pointee = true }
                } else if key != .font {
                    interesting = true
                    stop.pointee = true
                }
            }
        }
        return interesting
    }
}
