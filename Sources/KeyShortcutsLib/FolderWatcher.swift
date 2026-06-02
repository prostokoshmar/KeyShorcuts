import Foundation
import CoreServices

// Watches a set of folders with FSEvents and emits changed file URLs after debounce.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private var watchedPaths: [String] = []
    private var debounceWork: DispatchWorkItem?
    private var pendingURLs: Set<URL> = []
    private let debounceInterval: TimeInterval = 1.2
    private let queue = DispatchQueue(label: "com.keyshortcuts.folderwatcher", qos: .utility)

    var onFilesChanged: (([URL]) -> Void)?

    func start(paths: [String]) {
        stop()
        guard !paths.isEmpty else { return }
        watchedPaths = paths

        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            let urls  = paths.prefix(numEvents).map { URL(fileURLWithPath: $0) }
            watcher.received(urls: urls)
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &ctx,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // latency seconds
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        debounceWork?.cancel()
        pendingURLs.removeAll()
    }

    private func received(urls: [URL]) {
        let filtered = urls.filter { shouldProcess($0) }
        guard !filtered.isEmpty else { return }

        pendingURLs.formUnion(filtered)

        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let batch = Array(self.pendingURLs)
            self.pendingURLs.removeAll()
            DispatchQueue.main.async { self.onFilesChanged?(batch) }
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    // Subdirectory name components that generate high-volume FSEvents noise.
    // Files anywhere under these paths are skipped.
    private static let noisyPathComponents: Set<String> = [
        "Library", ".build", ".git", ".svn", "node_modules", ".npm",
        ".gradle", ".idea", "DerivedData", "Pods", ".cache",
        "Virtual Machines.localized", ".Trash",
    ]

    private func shouldProcess(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        // Ignore hidden files, temp files, and directories
        if name.hasPrefix(".") { return false }
        if name.hasSuffix(".tmp") || name.hasSuffix(".part") || name.hasSuffix(".crdownload") { return false }
        if name.hasSuffix(".download") { return false }
        // Ignore package directories (e.g. .app, .bundle, .xcodeproj)
        let ext = url.pathExtension.lowercased()
        let packageExts: Set<String> = ["app", "bundle", "xcodeproj", "xctestproduct", "framework"]
        if packageExts.contains(ext) { return false }
        // Skip noisy subtrees (Library, node_modules, .build, etc.)
        let components = url.pathComponents
        for component in components where FolderWatcher.noisyPathComponents.contains(component) {
            return false
        }
        // Must be a regular file
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
        // Ignore files with no extension (can't determine target format)
        guard !url.pathExtension.isEmpty else { return false }
        return true
    }
}

// MARK: - Format detection via magic bytes / ImageIO / UTType

final class FormatDetector {
    static func detect(url: URL) -> ConversionFormat? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        let bytes = Array(data.prefix(270))  // 270 bytes covers TAR magic at offset 257

        // Magic byte checks
        if let fmt = magicFormat(bytes: bytes, ext: url.pathExtension.lowercased()) { return fmt }

