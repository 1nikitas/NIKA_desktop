import Foundation
import ImageIO
import UniformTypeIdentifiers

extension Workspace {
    nonisolated static func imageFiles(_ urls: [URL]) -> [URL] { urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true } }
    nonisolated static func preserveImages(_ urls: [URL], directory: URL) async throws -> [String] {
        guard urls.count <= 4 else { throw DesktopError("Добавьте до четырёх изображений за раз.") }
        return try await Task.detached {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try urls.map { url in
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 25_000_000 else { throw DesktopError("Изображение больше 25 МБ.") }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw DesktopError("Не удалось прочитать изображение.") }
                let name = UUID().uuidString + ".jpg"
                guard let output = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw DesktopError("Не удалось сохранить изображение.") }
                CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
                guard CGImageDestinationFinalize(output) else { throw DesktopError("Не удалось сохранить изображение.") }; return name
            }
        }.value
    }
    nonisolated static func inferenceTurns(_ messages: [DesktopMessage], directory: URL) async throws -> [InferenceMessage] {
        try await Task.detached {
            try messages.map { message in
                let images = try (message.localImages ?? []).map { name -> String in
                    guard !name.contains("/"), !name.contains("..") else { throw DesktopError("Некорректная ссылка на локальное изображение.") }
                    return "data:image/jpeg;base64," + (try Data(contentsOf: directory.appendingPathComponent(name))).base64EncodedString()
                }
                return InferenceMessage(role: message.role, content: message.content, images: images)
            }
        }.value
    }
}
