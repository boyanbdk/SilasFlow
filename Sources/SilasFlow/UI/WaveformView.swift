import SwiftUI

/// The floating pill's content: 12 vertical bars over a dark capsule.
/// listening  — bars follow live mic loudness (scrolling history)
/// processing — bars ripple in a gentle left-to-right wave
/// error      — bars turn red briefly before the pill hides
struct WaveformView: View {
    @ObservedObject var overlay: OverlayController

    private let barWidth: CGFloat = 6
    private let barSpacing: CGFloat = 6
    private let minHeight: CGFloat = 6
    private let maxHeight: CGFloat = 36

    var body: some View {
        Group {
            switch overlay.phase {
            case .listening:
                bars { index in liveHeight(overlay.levels[index]) }
                    .animation(.easeOut(duration: 0.09), value: overlay.levels)
            case .processing:
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    bars { index in rippleHeight(index: index, time: t) }
                }
            case .error:
                bars { _ in 14 }
            }
        }
        .frame(width: 210, height: 54)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.78))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        )
    }

    private func bars(height: @escaping (Int) -> CGFloat) -> some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<OverlayController.barCount, id: \.self) { index in
                Capsule()
                    .fill(barColor)
                    .frame(width: barWidth, height: height(index))
            }
        }
    }

    private var barColor: Color {
        switch overlay.phase {
        case .listening: return .white
        case .processing: return Color.white.opacity(0.8)
        case .error: return .red
        }
    }

    /// Map RMS loudness (~0.001 ambient … ~0.15 loud speech) to bar height.
    private func liveHeight(_ level: Float) -> CGFloat {
        let gain: CGFloat = 320
        let h = minHeight + min(CGFloat(level) * gain, maxHeight - minHeight)
        return max(minHeight, h)
    }

    private func rippleHeight(index: Int, time: TimeInterval) -> CGFloat {
        let phase = time * 3.0 - Double(index) * 0.55
        let wave = (sin(phase) + 1) / 2 // 0…1
        return minHeight + CGFloat(wave) * 14
    }
}
