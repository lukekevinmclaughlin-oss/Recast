import Foundation
import AVFoundation

/// Audio & video via AVFoundation — all on-device, no external tools.
/// Reads the containers AVFoundation understands; writes M4A/WAV/AIFF/CAF and
/// MP4/MOV, and extracts a video's audio track to M4A.
struct AudioVideoBackend: ConversionBackend {
    let id = "avfoundation"
    var isAvailable: Bool { true }

    private let readableAudio = ["mp3", "m4a", "aac", "wav", "aiff", "caf"]
    private let writableAudio = ["m4a", "wav", "aiff", "caf"]
    private let readableVideo = ["mp4", "mov"]
    private let writableVideo = ["mp4", "mov"]

    func edges() -> [FormatEdge] {
        var e: [FormatEdge] = []
        for a in readableAudio {
            for w in writableAudio where a != w {
                e.append(FormatEdge(from: a, to: w, backendID: id, cost: w == "m4a" ? 1.1 : 1.0))
            }
        }
        for v in readableVideo {
            for w in writableVideo where v != w {
                e.append(FormatEdge(from: v, to: w, backendID: id, cost: 1.0))
            }
            e.append(FormatEdge(from: v, to: "m4a", backendID: id, cost: 1.1))  // extract audio
        }
        return e
    }

    func convert(source: URL, from: Format, to: Format,
                 options: ConversionOptions,
                 progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let out = tempURL(for: to)
        switch to.category {
        case .audio where to.id == "m4a":
            try await exportAAC(source: source, to: out, progress: progress)
        case .audio:
            try convertPCM(source: source, to: out, progress: progress)
        case .video:
            let asset = AVURLAsset(url: source)
            guard let session = AVAssetExportSession(asset: asset, presetName: preset(options.videoQuality)) else {
                throw ConversionError.exportFailed("This video can't be exported at the chosen quality.")
            }
            try await AVExportRunner.run(session, to: out, fileType: to.id == "mp4" ? .mp4 : .mov, progress: progress)
        default:
            throw ConversionError.unsupportedTarget("Unsupported A/V target.")
        }
        return out
    }

    private func exportAAC(source: URL, to url: URL,
                           progress: @Sendable @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ConversionError.exportFailed("Couldn't start the audio exporter.")
        }
        try await AVExportRunner.run(session, to: url, fileType: .m4a, progress: progress)
    }

    private func convertPCM(source: URL, to url: URL,
                            progress: @Sendable @escaping (Double) -> Void) throws {
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: source) } catch { throw ConversionError.readFailed }
        let readingFormat = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: input.fileFormat.sampleRate,
            AVNumberOfChannelsKey: input.fileFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output: AVAudioFile
        do { output = try AVAudioFile(forWriting: url, settings: settings) } catch { throw ConversionError.writeFailed }
        let total = input.length
        guard total > 0 else { return }
        let chunk: AVAudioFrameCount = 65_536
        var done: AVAudioFramePosition = 0
        while done < total {
            let toRead = AVAudioFrameCount(min(AVAudioFramePosition(chunk), total - done))
            guard let buf = AVAudioPCMBuffer(pcmFormat: readingFormat, frameCapacity: toRead) else {
                throw ConversionError.readFailed
            }
            try input.read(into: buf, frameCount: toRead)
            if buf.frameLength == 0 { break }
            try output.write(from: buf)
            done += AVAudioFramePosition(buf.frameLength)
            progress(Double(done) / Double(total))
        }
        progress(1)
    }

    private func preset(_ q: VideoQuality) -> String {
        switch q {
        case .same: return AVAssetExportPresetPassthrough
        case .p1080: return AVAssetExportPreset1920x1080
        case .p720: return AVAssetExportPreset1280x720
        }
    }
}
