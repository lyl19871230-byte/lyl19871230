import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var currentRecordingURL: URL?
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var stopTimer: Timer?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    func startRecording() async {
        guard await requestPermission() else {
            errorMessage = "请允许麦克风权限。"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = Self.recordingDirectory().appendingPathComponent("recording-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record()
            self.recorder = recorder
            currentRecordingURL = url
            isRecording = true

            stopTimer?.invalidate()
            stopTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.stopRecording() }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        stopTimer?.invalidate()
        stopTimer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func splitForASRIfNeeded(url: URL) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds > 30 else { return [url] }

        var chunks: [URL] = []
        var start: Double = 0
        while start < seconds {
            let length = min(29.5, seconds - start)
            let outputURL = Self.recordingDirectory().appendingPathComponent("chunk-\(UUID().uuidString).m4a")
            try await export(asset: asset, start: start, duration: length, outputURL: outputURL)
            chunks.append(outputURL)
            start += length
        }
        return chunks
    }

    private func export(asset: AVURLAsset, start: Double, duration: Double, outputURL: URL) async throws {
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioRecorderError.exportUnavailable
        }

        export.outputURL = outputURL
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )

        try await withCheckedThrowingContinuation { continuation in
            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: export.error ?? AudioRecorderError.exportFailed)
                default:
                    continuation.resume(throwing: AudioRecorderError.exportFailed)
                }
            }
        }
    }

    private static func recordingDirectory() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum AudioRecorderError: LocalizedError {
    case exportUnavailable
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .exportUnavailable:
            return "当前设备无法分段导出录音。"
        case .exportFailed:
            return "录音分段失败。"
        }
    }
}

