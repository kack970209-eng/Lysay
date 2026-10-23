import SwiftUI

extension Color {
    /// Lysay 品牌色：iOS 系统蓝
    static let lysay = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let lysayLight = Color(red: 0.36, green: 0.66, blue: 1.0)
}

extension View {
    /// iOS 26 液态玻璃；旧系统退回毛玻璃材质。
    @ViewBuilder
    func lysayGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(lysayMakeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill((tint ?? .clear).opacity(0.55)))
                .overlay(shape.stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func lysayGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

@available(iOS 26.0, *)
private func lysayMakeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

/// 麦克风圆球：待机显示麦克风，聆听时显示声波并随音量呼吸。
struct MicOrb: View {
    var size: CGFloat = 84
    var active: Bool
    var busy: Bool = false
    var level: Float = 0

    var body: some View {
        ZStack {
            if active {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(Color.lysay.opacity(0.35 - Double(i) * 0.12), lineWidth: 2)
                        .frame(width: size, height: size)
                        .scaleEffect(1 + CGFloat(level) * (0.28 + CGFloat(i) * 0.22))
                }
            }
            Group {
                if busy && !active {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    Image(systemName: active ? "waveform" : "mic.fill")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .symbolEffect(.variableColor.iterative, isActive: active)
                        .foregroundStyle(active ? Color.white : Color.primary)
                }
            }
            .frame(width: size, height: size)
            .lysayGlass(in: Circle(), tint: active ? Color.lysay : nil, interactive: true)
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .animation(.easeOut(duration: 0.12), value: level)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: active)
        .contentShape(Circle())
    }
}