        // Fall back to UTType via file attributes
        if #available(macOS 12, *) {
            if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
               let ut = values.contentType {
                if let fmt = utTypeToFormat(ut.identifier) { return fmt }
            }
        }

        return nil
    }

    // MARK: - Magic bytes

    private static func magicFormat(bytes: [UInt8], ext: String) -> ConversionFormat? {
        guard bytes.count >= 4 else { return nil }

        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF { return .jpeg }

        // PNG: 89 50 4E 47
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 { return .png }

        // GIF: 47 49 46 38
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 { return .gif }

        // TIFF: 49 49 or 4D 4D
        if (bytes[0] == 0x49 && bytes[1] == 0x49) || (bytes[0] == 0x4D && bytes[1] == 0x4D) {
            // DNG/ARW/NEF/CR2 also start with TIFF magic — use extension to disambiguate
            switch ext {
            case "dng": return .dng
            case "arw": return .arw
            case "nef": return .nef
            case "cr2": return .cr2
            case "orf": return .orf
            case "rw2": return .rw2
            case "pef": return .pef
            default:    return .tiff
            }
        }

        // BMP: 42 4D
        if bytes[0] == 0x42 && bytes[1] == 0x4D { return .bmp }

        // WebP: 52 49 46 46 ?? ?? ?? ?? 57 45 42 50
        if bytes.count >= 12 && bytes[0]==0x52 && bytes[1]==0x49 && bytes[2]==0x46 && bytes[3]==0x46
            && bytes[8]==0x57 && bytes[9]==0x45 && bytes[10]==0x42 && bytes[11]==0x50 { return .webp }

        // HEIC: ftyp box — look for 'ftyp' at offset 4
        if bytes.count >= 12 && bytes[4]==0x66 && bytes[5]==0x74 && bytes[6]==0x79 && bytes[7]==0x70 {
            let brand = String(bytes: bytes[8...11], encoding: .ascii) ?? ""
            if brand.hasPrefix("heic") || brand.hasPrefix("heis") || brand.hasPrefix("mif1") { return .heic }
            if brand.hasPrefix("avif") || brand.hasPrefix("avis") { return .avif }
        }

        // PDF: 25 50 44 46
        if bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 { return .pdf }

        // ZIP: 50 4B 03 04
        if bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04 {
            // DOCX/XLSX/PPTX are ZIPs — use extension to distinguish
            switch ext {
            case "docx": return .docx
            case "xlsx": return .xlsx
            case "pptx": return .pptx
            default:     return .zip
            }
        }

        // GZIP / TGZ: 1F 8B
        if bytes[0] == 0x1F && bytes[1] == 0x8B {
            return (ext == "tgz" || ext == "tar.gz") ? .tgz : .gzip
        }

        // TAR: "ustar" at offset 257
        if bytes.count >= 262 {
            let tarMagic = Array(bytes[257...261])
            if tarMagic[0]==0x75 && tarMagic[1]==0x73 && tarMagic[2]==0x74 && tarMagic[3]==0x61 && tarMagic[4]==0x72 {
                return .tar
            }
        }

        // 7z: 37 7A BC AF 27 1C
        if bytes.count >= 6 && bytes[0]==0x37 && bytes[1]==0x7A && bytes[2]==0xBC && bytes[3]==0xAF { return .sevenzip }

        // FLAC: 66 4C 61 43
        if bytes[0]==0x66 && bytes[1]==0x4C && bytes[2]==0x61 && bytes[3]==0x43 { return .flac }

        // OGG: 4F 67 67 53
        if bytes[0]==0x4F && bytes[1]==0x67 && bytes[2]==0x67 && bytes[3]==0x53 { return .ogg }

        // RIFF (WAV/AVI): 52 49 46 46
        if bytes[0]==0x52 && bytes[1]==0x49 && bytes[2]==0x46 && bytes[3]==0x46 {
            if bytes.count >= 12 {
                let fmt = String(bytes: bytes[8...11], encoding: .ascii) ?? ""
                if fmt == "WAVE" { return .wav }
                if fmt == "AVI " { return .avi }
            }
        }

        // MP3: ID3 (49 44 33) or sync word FF Fx
        if bytes[0]==0x49 && bytes[1]==0x44 && bytes[2]==0x33 { return .mp3 }
        if bytes[0]==0xFF && (bytes[1] & 0xE0) == 0xE0 { return .mp3 }

        // M4A/AAC: ftyp variants
        if bytes.count >= 12 && bytes[4]==0x66 && bytes[5]==0x74 && bytes[6]==0x79 && bytes[7]==0x70 {
            let brand = String(bytes: bytes[8...11], encoding: .ascii) ?? ""
            if brand.hasPrefix("M4A") || brand.hasPrefix("M4B") { return .m4a }
            if brand.hasPrefix("mp4") || brand.hasPrefix("isom") || brand.hasPrefix("avc1") { return .mp4 }
            if brand.hasPrefix("qt  ") { return .mov }
        }

        // MKV / WebM: EBML
        if bytes[0]==0x1A && bytes[1]==0x45 && bytes[2]==0xDF && bytes[3]==0xA3 {
            return ext == "webm" ? .webm : .mkv
        }

        // EML/EMLX: starts with "From " or common header
        if bytes.count >= 5 {
            let prefix = String(bytes: bytes.prefix(5), encoding: .ascii) ?? ""
            if prefix.hasPrefix("From ") || prefix.hasPrefix("MIME-") || prefix.hasPrefix("Date:") || prefix.hasPrefix("Rece") {
                return ext == "emlx" ? .emlx : .eml
            }
        }

        // JSON: starts with { or [
        if bytes[0] == 0x7B || bytes[0] == 0x5B { return .json }

        // XML/HTML/SVG/Plist
        if bytes[0]==0x3C {
            if let str = String(bytes: bytes, encoding: .utf8) {
                if str.contains("<!DOCTYPE html") || str.contains("<html") { return .html }
                if str.contains("<svg") { return .svg }
                if str.contains("<!DOCTYPE plist") { return .plist }
                return .xml
            }
        }

        // RTF: 7B 5C 72 74 66
        if bytes[0]==0x7B && bytes[1]==0x5C && bytes[2]==0x72 && bytes[3]==0x74 && bytes[4]==0x66 { return .rtf }

        return nil
    }

    private static func utTypeToFormat(_ identifier: String) -> ConversionFormat? {
        let map: [String: ConversionFormat] = [
            "public.jpeg": .jpeg, "public.png": .png, "com.compuserve.gif": .gif,
            "public.tiff": .tiff, "com.microsoft.bmp": .bmp,
            "public.heic": .heic, "public.heif": .heic,
            "public.webp": .webp, "public.avif": .avif,
            "com.apple.icns": .icns,
            "com.adobe.pdf": .pdf,
            "public.zip-archive": .zip, "org.gnu.gnu-tar-archive": .tar,
            "public.tar-bzip2-archive": .tgz, "org.gnu.gnu-zip-archive": .gzip,
            "public.mp3": .mp3, "public.aac-audio": .aac,
            "com.apple.m4a-audio": .m4a, "com.microsoft.waveform-audio": .wav,
            "public.aiff-audio": .aiff, "org.xiph.flac": .flac,
            "public.ogg-vorbis": .ogg, "org.xiph.opus": .opus,
            "public.mpeg-4": .mp4, "com.apple.quicktime-movie": .mov,
            "org.webmproject.webm": .webm, "org.matroska.mkv": .mkv,
            "public.avi": .avi, "public.mpeg": .mpeg,
            "public.json": .json, "com.apple.property-list": .plist,
            "public.xml": .xml, "public.html": .html,
            "public.plain-text": .txt, "public.rtf": .rtf,
        ]
        return map[identifier]
    }
}
