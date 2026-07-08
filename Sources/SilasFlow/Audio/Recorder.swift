import AVFoundation
import Foundation

/// Captures microphone audio and accumulates 16 kHz mono Float32 samples
/// (the format Whisper models expect).
///
/// A FRESH AVAudioEngine is created for every recording session: reusing one
/// engine across stop/start cycles can silently deliver zeroed (silent)
/// buffers after the first cycle on modern macOS — recording "works" (buffers
/// arrive, durations count up) but contains no audio, so Whisper returns "".
final class Recorder {
    static let sampleRate: Double = 16_000

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sumSquares: Double = 0
    private var peak: Float = 0
    private(set) var isRecording = false

    /// Live loudness callback (0…1-ish RMS per buffer), for UI level meters.
    /// Called on the audio thread — hop to the main actor before touching UI.
    var onLevel: ((Float) -> Void)?

    private lazy var outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Self.sampleRate,
        channels: 1,
        interleaved: false
    )!

    func start() throws {
        guard !isRecording else { return }
        lock.lock()
        samples.removeAll()
        sumSquares = 0
        peak = 0
        lock.unlock()

        // Fresh engine every session (see class comment).
        let engine = AVAudioEngine()
        self.engine = engine

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
        Diag.log("AUDIO: recording started (input \(Int(inputFormat.sampleRate)) Hz, \(inputFormat.channelCount) ch)")
    }

    /// Stops the engine and returns everything captured as 16 kHz mono Float32.
    func stop() -> [Float] {
        guard isRecording, let engine else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        converter = nil
        isRecording = false

        lock.lock(); defer { lock.unlock() }
        let result = samples
        samples = []
        let rms = result.isEmpty ? 0 : sqrt(sumSquares / Double(result.count))
        Diag.log(String(format: "AUDIO: stopped — %.2fs, rms %.4f, peak %.4f%@",
                        Double(result.count) / Self.sampleRate, rms, peak,
                        rms < 0.001 ? " ⚠️ SILENT INPUT" : ""))
        return result
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = Self.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let error {
            Diag.log("AUDIO: conversion error: \(error.localizedDescription)")
            return
        }
        guard let channel = converted.floatChannelData?[0], converted.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))

        var chunkSquares: Double = 0
        var chunkPeak: Float = 0
        for sample in chunk {
            chunkSquares += Double(sample * sample)
            chunkPeak = max(chunkPeak, abs(sample))
        }
        let level = chunk.isEmpty ? 0 : Float(sqrt(chunkSquares / Double(chunk.count)))

        lock.lock()
        samples.append(contentsOf: chunk)
        sumSquares += chunkSquares
        peak = max(peak, chunkPeak)
        lock.unlock()

        onLevel?(level)
    }
}

enum RecorderError: LocalizedError {
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No microphone input device available."
        }
    }
}
