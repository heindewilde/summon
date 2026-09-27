import Foundation

/// What actually goes onto the pasteboard when an item is used.
public struct InsertPayload: Sendable {
    public var plainText: String?
    public var rtf: Data?
    public var fileURL: URL?
    public var imageData: Data?

    public init(
        plainText: String? = nil,
        rtf: Data? = nil,
        fileURL: URL? = nil,
        imageData: Data? = nil
    ) {
        self.plainText = plainText
        self.rtf = rtf
        self.fileURL = fileURL
        self.imageData = imageData
    }

    public var isEmpty: Bool {
        plainText == nil && rtf == nil && fileURL == nil && imageData == nil
    }

    /// A short description for the confirmation toast.
    public var descriptionForToast: String {
        if fileURL != nil { return "file" }
        if imageData != nil { return "image" }
        if rtf != nil { return "formatted text" }
        return "text"
    }
}
