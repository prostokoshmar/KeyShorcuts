import Foundation

// MARK: - Protocol

protocol ConversionEngine: AnyObject {
    var engineName: String { get }

    func availability(for pair: ConversionPair) -> EngineAvailability

    // Synchronous conversion — called off main thread.
    // Reports progress in [0,1] via the callback; pass nil if indeterminate.
    func convert(
        item: ConversionItem,
        to outputURL: URL,
        progress: @escaping (Double) -> Void
    ) throws
}

// MARK: - Pair

struct ConversionPair: Hashable {
    let source: ConversionFormat
    let target: ConversionFormat
}

// MARK: - Capability matrix entry

struct CapabilityEntry {
    let pair: ConversionPair
    let engine: ConversionEngine
}

// MARK: - Router

final class ConversionRouter {
    static let shared = ConversionRouter()

    // Registered in priority order (first matching engine wins).
    private var entries: [CapabilityEntry] = []

    private init() {
        registerAll()
    }

    private func registerAll() {
        let image    = BuiltinImageEngine.shared
        let pdf      = PDFEngine.shared
        let config   = ConfigEngine.shared
        let archive  = ArchiveEngine.shared
        let email    = EmailEngine.shared
        let ffmpeg   = FFmpegEngine.shared

        // Images (sips / ImageIO — built-in)
        let writableImages: [ConversionFormat] = [.jpeg, .png, .gif, .tiff, .bmp, .heic, .ico, .icns]
        let readableImages: [ConversionFormat] = writableImages + [.webp, .avif, .psd,
                                                                    .cr2, .nef, .arw, .dng, .raf, .orf, .rw2, .pef]
        for src in readableImages {
            for dst in writableImages where dst != src {
                register(pair: ConversionPair(source: src, target: dst), engine: image)
            }
        }

        // PDF
        let pdfSources: [ConversionFormat] = [.pdf, .png, .jpeg, .tiff]
        for src in pdfSources {
            register(pair: ConversionPair(source: src, target: .pdf), engine: pdf)
        }
        // PDF → image via PDFKit
        for dst in [ConversionFormat.png, .jpeg, .tiff] {
            register(pair: ConversionPair(source: .pdf, target: dst), engine: pdf)
        }

        // Config
        let configFmts: [ConversionFormat] = [.json, .yaml, .toml, .plist, .xml]
        for src in configFmts {
            for dst in configFmts where dst != src {
                register(pair: ConversionPair(source: src, target: dst), engine: config)
            }
        }

        // Spreadsheets (CSV/TSV only — built-in)
        register(pair: ConversionPair(source: .csv, target: .tsv), engine: config)
        register(pair: ConversionPair(source: .tsv, target: .csv), engine: config)

        // Archives
        register(pair: ConversionPair(source: .zip, target: .tar), engine: archive)
        register(pair: ConversionPair(source: .tar, target: .zip), engine: archive)
        register(pair: ConversionPair(source: .tgz, target: .zip), engine: archive)
        register(pair: ConversionPair(source: .zip, target: .tgz), engine: archive)
        // gzip single-file wrap/unwrap
        register(pair: ConversionPair(source: .gzip, target: .tar), engine: archive)
        register(pair: ConversionPair(source: .tar,  target: .gzip), engine: archive)

        // Email
        register(pair: ConversionPair(source: .eml,  target: .html), engine: email)
        register(pair: ConversionPair(source: .eml,  target: .txt),  engine: email)
        register(pair: ConversionPair(source: .emlx, target: .html), engine: email)
        register(pair: ConversionPair(source: .emlx, target: .txt),  engine: email)
        // MSG: marked unsupported (compound binary format needs heavy parser)

        // Audio + Video — ffmpeg (may be unavailable)
        let audioFmts: [ConversionFormat] = [.mp3, .aac, .m4a, .wav, .aiff, .flac, .alac, .ogg, .opus, .wma, .caf, .ac3, .eac3]
        let videoFmts: [ConversionFormat] = [.mp4, .mov, .webm, .mkv, .avi, .threegp, .mxf, .mpeg, .m2ts, .vob, .wmv, .flv, .ts]
        for src in audioFmts {
            for dst in audioFmts where dst != src {
                register(pair: ConversionPair(source: src, target: dst), engine: ffmpeg)
            }
        }
        for src in videoFmts {
            for dst in videoFmts where dst != src {
                register(pair: ConversionPair(source: src, target: dst), engine: ffmpeg)
            }
        }
        // Audio ↔ video extraction / remux
        for src in videoFmts {
            for dst in audioFmts {
                register(pair: ConversionPair(source: src, target: dst), engine: ffmpeg)
            }
        }
    }

    private func register(pair: ConversionPair, engine: ConversionEngine) {
        entries.append(CapabilityEntry(pair: pair, engine: engine))
    }

    /// Returns the best engine for the pair, or nil if unsupported.
    func engine(for pair: ConversionPair) -> ConversionEngine? {
        entries.first { $0.pair == pair }?.engine
    }

    /// True if we have an engine (available or not) for the pair.
    func supports(_ pair: ConversionPair) -> Bool {
        engine(for: pair) != nil
    }

    /// Availability of the engine for this pair.
    func availability(for pair: ConversionPair) -> EngineAvailability {
        guard let eng = engine(for: pair) else { return .missingDependency("unsupported") }
        return eng.availability(for: pair)
    }

    /// All supported target formats for a given source.
    func targets(for source: ConversionFormat) -> [ConversionFormat] {
        entries
            .filter { $0.pair.source == source }
            .map { $0.pair.target }
    }
}
