import SwiftUI

/// AI 语音输入的视觉效果：三条不同颜色的线缠绕在一起，随音量起伏。
/// listening：跟着声音大小波动；thinking：AI 整理时平缓流动。
struct AIWaveView: View {
    enum Mode { case listening, thinking }

    var level: Float
    var mode: Mode

    @Environment(\.colorScheme) private var scheme

    private struct Strand {
        let color: Color
        let frequency: CGFloat   // 横向有几个波峰
        let speed: Double        // 流动速度
        let offset: Double       // 相位错开，让三条线交织
        let weight: CGFloat      // 振幅比例
    }

    private let strands = [
        Strand(color: Color(red: 0.04, green: 0.52, blue: 1.0), frequency: 1.6, speed: 2.6, offset: 0, weight: 1.0),
        Strand(color: Color(red: 0.98, green: 0.30, blue: 0.62), frequency: 2.2, speed: -3.1, offset: 2.1, weight: 0.85),
        Strand(color: Color(red: 0.20, green: 0.86, blue: 0.80), frequency: 2.9, speed: 3.7, offset: 4.2, weight: 0.7),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<strands.count, id: \.self) { i in
                    let s = strands[i]
                    let amp = amplitude(t: t, index: i) * s.weight
                    WaveShape(phase: t * s.speed + s.offset, amplitude: amp, frequency: s.frequency)
                        .stroke(s.color.opacity(0.55), lineWidth: 7)
                        .blur(radius: 6)
                    WaveShape(phase: t * s.speed + s.offset, amplitude: amp, frequency: s.frequency)
                        .stroke(s.color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
            }
            .blendMode(scheme == .dark ? .plusLighter : .normal)
            .animation(.easeOut(duration: 0.14), value: level)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func amplitude(t: Double, index: Int) -> CGFloat {
        switch mode {
        case .listening:
            // 安静时保留一点起伏，说话时随音量放大；每条线略有不同的呼吸
            let breathe = 0.5 + 0.5 * sin(t * 1.7 + Double(index))
            return 0.10 + 0.06 * CGFloat(breathe) + CGFloat(level) * 0.84
        case .thinking:
            let pulse = 0.5 + 0.5 * sin(t * 2.4 + Double(index) * 1.3)
            return 0.18 + 0.16 * CGFloat(pulse)
        }
    }
}

/// 两端收拢、中间起伏的正弦线
struct WaveShape: Shape {
    var phase: Double
    var amplitude: CGFloat   // 0…1，相对于半高
    var frequency: CGFloat

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        let half = rect.height / 2 * 0.9
        let step: CGFloat = 2
        var x: CGFloat = 0
        var first = true
        while x <= rect.width {
            let n = x / rect.width * 2 - 1                 // -1 … 1
            let envelope = pow(1 - n * n, 2)               // 两端收成一点
            let y = mid + sin(n * frequency * .pi + CGFloat(phase)) * half * amplitude * envelope
            if first {
                p.move(to: CGPoint(x: x, y: y))
                first = false
            } else {
                p.addLine(to: CGPoint(x: x, y: y))
            }
            x += step
        }
        return p
    }
}
