import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct AIIconImporter {
    let sourceURL: URL
    let resourcesURL: URL
    let iconsetURL: URL

    func run() throws {
        guard let sourceImage = NSImage(contentsOf: sourceURL) else {
            throw NSError(domain: "AIIconImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read source image"])
        }

        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: iconsetURL)
        try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

        let master = try renderIcon(from: sourceImage, size: 1024)
        try writePNG(master, to: resourcesURL.appendingPathComponent("AppIcon.png"))

        var iconImages: [(IconSpec, Data)] = []
        for spec in IconSpec.all {
            let image = try resize(master, size: spec.pixelSize)
            let pngURL = iconsetURL.appendingPathComponent(spec.fileName)
            try writePNG(image, to: pngURL)
            iconImages.append((spec, try Data(contentsOf: pngURL)))
        }

        try writeICNS(iconImages, to: resourcesURL.appendingPathComponent("AppIcon.icns"))
    }

    private func renderIcon(from sourceImage: NSImage, size: Int) throws -> CGImage {
        let scale = CGFloat(size) / 1024
        let outputSize = NSSize(width: size, height: size)
        let image = NSImage(size: outputSize)

        image.lockFocus()
        let context = NSGraphicsContext.current?.cgContext
        context?.setShouldAntialias(true)
        context?.setAllowsAntialiasing(true)

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outputSize).fill()

        let iconRect = NSRect(x: 84 * scale, y: 96 * scale, width: 856 * scale, height: 856 * scale)
        let cornerRadius = iconRect.width * 0.285
        let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowBlurRadius = 28 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
        shadow.set()
        NSColor.black.withAlphaComponent(0.62).setFill()
        iconPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        iconPath.addClip()
        let cropSize = min(sourceImage.size.width, sourceImage.size.height) * 0.76
        let cropX = (sourceImage.size.width - cropSize) * 0.5
        let cropY = (sourceImage.size.height - cropSize) * 0.5
        sourceImage.draw(
            in: iconRect,
            from: NSRect(x: cropX, y: cropY, width: cropSize, height: cropSize),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let innerInset = 2 * scale
        let innerRect = iconRect.insetBy(dx: innerInset, dy: innerInset)
        let innerPath = NSBezierPath(
            roundedRect: innerRect,
            xRadius: max(0, cornerRadius - innerInset),
            yRadius: max(0, cornerRadius - innerInset)
        )
        NSColor.white.withAlphaComponent(0.42).setStroke()
        innerPath.lineWidth = max(1, 1.6 * scale)
        innerPath.stroke()

        NSColor.black.withAlphaComponent(0.10).setStroke()
        iconPath.lineWidth = max(1, 1 * scale)
        iconPath.stroke()

        image.unlockFocus()

        guard let output = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "AIIconImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot render icon"])
        }
        return output
    }

    private func resize(_ image: CGImage, size: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "AIIconImporter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create resize context"])
        }
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let output = context.makeImage() else {
            throw NSError(domain: "AIIconImporter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot resize icon"])
        }
        return output
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "AIIconImporter", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot create PNG destination"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "AIIconImporter", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot write PNG"])
        }
    }

    private func writeICNS(_ images: [(IconSpec, Data)], to url: URL) throws {
        var body = Data()
        for (spec, pngData) in images {
            guard let type = spec.icnsType else { continue }
            body.appendFourCC(type)
            body.appendUInt32(UInt32(pngData.count + 8))
            body.append(pngData)
        }

        var output = Data()
        output.appendFourCC("icns")
        output.appendUInt32(UInt32(body.count + 8))
        output.append(body)
        try output.write(to: url)
    }
}

struct IconSpec {
    let baseSize: Int
    let scale: Int

    var pixelSize: Int { baseSize * scale }
    var fileName: String {
        scale == 1 ? "icon_\(baseSize)x\(baseSize).png" : "icon_\(baseSize)x\(baseSize)@\(scale)x.png"
    }

    var icnsType: String? {
        switch (baseSize, scale) {
        case (16, 1): return "icp4"
        case (16, 2): return "ic11"
        case (32, 1): return "icp5"
        case (32, 2): return "ic12"
        case (128, 1): return "ic07"
        case (128, 2): return "ic13"
        case (256, 1): return "ic08"
        case (256, 2): return "ic14"
        case (512, 1): return "ic09"
        case (512, 2): return "ic10"
        default: return nil
        }
    }

    static let all = [
        IconSpec(baseSize: 16, scale: 1),
        IconSpec(baseSize: 16, scale: 2),
        IconSpec(baseSize: 32, scale: 1),
        IconSpec(baseSize: 32, scale: 2),
        IconSpec(baseSize: 128, scale: 1),
        IconSpec(baseSize: 128, scale: 2),
        IconSpec(baseSize: 256, scale: 1),
        IconSpec(baseSize: 256, scale: 2),
        IconSpec(baseSize: 512, scale: 1),
        IconSpec(baseSize: 512, scale: 2)
    ]
}

extension Data {
    mutating func appendFourCC(_ value: String) {
        precondition(value.utf8.count == 4)
        append(contentsOf: value.utf8)
    }

    mutating func appendUInt32(_ value: UInt32) {
        var bigEndianValue = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndianValue) { append(contentsOf: $0) }
    }
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: import_ai_icon.swift <source.png> <resources-dir> <iconset-dir>\n", stderr)
    exit(2)
}

do {
    try AIIconImporter(
        sourceURL: URL(fileURLWithPath: CommandLine.arguments[1]),
        resourcesURL: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true),
        iconsetURL: URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    ).run()
} catch {
    fputs("Icon import failed: \(error)\n", stderr)
    exit(1)
}
