import XCTest
@testable import NIKADesktop

final class DesktopModelTests: XCTestCase {
    func testEightGBRecommendationReservesSystemMemory() throws {
        let ram: UInt64 = 8 * 1_073_741_824
        let recommended = try XCTUnwrap(DesktopModel.catalogue.first)
        XCTAssertEqual(recommended.id, "smart")
        XCTAssertEqual(recommended.parameters, "4B")
        XCTAssertFalse(DesktopModel.catalogue.contains { $0.id == "mini" })
        XCTAssertTrue(recommended.fits(memory: ram))
        XCTAssertTrue(LocalMemoryBudget.permits(modelBytes: recommended.bytes, context: 4096, memory: ram))
        XCTAssertFalse(LocalMemoryBudget.permits(modelBytes: recommended.bytes, context: 8192, memory: ram))
        XCTAssertFalse(LocalMemoryBudget.permits(modelBytes: recommended.bytes, context: -1, memory: ram))
        XCTAssertFalse(LocalMemoryBudget.permits(modelBytes: 6_000_000_000, context: 2048, memory: ram))
        let vision = recommended.bytes + (try XCTUnwrap(recommended.visionProjector)).bytes
        XCTAssertFalse(LocalMemoryBudget.permits(modelBytes: vision, context: 4096, memory: ram))
        XCTAssertTrue(LocalMemoryBudget.permits(modelBytes: vision, context: 2048, memory: ram))
        XCTAssertTrue(LocalMemoryBudget.permits(modelBytes: recommended.bytes, context: 8192, memory: 16 * 1_073_741_824))
    }

    @MainActor
    func testExistingMiniAndSmartFilesKeepStableIdentities() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Models")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for old in DesktopModel.legacyCatalogue {
            try Data("file-presence-only; integrity still checked on load".utf8).write(to: directory.appendingPathComponent(old.filename))
        }
        let library = ModelLibrary(root: root)
        XCTAssertEqual(library.installed, ["mini", "balance", "smart"])
        XCTAssertEqual(Set(library.models.map(\.id)).count, library.models.count)
        XCTAssertEqual(library.models.first?.id, "smart")
        XCTAssertEqual(library.models.first { $0.id == "mini" }?.filename, DesktopModel.legacyCatalogue[0].filename)
    }
}
