import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct AppIconNormalizer {
    let sourceURL: URL
    let resourcesURL: URL
    let iconsetURL: URL
    let canvasSize = 1024

    func run() throws {
        let source = try loadImage(sourceURL)
        let crop = visibleBounds(in: source)
        let master = try renderNormalizedIcon(source: source, crop: crop, size: canvasSize)

        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try writePNG(master, to: resourcesURL.appendingPathComponent("AppIcon.png"))

        try? FileManager.default.removeItem(at: iconsetURL)
        try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

        var iconImages: [(IconSpec, Data)] = []
        for spec in IconSpec.all {
            let image = try resize(master, size: spec.pixelSize)
            let pngURL = iconsetURL.appendingPathComponent(spec.fileName)
            try writePNG(image, to: pngURL)
            iconImages.append((spec, try Data(contentsOf: pngURL)))
        }
        try writeICNS(iconImages, to: resourcesURL.appendingPathComponent("AppIcon.icns"))
    }

    private func loadImage(_ url: URL) throws -> CGImage {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "AppIconNormalizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read source image"])
        }
        return cgImage
    }

    private func visibleBounds(in image: CGImage) -> CGRect {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        for y in 0..<height {
            for x in 0..<width where pixels[y * bytesPerRow + x * 4 + 3] > 8 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard minX <= maxX, minY <= maxY else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func renderNormalizedIcon(source: CGImage, crop: CGRect, size: Int) throws -> CGImage {
        guard let cropped = source.cropping(to: crop) else {
            throw NSError(domain: "AppIconNormalizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot crop source image"])
        }

        let outputSize = NSSize(width: size, height: size)
        let image = NSImage(size: outputSize)
        let sourceImage = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outputSize).fill()

        let iconRect = NSRect(
            x: CGFloat(size) * 0.0859375,
            y: CGFloat(size) * 0.09765625,
            width: CGFloat(size) * 0.828125,
            height: CGFloat(size) * 0.828125
        )
        let cornerRadius = iconRect.width * 0.24
        let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowBlurRadius = CGFloat(size) * 0.02734375
        shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(size) * 0.01171875)
        shadow.set()
        NSColor.black.withAlphaComponent(0.65).setFill()
        iconPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        iconPath.addClip()
        sourceImage.draw(
            in: iconRect,
            from: NSRect(x: 0, y: 0, width: cropped.width, height: cropped.height),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.035).setStroke()
        iconPath.lineWidth = max(1, CGFloat(size) * 0.001953125)
        iconPath.stroke()

        image.unlockFocus()

        guard let output = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "AppIconNormalizer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot render icon"])
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
            throw NSError(domain: "AppIconNormalizer", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot create resize context"])
        }
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let output = context.makeImage() else {
            throw NSError(domain: "AppIconNormalizer", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot resize icon"])
        }
        return output
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "AppIconNormalizer", code: 7, userInfo: [NSLocalizedDescriptionKey: "Cannot create PNG destination"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "AppIconNormalizer", code: 8, userInfo: [NSLocalizedDescriptionKey: "Cannot write PNG"])
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
    fputs("Usage: normalize_app_icon.swift <source-icon.png> <resources-dir> <iconset-dir>\n", stderr)
    exit(2)
}

do {
    try AppIconNormalizer(
        sourceURL: URL(fileURLWithPath: CommandLine.arguments[1]),
        resourcesURL: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true),
        iconsetURL: URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    ).run()
} catch {
    fputs("Icon normalization failed: \(error)\n", stderr)
    exit(1)
}
