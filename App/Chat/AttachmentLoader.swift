import AppKit
import JAgent
import UniformTypeIdentifiers

/// Loads dropped/opened files into chat attachments. Images become vision input;
/// text files become inline context.
enum AttachmentLoader {
    static let maxImageDimension: CGFloat = 1568 // Anthropic's per-image edge cap
    static let maxTextBytes = 200_000

    static func load(url: URL) -> Attachment? {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return loadText(url: url)
        }
        if type.conforms(to: .image) {
            return loadImage(url: url)
        }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) || type == .data {
            return loadText(url: url)
        }
        return loadText(url: url)
    }

    static func loadImage(url: URL) -> Attachment? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        guard let source = encodeImage(image) else { return nil }
        return Attachment(filename: url.lastPathComponent, image: source)
    }

    static func loadImage(_ image: NSImage, filename: String) -> Attachment? {
        guard let source = encodeImage(image) else { return nil }
        return Attachment(filename: filename, image: source)
    }

    private static func loadText(url: URL) -> Attachment? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let clipped = data.prefix(maxTextBytes)
        guard let text = String(data: clipped, encoding: .utf8) else { return nil }
        return Attachment(filename: url.lastPathComponent, text: text)
    }

    private static func encodeImage(_ image: NSImage) -> ImageSource? {
        let scaled = downscale(image, maxDimension: maxImageDimension)
        guard let tiff = scaled.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        return ImageSource(mediaType: "image/jpeg", base64Data: jpeg.base64EncodedString())
    }

    private static func downscale(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: newSize)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1.0)
        result.unlockFocus()
        return result
    }
}
