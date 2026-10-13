import SwiftUI
import AppKit

enum MascotPose: String, CaseIterable { case idle, thinking, speaking, happy }
enum MascotAssets {
    static func image(_ pose: MascotPose) -> NSImage {
        let name = "nika_" + pose.rawValue
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Mascot")
            ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Mascot")
        return url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 1, height: 1))
    }
    static let menuIcon: NSImage = {
        let icon = image(.idle).copy() as! NSImage
        icon.size = NSSize(width: 22, height: 22); icon.isTemplate = false; return icon
    }()
    static let images = Dictionary(uniqueKeysWithValues: MascotPose.allCases.map { ($0, image($0)) })
}
/// Original iPhone illustrations. Voice changes the pose, never the mascot's body colour.
struct DesktopMascot: View {
    var pose: MascotPose = .idle
    var size: CGFloat = 144
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var happy = false
    @State private var previousPose: MascotPose = .idle
    var body: some View {
        ZStack {
            ForEach(MascotPose.allCases, id: \.self) { item in
                Image(nsImage: MascotAssets.images[item]!).resizable().scaledToFit()
                    .opacity(item == (happy ? .happy : pose) ? 1 : 0)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: size * 0.055, y: size * 0.025)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.28), value: pose)
        .animation(.easeOut(duration: 0.2), value: happy)
        .task(id: pose) {
            happy = previousPose == .speaking && pose == .idle
            previousPose = pose
            guard happy else { return }; try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }; happy = false
        }
        .accessibilityHidden(true)
    }
}
