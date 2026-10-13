import SwiftUI
import AppKit

/// A multiline field owns its scrolling and never paints an AppKit square over glass.
struct DesktopTextArea: View {
    @Binding var text: String
    var height: CGFloat = 140
    var label: String = "Текст"
    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(height: height)
            .background(DesktopStyle.surface.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
            .accessibilityLabel(label)
    }
}
enum DesktopFormLayout {
    static func width(_ preferred: CGFloat) -> CGFloat {
        min(preferred, max(320, (NSScreen.main?.visibleFrame.width ?? 1280) - 80))
    }
    static func height(_ preferred: CGFloat) -> CGFloat {
        min(preferred, max(360, (NSScreen.main?.visibleFrame.height ?? 800) - 110))
    }
}
