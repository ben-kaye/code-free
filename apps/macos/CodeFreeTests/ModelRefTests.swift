import XCTest
@testable import CodeFree

final class ModelRefTests: XCTestCase {
    func testEncodeWithEffort() {
        XCTAssertEqual(ModelRef.encode(modelId: "grok-4.5", effortId: "high"), "grok-4.5#high")
    }

    func testEncodeWithoutEffort() {
        XCTAssertEqual(ModelRef.encode(modelId: "grok-4.5", effortId: nil), "grok-4.5")
        XCTAssertEqual(ModelRef.encode(modelId: "grok-4.5", effortId: ""), "grok-4.5")
    }

    func testParseComposite() {
        let parsed = ModelRef.parse("grok-4.5#medium")
        XCTAssertEqual(parsed.modelId, "grok-4.5")
        XCTAssertEqual(parsed.effortId, "medium")
    }

    func testParsePlain() {
        let parsed = ModelRef.parse("grok-4.5")
        XCTAssertEqual(parsed.modelId, "grok-4.5")
        XCTAssertNil(parsed.effortId)
    }

    func testModelSelectionLabel() {
        let model = ModelInfo(
            id: "grok-4.5",
            name: "Grok 4.5",
            reasoningEfforts: [
                ReasoningEffortInfo(id: "low", label: "Low", isDefault: false),
                ReasoningEffortInfo(id: "high", label: "High", isDefault: true),
            ],
            defaultReasoningEffort: "high"
        )
        XCTAssertEqual(model.selectionLabel(effortId: "high"), "Grok 4.5 · High")
        XCTAssertEqual(model.preferredEffortId, "high")
        XCTAssertTrue(model.supportsReasoning)
    }
}
