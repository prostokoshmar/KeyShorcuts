import Foundation

final class ArchiveEngine: ConversionEngine {
    static let shared = ArchiveEngine()
    let engineName = "Built-in Archive (/usr/bin/tar + Foundation)"

    private init() {}

    func availability(for pair: ConversionPair) -> EngineAvailability { .available }

    func convert(item: ConversionItem, to outputURL: URL, progress: @escaping (Double) -> Void) throws {
        let src = item.sourceURL
        let src_fmt = item.detectedSourceFormat
        let dst_fmt = item.targetFormat
        let tmp = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")

        defer { try? FileManager.default.removeItem(at: tmp) }

        progress(0.1)

        switch (src_fmt, dst_fmt) {
        case (.zip, .tar), (.tgz, .tar):
            // Unpack source → repack as tar
            let unpacked = try unpackToTemp(src: src, format: src_fmt)
            defer { try? FileManager.default.removeItem(at: unpacked) }
            progress(0.5)
            try packAsTar(directory: unpacked, dst: tmp)

        case (.tar, .zip), (.tgz, .zip):
            let unpacked = try unpackToTemp(src: src, format: src_fmt)
            defer { try? FileManager.default.removeItem(at: unpacked) }
            progress(0.5)
            try packAsZip(directory: unpacked, dst: tmp)

        case (.zip, .tgz), (.tar, .tgz):
            let unpacked = try unpackToTemp(src: src, format: src_fmt)
            defer { try? FileManager.default.removeItem(at: unpacked) }
            progress(0.5)
            try packAsTgz(directory: unpacked, dst: tmp)

        case (.gzip, .tar):
            // gzip is a single-file wrapper; decompress it
            try decompressGzip(src: src, dst: tmp)

        case (.tar, .gzip):
            // gzip-compress the entire tar
            try compressGzip(src: src, dst: tmp)

        default:
            throw ConversionError.unsupported("\(src_fmt.displayName) → \(dst_fmt.displayName) not supported by ArchiveEngine")
        }

        progress(0.9)
        try FileManager.default.moveItem(at: tmp, to: outputURL)
        progress(1.0)
    }

    // MARK: - Helpers

    private func unpackToTemp(src: URL, format: ConversionFormat) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        switch format {
        case .zip:
            try runProcess("/usr/bin/unzip", args: ["-q", src.path, "-d", dir.path])
        case .tar:
            try runProcess("/usr/bin/tar", args: ["-xf", src.path, "-C", dir.path])
        case .tgz:
            try runProcess("/usr/bin/tar", args: ["-xzf", src.path, "-C", dir.path])
        default:
            throw ConversionError.unsupported("Cannot unpack \(format.displayName)")
        }
        return dir
    }

    private func packAsZip(directory: URL, dst: URL) throws {
        // Use ditto for reliable ZIP creation on macOS
        try runProcess("/usr/bin/ditto", args: ["-c", "-k", "--sequesterRsrc", directory.path, dst.path])
    }

    private func packAsTar(directory: URL, dst: URL) throws {
        try runProcess("/usr/bin/tar", args: ["-cf", dst.path, "-C", directory.path, "."])
    }

    private func packAsTgz(directory: URL, dst: URL) throws {
        try runProcess("/usr/bin/tar", args: ["-czf", dst.path, "-C", directory.path, "."])
    }

    private func decompressGzip(src: URL, dst: URL) throws {
        // gunzip to stdout, write to dst
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", src.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ConversionError.processError("gunzip failed (exit \(process.terminationStatus))")
        }
        try data.write(to: dst, options: .atomic)
    }

    private func compressGzip(src: URL, dst: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-c", src.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ConversionError.processError("gzip failed (exit \(process.terminationStatus))")
        }
        try data.write(to: dst, options: .atomic)
    }

    @discardableResult
    private func runProcess(_ path: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw ConversionError.processError("\(path) failed: \(msg)")
        }
        return ""
    }
}
