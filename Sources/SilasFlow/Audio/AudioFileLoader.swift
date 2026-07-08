import AVFoundation
import Foundation

/// Loads an audio file and converts it to 16 kHz mono Float32 samples
/// (used by --selftest; the live path uses Recorder instead).
enum AudioFileLoader {
    static func load(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw AudioFileError.readFailed
        }
        try file.read(into: sourceBuffer)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Recorder.sampleRate,
            channels: 1,
            interleaved: false
        )!

        if sourceFormat == targetFormat {
            return samples(from: sourceBuffer)
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioFileError.conversionFailed
        }
        let ratio = Recorder.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw AudioFileError.conversionFailed
        }

        var fed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        if let error { throw error }
        return samples(from: converted)
    }

    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}

enum AudioFileError: LocalizedError {
    case readFailed
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .readFailed: return "Could not read audio file."
        case .conversionFailed: return "Could not convert audio to 16 kHz mono."
        }
    }
}
