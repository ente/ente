import XCTest
@testable import Ensu

private final class GenerateEventCollector: LlmGenerationEventCallback {
    private(set) var events: [LlmGenerationEvent] = []

    func onEvent(event: LlmGenerationEvent) {
        events.append(event)
    }

    var hasDone: Bool {
        events.contains { event in
            if case .done = event { return true }
            return false
        }
    }

    var textOutput: String {
        events.compactMap { event in
            if case let .text(_, text, _) = event { return text }
            return nil
        }.joined()
    }
}

final class LlmIntegrationTests: XCTestCase {
    func testInitBackend() throws {
        try llmInitBackend()
    }

    func testGenerateChatStreamWhenModelProvided() throws {
        let modelPath = try requiredEnv("ENSU_TEST_MODEL")

        try llmInitBackend()

        let model = try LlmModel.load(
            params: LlmModelLoadParams(
                modelPath: modelPath,
                nGpuLayers: nil,
                useMmap: nil,
                useMlock: nil
            )
        )

        let context = try model.newContext(
            params: LlmContextParams(contextSize: 2048, nThreads: nil, nBatch: nil)
        )

        let request = LlmChatRequest(
            messages: [
                LlmChatMessage(role: "system", content: "You are a helpful assistant."),
                LlmChatMessage(role: "user", content: "Say hello in one short sentence.")
            ],
            templateOverride: nil,
            addAssistant: true,
            imagePaths: nil,
            mmprojPath: nil,
            mediaMarker: nil,
            maxTokens: 24,
            temperature: 0.7,
            topP: 0.9,
            topK: nil,
            repeatPenalty: nil,
            frequencyPenalty: nil,
            presencePenalty: nil,
            seed: 42,
            stopSequences: nil,
            grammar: nil
        )

        let collector = GenerateEventCollector()
        let summary = try context.generateChatStream(request: request, callback: collector)

        XCTAssertGreaterThan(summary.jobId, 0)
        XCTAssertTrue(collector.hasDone)
        XCTAssertFalse(collector.textOutput.isEmpty)
    }

    func testGenerateChatStreamWithImageWhenProvided() throws {
        let modelPath = try requiredEnv("ENSU_TEST_MODEL")
        let mmprojPath = try requiredEnv("ENSU_TEST_MMPROJ")
        let imagePath = try requiredEnv("ENSU_TEST_IMAGE")

        try llmInitBackend()

        let model = try LlmModel.load(
            params: LlmModelLoadParams(
                modelPath: modelPath,
                nGpuLayers: nil,
                useMmap: nil,
                useMlock: nil
            )
        )

        let context = try model.newContext(
            params: LlmContextParams(contextSize: 2048, nThreads: nil, nBatch: nil)
        )

        let request = LlmChatRequest(
            messages: [
                LlmChatMessage(role: "system", content: "You are a helpful assistant."),
                LlmChatMessage(role: "user", content: "What color is the car? Answer in one word.")
            ],
            templateOverride: nil,
            addAssistant: true,
            imagePaths: [imagePath],
            mmprojPath: mmprojPath,
            mediaMarker: nil,
            maxTokens: 24,
            temperature: 0.2,
            topP: 0.9,
            topK: nil,
            repeatPenalty: nil,
            frequencyPenalty: nil,
            presencePenalty: nil,
            seed: 42,
            stopSequences: nil,
            grammar: nil
        )

        let collector = GenerateEventCollector()
        let summary = try context.generateChatStream(request: request, callback: collector)

        XCTAssertGreaterThan(summary.jobId, 0)
        XCTAssertTrue(collector.hasDone)
        XCTAssertFalse(collector.textOutput.isEmpty)
    }

    private func requiredEnv(_ keys: String...) throws -> String {
        let env = ProcessInfo.processInfo.environment
        if let value = keys.compactMap({ env[$0] }).first(where: { !$0.isEmpty }) {
            return value
        }

        throw XCTSkip("Set one of \(keys.joined(separator: ", ")) to run this test.")
    }
}
