import Foundation
import UniformTypeIdentifiers

// MARK: - Format

enum ConversionFormat: String, CaseIterable, Equatable, Hashable {
    // Images
    case jpeg, png, gif, webp, heic, avif, tiff, bmp, ico, icns, psd
    case cr2, nef, arw, dng, raf, orf, rw2, pef   // camera RAW — input only
    case svg, eps

    // Audio
    case mp3, aac, m4a, wav, aiff, flac, alac, ogg, opus, wma, caf, ac3, eac3

    // Video
    case mp4, mov, webm, mkv, avi, threegp, mxf, mpeg, m2ts, vob, wmv, flv, ts

    // Documents
    case pdf, ps, docx, pptx, rtf, doc, odt, html, markdown, txt, rst, latex

    // E-books
    case epub, mobi, azw, azw3

    // Email
    case eml, emlx, msg

    // Config
    case json, yaml, toml, plist, xml

    // Spreadsheets
    case csv, tsv, xlsx, xls

    // Archives
    case zip, tar, tgz, gzip, sevenzip

    var fileExtension: String {
        switch self {
        case .jpeg:     return "jpg"
        case .threegp:  return "3gp"
        case .sevenzip: return "7z"
        case .markdown: return "md"
        case .latex:    return "tex"
        case .ac3:      return "ac3"
        case .eac3:     return "eac3"
        default:        return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .jpeg:     return "JPEG"
        case .png:      return "PNG"
        case .gif:      return "GIF"
        case .webp:     return "WebP"
        case .heic:     return "HEIC"
        case .avif:     return "AVIF"
        case .tiff:     return "TIFF"
        case .bmp:      return "BMP"
        case .ico:      return "ICO"
        case .icns:     return "ICNS"
        case .psd:      return "PSD"
        case .cr2:      return "CR2"
        case .nef:      return "NEF"
        case .arw:      return "ARW"
        case .dng:      return "DNG"
        case .raf:      return "RAF"
        case .orf:      return "ORF"
        case .rw2:      return "RW2"
        case .pef:      return "PEF"
        case .svg:      return "SVG"
        case .eps:      return "EPS"
        case .mp3:      return "MP3"
        case .aac:      return "AAC"
        case .m4a:      return "M4A"
        case .wav:      return "WAV"
        case .aiff:     return "AIFF"
        case .flac:     return "FLAC"
        case .alac:     return "ALAC"
        case .ogg:      return "OGG"
        case .opus:     return "Opus"
        case .wma:      return "WMA"
        case .caf:      return "CAF"
        case .ac3:      return "AC-3"
        case .eac3:     return "E-AC-3"
        case .mp4:      return "MP4"
        case .mov:      return "MOV"
        case .webm:     return "WebM"
        case .mkv:      return "MKV"
        case .avi:      return "AVI"
        case .threegp:  return "3GP"
        case .mxf:      return "MXF"
        case .mpeg:     return "MPEG"
        case .m2ts:     return "M2TS"
        case .vob:      return "VOB"
        case .wmv:      return "WMV"
        case .flv:      return "FLV"
        case .ts:       return "TS"
        case .pdf:      return "PDF"
        case .ps:       return "PS"
        case .docx:     return "DOCX"
        case .pptx:     return "PPTX"
        case .rtf:      return "RTF"
        case .doc:      return "DOC"
        case .odt:      return "ODT"
        case .html:     return "HTML"
        case .markdown: return "Markdown"
        case .txt:      return "TXT"
        case .rst:      return "RST"
        case .latex:    return "LaTeX"
        case .epub:     return "EPUB"
        case .mobi:     return "MOBI"
        case .azw:      return "AZW"
        case .azw3:     return "AZW3"
        case .eml:      return "EML"
        case .emlx:     return "EMLX"
        case .msg:      return "MSG"
        case .json:     return "JSON"
        case .yaml:     return "YAML"
        case .toml:     return "TOML"
        case .plist:    return "Plist"
        case .xml:      return "XML"
        case .csv:      return "CSV"
        case .tsv:      return "TSV"
        case .xlsx:     return "XLSX"
        case .xls:      return "XLS"
        case .zip:      return "ZIP"
        case .tar:      return "TAR"
        case .tgz:      return "TGZ"
        case .gzip:     return "GZIP"
        case .sevenzip: return "7z"
        }
    }

    // Camera RAW formats are read-only inputs; writing them is not supported.
    var isInputOnly: Bool {
        switch self {
        case .cr2, .nef, .arw, .raf, .orf, .rw2, .pef: return true
        default: return false
        }
    }

    // All file extensions that map to this format (for extension→format lookup).
    static var extensionMap: [String: ConversionFormat] = {
        var map: [String: ConversionFormat] = [:]
        for fmt in ConversionFormat.allCases {
            map[fmt.fileExtension.lowercased()] = fmt
        }
        // Extra aliases
        map["jpeg"]  = .jpeg
        map["tif"]   = .tiff
        map["mpg"]   = .mpeg
        map["ts"]    = .ts
        map["3gpp"]  = .threegp
        map["aif"]   = .aiff
        map["yml"]   = .yaml
        return map
    }()
}

// MARK: - Conversion item states

enum ConversionState: Equatable {
    case pending
    case converting(progress: Double)   // 0…1
    case done
    case failed(String)
    case dismissed
}

// MARK: - Pending conversion

struct ConversionItem: Identifiable {
    let id: UUID
    let sourceURL: URL
    let detectedSourceFormat: ConversionFormat
    let targetFormat: ConversionFormat
    var state: ConversionState
    var outputURL: URL?

    init(sourceURL: URL, detected: ConversionFormat, target: ConversionFormat) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.detectedSourceFormat = detected
        self.targetFormat = target
        self.state = .pending
    }

    var filename: String { sourceURL.lastPathComponent }

    var description: String {
        "\(filename) → \(targetFormat.displayName)"
    }
}

// MARK: - Engine availability

enum EngineAvailability: Equatable {
    case available
    case missingDependency(String)   // name of the tool (e.g. "ffmpeg", "LibreOffice")
    case unsupportedOnThisOS(String) // reason
}
