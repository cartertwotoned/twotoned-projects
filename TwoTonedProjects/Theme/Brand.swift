import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Brand colors come from the asset catalog (Xcode generates `Color.brandBlue` etc.):
// - brandBlue `#1FB0E6` — main accent (selection, current task)
// - brandBlueText — readable blue for small text (`#5EC6EF` in dark mode)
// - brandPurple `#8B4FC9` — anything Claude-related
// - brandPurpleText — readable purple for small text (`#B28BE6` in dark mode)

extension Color {
    init?(hex: String?) {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

enum ProjectColors {
    static let swatches = ["#1FB0E6", "#8B4FC9", "#1D9E75", "#E8833A", "#E24B4A", "#D4537E", "#C9A227", "#7A7A80"]
    static let fallback = Color.brandBlue
}

enum ImageTools {
    /// Downsamples an image to at most `maxPixel` on its longest side and returns PNG data.
    /// Keeps stored icons small no matter how large the source image is.
    static func thumbnailPNG(from data: Data, maxPixel: Int = 256) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

/// Small cache so icons and screenshots aren't re-decoded on every redraw.
@MainActor
enum ImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()

    static func image(for data: Data, key: String) -> NSImage? {
        let cacheKey = "\(key)-\(data.count)-\(data.hashValue)" as NSString
        if let hit = cache.object(forKey: cacheKey) { return hit }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}
