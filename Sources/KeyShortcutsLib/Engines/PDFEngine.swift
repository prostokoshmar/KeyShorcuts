import Foundation
import PDFKit
import AppKit
import ImageIO
import UniformTypeIdentifiers

final class PDFEngine: ConversionEngine {
    static let shared = PDFEngine()
    let engineName = "Built-in PDF (PDFKit/Quartz)"

    private init() {}

    func availability(for pair: ConversionPair) -> EngineAvailability { .available }

    func convert(item: ConversionItem, to outputURL: URL, progress: @escaping (Double) -> Void) throws {
        let src = item.sourceURL

        switch (item.detectedSourceFormat, item.targetFormat) {
        case (_, .pdf):
            try imageToPDF(src: src, dst: outputURL, progress: progress)
        case (.pdf, _):
            try pdfToImage(src: src, dst: outputURL, targetFormat: item.targetFormat, progress: progress)
        default:
            throw ConversionError.unsupported("\(item.detectedSourceFormat) → PDF not handled here")
        }
    }

    // MARK: - Image → PDF

    private func imageToPDF(src: URL, dst: URL, progress: @escaping (Double) -> Void) throws {
        guard let image = NSImage(contentsOf: src) else {
            throw ConversionError.loadFailed("Cannot open image \(src.lastPathComponent)")
        }
        progress(0.3)
        let doc = PDFDocument()
        let page = PDFPage(image: image)!
        doc.insert(page, at: 0)
        progress(0.8)
        guard doc.write(to: dst) else {
            throw ConversionError.writeFailed("PDFDocument.write failed")
        }
        progress(1.0)
    }

    // MARK: - PDF → Image (first page)

    private func pdfToImage(src: URL, dst: URL, targetFormat: ConversionFormat, progress: @escaping (Double) -> Void) throws {
        guard let doc = PDFDocument(url: src), let page = doc.page(at: 0) else {
            throw ConversionError.loadFailed("Cannot open PDF \(src.lastPathComponent)")
        }
        progress(0.3)

        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0  // 144 dpi
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let image = page.thumbnail(of: size, for: .mediaBox)
        progress(0.7)

        let utType: UTType
        switch targetFormat {
        case .png:  utType = .png
        case .tiff: utType = .tiff
        default:    utType = .jpeg
        }

        guard let data = imageData(from: image, type: utType) else {
            throw ConversionError.writeFailed("Cannot encode PDF page to \(targetFormat.displayName)")
        }
        try data.write(to: dst, options: .atomic)
        progress(1.0)
    }

    private func imageData(from image: NSImage, type: UTType) -> Data? {
        guard let cgImg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let props: [String: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality as String: 0.85] : [:]
        CGImageDestinationAddImage(dest, cgImg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
