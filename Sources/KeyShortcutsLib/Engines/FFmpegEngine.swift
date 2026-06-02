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

        var args = ["-y", "-i", item.sourceURL.path]
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
            if let p = readFFmpegProgress(progressFile) {
                progress(p)
            }
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

    // Parse out:time=HH:MM:SS.ms and out:duration from ffmpeg -progress output.
    // Returns 0…1 fraction if both are readable, nil otherwise.
    private func readFFmpegProgress(_ url: URL) -> Double? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var outTimeUs: Double?
        let durationUs: Double? = nil  // not emitted in -progress file; would need to parse stderr
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("out_time_us="), let v = Double(line.dropFirst("out_time_us=".count)) {
                outTimeUs = v
            }
            if line.hasPrefix("Duration:") {
                // Not in progress file — ignore
            }
        }
        guard let t = outTimeUs, let d = durationUs, d > 0 else { return outTimeUs != nil ? nil : nil }
        return min(1.0, t / d)
    }
}
