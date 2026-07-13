import Foundation

// Wraps a bundled ffmpeg binary (Contents/Helpers/ffmpeg).
// ffmpeg is GPL — its license is included in Contents/Helpers/ffmpeg-LICENSE.txt.
// Phase 2 will bundle the binary; Phase 1 detects it at an external path if present.
final class FFmpegEngine: ConversionEngine {
    static let shared = FFmpegEngine()
    let engineName = "ffmpeg"

    private init() {}

    // Resolve ffmpeg: bundled first, then /usr/local/bin, then /opt/homebrew/bin.
    var ffmpegPath: String? {
        let helpers = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ffmpeg").path
        if FileManager.default.isExecutableFile(atPath: helpers) { return helpers }
        for fallback in ["/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: fallback) { return fallback }
        }
        return nil
    }

    func availability(for pair: ConversionPair) -> EngineAvailability {
        if ffmpegPath == nil {
            return .missingDependency("ffmpeg")
        }
        return .available
    }

    func convert(item: ConversionItem, to outputURL: URL, progress: @escaping (Double) -> Void) throws {
        guard let ffmpeg = ffmpegPath else {
            throw ConversionError.dependencyMissing("ffmpeg not found. Install via Homebrew: brew install ffmpeg")
        }

        let progressFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).progress")
        defer { try? FileManager.default.removeItem(at: progressFile) }

        // Total duration in µs, for converting out_time_us into a 0…1 fraction.
        let totalUs = probeDurationSeconds(ffmpeg: ffmpeg, input: item.sourceURL).map { $0 * 1_000_000 }

        // -nostats: without it ffmpeg streams stats to stderr for the whole run,
        // which can fill the pipe buffer and deadlock long conversions.
        var args = ["-y", "-nostats", "-loglevel", "error", "-i", item.sourceURL.path]
        args += extraArgs(for: item.targetFormat)
        args += ["-progress", progressFile.path, outputURL.path]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()

        // Poll progress file while ffmpeg runs
        let deadline = Date().addingTimeInterval(3600)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            if let p = readFFmpegProgress(progressFile, totalUs: totalUs) {
                progress(p)
            }
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw ConversionError.processError("ffmpeg timed out after 1 hour")
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8)?.components(separatedBy: "\n").last(where: { !$0.isEmpty }) ?? "unknown"
            throw ConversionError.processError("ffmpeg: \(msg)")
        }
        progress(1.0)
    }

    private func extraArgs(for fmt: ConversionFormat) -> [String] {
        switch fmt {
        case .mp3:  return ["-codec:a", "libmp3lame", "-q:a", "2"]
        case .aac:  return ["-codec:a", "aac", "-b:a", "192k"]
        case .m4a:  return ["-codec:a", "aac", "-b:a", "192k"]
        case .flac: return ["-codec:a", "flac"]
        case .alac: return ["-codec:a", "alac"]
        case .ogg:  return ["-codec:a", "libvorbis", "-q:a", "5"]
        case .opus: return ["-codec:a", "libopus", "-b:a", "128k"]
        case .wav:  return ["-codec:a", "pcm_s16le"]
        case .aiff: return ["-codec:a", "pcm_s16be"]
        case .wma:  return ["-codec:a", "wmav2"]
        case .caf:  return ["-codec:a", "pcm_s16le"]
        case .mp4:  return ["-codec:v", "libx264", "-preset", "medium", "-crf", "23", "-codec:a", "aac"]
        case .mov:  return ["-codec:v", "libx264", "-preset", "medium", "-crf", "23", "-codec:a", "aac"]
        case .webm: return ["-codec:v", "libvpx-vp9", "-crf", "30", "-b:v", "0", "-codec:a", "libopus"]
        case .mkv:  return ["-codec:v", "copy", "-codec:a", "copy"]
        case .avi:  return ["-codec:v", "libxvid", "-codec:a", "mp3"]
        default:    return []
        }
    }

    // Read the source's total duration from ffmpeg's "-i" banner on stderr
    // ("Duration: HH:MM:SS.ms, ..."). Returns nil for streams with no duration.
    private func probeDurationSeconds(ffmpeg: String, input: URL) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-hide_banner", "-i", input.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8),
              let range = text.range(of: #"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)"#, options: .regularExpression)
        else { return nil }
        let parts = text[range].dropFirst("Duration: ".count).split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2])
        else { return nil }
        return h * 3600 + m * 60 + s
    }

    // Parse out_time_us from ffmpeg's -progress file and convert to a 0…1 fraction.
    private func readFFmpegProgress(_ url: URL, totalUs: Double?) -> Double? {
        guard let totalUs, totalUs > 0,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var outTimeUs: Double?
        for line in text.components(separatedBy: "\n") where line.hasPrefix("out_time_us=") {
            if let v = Double(line.dropFirst("out_time_us=".count)) { outTimeUs = v }
        }
        guard let t = outTimeUs else { return nil }
        return min(1.0, t / totalUs)
    }
}
