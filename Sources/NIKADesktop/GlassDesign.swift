import SwiftUI
import AppKit

/// iPhone «Сияние»: coloured light sits along the bottom; content stays neutral.
struct AuroraCanvas: View {
    var level: Double = 0
    var listening = false
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @AppStorage("auroraIntensity") private var intensity = 0.65
    var body: some View {
        ZStack(alignment: .bottom) {
            DesktopStyle.canvas
            if !opaque { DesktopBottomGlow(level: level, listening: listening).opacity(intensity) }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct DesktopBottomGlow: View {
    var level: Double = 0
    var listening = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    // Exact default palette from mobile NIKAGlow.
    static let colors = [Color(red: 0x15/255, green: 0x3C/255, blue: 1), Color(red: 0x19/255, green: 0xBD/255, blue: 0xF2/255), Color(red: 0x9A/255, green: 0x79/255, blue: 1), Color(red: 1, green: 0xD0/255, blue: 1)]
    var body: some View {
        GeometryReader { geometry in
            let loudness = listening ? VoiceLevel.shaped(level) : 0
            let energy = reduceMotion ? 0 : loudness
            let width = min(1100, geometry.size.width * 0.98)
            let height = min(460, max(240, geometry.size.height * 0.52))
            let strength = (scheme == .dark ? 1.0 : 0.72) * (1 + loudness * 0.65)
            ZStack {
                // Wide, feathered atmosphere. Never compress a blurred shape into a strip.
                light(Self.colors[0], strength: 0.42 * strength)
                    .frame(width: width, height: height * (1 + energy * 0.35))
                    .position(x: geometry.size.width * 0.48, y: geometry.size.height - height * 0.16)
                light(Self.colors[1], strength: 0.55 * strength)
                    .frame(width: width * 0.67, height: height * (0.74 + energy * 0.36))
                    .position(x: geometry.size.width * 0.42, y: geometry.size.height - height * 0.25)
                light(Self.colors[2], strength: 0.56 * strength)
                    .frame(width: width * 0.65, height: height * (0.88 + energy * 0.32))
                    .position(x: geometry.size.width * 0.65, y: geometry.size.height - height * 0.21)
                light(Self.colors[3], strength: 0.16 * strength)
                    .frame(width: width * 0.42, height: height * 0.5)
                    .position(x: geometry.size.width * 0.57, y: geometry.size.height - height * 0.17)
            }
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .white, location: 0.16),
                .init(color: .white, location: 0.84), .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing))
        }
        .clipped()
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.18), value: level)
        .animation(.easeOut(duration: 0.28), value: listening)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func light(_ color: Color, strength: Double) -> some View {
        Rectangle().fill(EllipticalGradient(stops: [
            .init(color: color.opacity(min(1, strength)), location: 0),
            .init(color: color.opacity(min(1, strength) * 0.66), location: 0.28),
            .init(color: color.opacity(min(1, strength) * 0.22), location: 0.57),
            .init(color: color.opacity(min(1, strength) * 0.04), location: 0.82),
            .init(color: color.opacity(0), location: 1)
        ], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
    }

}
struct GlassSurface: ViewModifier {
    var radius: CGFloat = 18
    var elevated = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if opaque { shape.fill(DesktopStyle.surface) }
            else {
                shape.fill(.regularMaterial)
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.035 : 0.42), .clear, Color.accentColor.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(
            LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.19 : 0.85), .primary.opacity(contrast == .increased ? 0.4 : 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
        .shadow(color: .black.opacity(elevated ? (scheme == .dark ? 0.2 : 0.06) : 0.015), radius: elevated ? 22 : 6, x: 0, y: elevated ? 8 : 2)
    }
}
extension View {
    func nikaGlass(radius: CGFloat = 18, elevated: Bool = false) -> some View { modifier(GlassSurface(radius: radius, elevated: elevated)) }
}
struct NikaMark: View {
    var size: CGFloat = 78
    var body: some View { DesktopMascot(size: size) }
}
