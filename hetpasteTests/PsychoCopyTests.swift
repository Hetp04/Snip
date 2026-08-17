import Testing
import Foundation
@testable import hetpaste
extension Tag {
    @Tag static var psychocopy: Self
}
@Suite(.tags(.psychocopy))
@MainActor
struct PsychoCopyTests {
    @Test(.tags(.psychocopy)) func property1_modeToggleCompleteness() async throws {
        let manager = PsychoCopyManager()
        #expect(!manager.isMultiCopyModeActive)
        manager.toggleMultiCopyMode()
        #expect(manager.isMultiCopyModeActive)
        manager.handleClipboardChange(ClipboardItem(contentType: .text, contentText: "test", sourceAppName: "Test"))
        #expect(!manager.copyQueue.isEmpty)
        manager.toggleMultiCopyMode()
        #expect(!manager.isMultiCopyModeActive)
        #expect(manager.copyQueue.isEmpty)
    }
    @Test(.tags(.psychocopy)) func property2_queueFIFOOrderingPreservation() async throws {
        let manager = PsychoCopyManager()
        manager.toggleMultiCopyMode()
        let item1 = ClipboardItem(contentType: .text, contentText: "1", sourceAppName: "Test")
        let item2 = ClipboardItem(contentType: .text, contentText: "2", sourceAppName: "Test")
        manager.handleClipboardChange(item1)
        manager.handleClipboardChange(item2)
        #expect(manager.copyQueue.count == 2)
        #expect(manager.copyQueue.items[0].contentText == "1")
        #expect(manager.copyQueue.items[1].contentText == "2")
        var queue = manager.copyQueue
        let qItem1 = queue.dequeue()
        let qItem2 = queue.dequeue()
        #expect(qItem1?.contentText == "1")
        #expect(qItem2?.contentText == "2")
    }
    @Test(.tags(.psychocopy)) func property3_queueAppendAndPreservation() async throws {
        let manager = PsychoCopyManager()
        manager.toggleMultiCopyMode()
        let item1 = ClipboardItem(contentType: .text, contentText: "1", sourceAppName: "Test")
        manager.handleClipboardChange(item1)
        #expect(manager.copyQueue.count == 1)
        #expect(manager.copyQueue.items[0].contentText == "1")
        #expect(manager.copyQueue.items[0].isQueueHead)
        let item2 = ClipboardItem(contentType: .text, contentText: "2", sourceAppName: "Test")
        manager.handleClipboardChange(item2)
        #expect(manager.copyQueue.count == 2)
        #expect(manager.copyQueue.items[0].contentText == "1") 
        #expect(manager.copyQueue.items[1].contentText == "2") 
    }
    @Test(.tags(.psychocopy)) func property4_sequentialPasteQueueModification() async throws {
        let manager = PsychoCopyManager()
        manager.toggleMultiCopyMode()
        let item1 = ClipboardItem(contentType: .text, contentText: "1", sourceAppName: "Test")
        manager.handleClipboardChange(item1)
        var queue = manager.copyQueue
        let itemDequeued = queue.dequeue()
        #expect(itemDequeued?.contentText == "1")
        #expect(queue.isEmpty)
    }
    @Test(.tags(.psychocopy)) func property5_universalContentTypeSupport() async throws {
        let manager = PsychoCopyManager()
        manager.toggleMultiCopyMode()
        let types: [ContentType] = [.text, .image, .file, .url, .video, .richText]
        for type in types {
            let item = ClipboardItem(contentType: type, contentText: "test", sourceAppName: "Test")
            manager.handleClipboardChange(item)
        }
        #expect(manager.copyQueue.count == types.count)
        for (i, type) in types.enumerated() {
            #expect(manager.copyQueue.items[i].contentType == type)
        }
    }
    @Test(.tags(.psychocopy)) func property6_clearOperationCompleteness() async throws {
        let manager = PsychoCopyManager()
        manager.toggleMultiCopyMode()
        let item1 = ClipboardItem(contentType: .text, contentText: "1", sourceAppName: "Test")
        manager.handleClipboardChange(item1)
        manager.clearQueue()
        #expect(manager.copyQueue.isEmpty)
        #expect(manager.isMultiCopyModeActive) 
    }
    @Test(.tags(.psychocopy)) func property7_visualStateConsistency() async throws {
        let manager = PsychoCopyManager()
        manager.toggleMultiCopyMode()
        let item1 = ClipboardItem(contentType: .text, contentText: "1", sourceAppName: "Test", fileName: "test.txt")
        manager.handleClipboardChange(item1)
        let previewText = manager.copyQueue.items.first?.queuePreviewText()
        #expect(previewText == "1") 
        #expect(manager.copyQueue.count == 1)
    }
    @Test(.tags(.psychocopy)) func property8_memoryEfficiencyBounds() async throws {
        var queue = CopyQueue()
        let data = Data(repeating: 0, count: 10_000)
        let item = ClipboardItem(contentType: .image, sourceAppName: "Test", localData: data)
        queue.enqueue(item)
        let footprint = queue.memoryFootprint()
        #expect(footprint == Int64(10_000))
    }
    @Test(.tags(.psychocopy)) func property9_clipboardQueueIntegration() async throws {
        let manager = PsychoCopyManager()
        manager.toggleMultiCopyMode()
        let item1 = ClipboardItem(contentType: .text, contentText: "1", sourceAppName: "Test")
        manager.handleClipboardChange(item1)
        #expect(manager.copyQueue.preview.first?.contentText == "1")
        #expect(manager.copyQueue.preview.first?.queuePosition == 0)
    }
    @Test(.tags(.psychocopy)) func property10_emptyQueueRecoveryAndContinuation() async throws {
        let manager = PsychoCopyManager()
        manager.toggleMultiCopyMode()
        manager.clearQueue()
        #expect(manager.copyQueue.isEmpty)
        #expect(manager.isMultiCopyModeActive) 
    }
}

