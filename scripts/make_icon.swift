import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct IconMaker {
    let sourceURL: URL
    let resourcesURL: URL
    let iconsetURL: URL

    func run() throws {
        let sourceImage = try loadSourceImage()
        let visibleRect = visibleBounds(in: sourceImage)
        let master = try renderIcon(source: sourceImage, crop: visibleRect, size: 1024)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try writePNG(master, to: resourcesURL.appendingPathComponent("AppIcon.png"))

        try? FileManager.default.removeItem(at: iconsetURL)
        try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

        var iconImages: [(IconSpec, Data)] = []
        for spec in IconSpec.all {
            let image = try renderIcon(source: sourceImage, crop: visibleRect, size: spec.pixelSize)
            let pngURL = iconsetURL.appendingPathComponent(spec.fileName)
            try writePNG(image, to: pngURL)
            iconImages.append((spec, try Data(contentsOf: pngURL)))
        }

        try writeICNS(iconImages, to: resourcesURL.appendingPathComponent("AppIcon.icns"))
    }

    private func loadSourceImage() throws -> CGImage {
        guard let image = NSImage(contentsOf: sourceURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "IconMaker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read source image"])
        }
        return cgImage
    }

    private func visibleBounds(in image: CGImage) -> CGRect {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * 4 + 3]
                if alpha > 8 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX <= maxX, minY <= maxY else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func renderIcon(source: CGImage, crop: CGRect, size: Int) throws -> CGImage {
        guard let cropped = source.cropping(to: crop) else {
            throw NSError(domain: "IconMaker", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot crop source image"])
        }

        let outputSize = NSSize(width: size, height: size)
        let scale = CGFloat(size) / 1024
        let image = NSImage(size: outputSize)
        let sourceImage = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outputSize).fill()

        let iconRect = NSRect(
            x: 97 * scale,
            y: 109 * scale,
            width: 830 * scale,
            height: 830 * scale
        )
        let cornerRadius = iconRect.width * 0.265
        let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        let contactShadow = NSShadow()
        contactShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        contactShadow.shadowBlurRadius = 16 * scale
        contactShadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
        contactShadow.set()
        NSColor.black.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: iconRect.insetBy(dx: 18 * scale, dy: 8 * scale), xRadius: cornerRadius * 0.92, yRadius: cornerRadius * 0.92).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.36)
        shadow.shadowBlurRadius = 34 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -18 * scale)
        shadow.set()
        NSColor.black.withAlphaComponent(0.50).setFill()
        iconPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        iconPath.addClip()
        let background = NSGradient(colors: [
            NSColor(calibratedRed: 1.00, green: 0.56, blue: 0.47, alpha: 1.00),
            NSColor(calibratedRed: 0.95, green: 0.34, blue: 0.34, alpha: 1.00)
        ])
        background?.draw(in: iconRect, angle: -90)

        sourceImage.draw(
            in: iconRect,
            from: NSRect(x: 0, y: 0, width: cropped.width, height: cropped.height),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        iconPath.addClip()
        let bottomShade = NSGradient(colors: [
            NSColor.black.withAlphaComponent(0.00),
            NSColor.black.withAlphaComponent(0.10)
        ])
        bottomShade?.draw(
            in: NSRect(x: iconRect.minX, y: iconRect.minY, width: iconRect.width, height: iconRect.height * 0.42),
            angle: -90
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.16).setStroke()
        iconPath.lineWidth = max(1, 2 * scale)
        iconPath.stroke()

        image.unlockFocus()

        guard let output = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "IconMaker", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot render icon"])
        }
        return output
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "IconMaker", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot create PNG destination"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "IconMaker", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot write PNG"])
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
    fputs("Usage: make_icon.swift <source.png> <resources-dir> <iconset-dir>\n", stderr)
    exit(2)
}

do {
    try IconMaker(
        sourceURL: URL(fileURLWithPath: CommandLine.arguments[1]),
        resourcesURL: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true),
        iconsetURL: URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    ).run()
} catch {
    fputs("Icon generation failed: \(error)\n", stderr)
    exit(1)
}
