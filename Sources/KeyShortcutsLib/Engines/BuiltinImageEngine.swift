import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

final class BuiltinImageEngine: ConversionEngine {
    static let shared = BuiltinImageEngine()
    let engineName = "Built-in Image (sips/ImageIO)"

    private init() {}

    func availability(for pair: ConversionPair) -> EngineAvailability {
        // AVIF read/write support: macOS 13 can read AVIF via ImageIO but write support
        // is only guaranteed on macOS 14+. We allow it but the caller should handle failure.
        if pair.target == .avif {
            if #available(macOS 14, *) { return .available }
            return .unsupportedOnThisOS("AVIF write requires macOS 14+")
        }
        return .available
    }

    func convert(item: ConversionItem, to outputURL: URL, progress: @escaping (Double) -> Void) throws {
        let src = item.sourceURL
        progress(0.1)

        // Load source image via ImageIO (handles RAW, PSD, HEIC, etc.)
        guard let src_cgImage = loadImage(at: src) else {
            throw ConversionError.loadFailed("Could not load image: \(src.lastPathComponent)")
        }
        progress(0.5)

        let utType = utTypeForFormat(item.targetFormat)
        guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, utType.identifier as CFString, 1, nil) else {
            throw ConversionError.writeFailed("Cannot create image destination for \(item.targetFormat.displayName)")
        }

        let props = imageProperties(for: item.targetFormat)
        CGImageDestinationAddImage(dest, src_cgImage, props as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.writeFailed("CGImageDestinationFinalize failed for \(item.targetFormat.displayName)")
        }
        progress(1.0)
    }

    // MARK: - Helpers

    private func loadImage(at url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private func utTypeForFormat(_ fmt: ConversionFormat) -> UTType {
        switch fmt {
        case .jpeg:  return .jpeg
        case .png:   return .png
        case .gif:   return .gif
        case .tiff:  return .tiff
        case .bmp:   return .bmp
        case .heic:  return .heic
        case .webp:
            if let t = UTType("public.webp") { return t }
            return .png
        case .avif:
            if let t = UTType("public.avif") { return t }
            return .heic
        case .ico:
            if let t = UTType("com.microsoft.ico") { return t }
            return .png
        case .icns:  return .icns
        default:     return .png
        }
    }

    private func imageProperties(for fmt: ConversionFormat) -> [String: Any] {
        switch fmt {
        case .jpeg:
            return [kCGImageDestinationLossyCompressionQuality as String: 0.85]
        case .heic:
            return [kCGImageDestinationLossyCompressionQuality as String: 0.85]
        default:
            return [:]
        }
    }
}

enum ConversionError: LocalizedError {
    case loadFailed(String)
    case writeFailed(String)
    case unsupported(String)
    case dependencyMissing(String)
    case processError(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let m):       return "Load failed: \(m)"
        case .writeFailed(let m):      return "Write failed: \(m)"
        case .unsupported(let m):      return "Unsupported: \(m)"
        case .dependencyMissing(let m): return "Missing dependency: \(m)"
        case .processError(let m):     return "Process error: \(m)"
        }
    }
}
