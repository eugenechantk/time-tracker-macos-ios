import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlass(in shape: some Shape = .rect(cornerRadius: 12)) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func adaptiveGlass(
        tint: Color?,
        in shape: some Shape = .rect(cornerRadius: 12)
    ) -> some View {
        adaptiveGlass(tint: tint, isProminent: true, in: shape)
    }

    @ViewBuilder
    func adaptiveGlass(
        tint: Color?,
        isProminent: Bool,
        in shape: some Shape = .rect(cornerRadius: 12)
    ) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: shape)
            } else {
                self.glassEffect(in: shape)
            }
        } else {
            if let tint {
                self
                    .background(tint, in: shape)
                    .background(Color.white.opacity(0.12), in: shape)
            } else if isProminent {
                self.background(Color.white.opacity(0.12), in: shape)
            } else {
                self.background(Color.white.opacity(0.04), in: shape)
            }
        }
    }
}

struct AdaptiveProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            configuration.label
                .buttonStyle(.glassProminent)
        } else {
            configuration.label
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 10))
                .opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}

extension ButtonStyle where Self == AdaptiveProminentButtonStyle {
    static var adaptiveProminent: AdaptiveProminentButtonStyle { .init() }
}
