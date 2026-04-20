import XCTest
@testable import claudetracker

final class PricingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clear any live rates so these tests exercise the hardcoded fallback table.
        Pricing.setLive([:])
    }

    func testHardcodedOpus47PerMillion() throws {
        let r = try XCTUnwrap(Pricing.rates(for: "claude-opus-4-7"))
        XCTAssertEqual(r.input,      5.00,  accuracy: 0.0001)
        XCTAssertEqual(r.output,     25.00, accuracy: 0.0001)
        XCTAssertEqual(r.cacheWrite, 6.25,  accuracy: 0.0001)
        XCTAssertEqual(r.cacheRead,  0.50,  accuracy: 0.0001)
    }

    func testHardcodedSonnet46() throws {
        let r = try XCTUnwrap(Pricing.rates(for: "claude-sonnet-4-6"))
        XCTAssertEqual(r.input,      3.00,  accuracy: 0.0001)
        XCTAssertEqual(r.output,     15.00, accuracy: 0.0001)
        XCTAssertEqual(r.cacheWrite, 3.75,  accuracy: 0.0001)
        XCTAssertEqual(r.cacheRead,  0.30,  accuracy: 0.0001)
    }

    func testHardcodedHaiku45() throws {
        let r = try XCTUnwrap(Pricing.rates(for: "claude-haiku-4-5"))
        XCTAssertEqual(r.input,  1.00, accuracy: 0.0001)
        XCTAssertEqual(r.output, 5.00, accuracy: 0.0001)
    }

    /// Claude Code reports the model id as "claude-opus-4-7[1m]" when the 1M
    /// context variant is active; that must still resolve to opus-4-7 pricing.
    func testBracketedSuffixStillMatches() throws {
        let r = try XCTUnwrap(Pricing.rates(for: "claude-opus-4-7[1m]"))
        XCTAssertEqual(r.input, 5.00, accuracy: 0.0001)
    }

    /// Opus 4 / 4.1 pricing hasn't changed — make sure we don't bleed the new
    /// lower prices onto the older model family via loose substring matching.
    func testOpus41KeepsOriginalPricing() throws {
        let r = try XCTUnwrap(Pricing.rates(for: "claude-opus-4-1"))
        XCTAssertEqual(r.input,  15.00, accuracy: 0.0001)
        XCTAssertEqual(r.output, 75.00, accuracy: 0.0001)
    }

    func testCostArithmetic() throws {
        let cost = try XCTUnwrap(Pricing.cost(
            modelId: "claude-opus-4-7",
            input: 1_000_000, output: 1_000_000,
            cacheWrite: 0, cacheRead: 0
        ))
        XCTAssertEqual(cost, 30.00, accuracy: 0.001)  // 5 + 25
    }

    func testUnknownModelReturnsNil() {
        XCTAssertNil(Pricing.rates(for: "some-other-model"))
        XCTAssertNil(Pricing.cost(modelId: "some-other-model",
                                   input: 1, output: 1, cacheWrite: 0, cacheRead: 0))
    }

    func testLiveRatesOverrideHardcoded() throws {
        Pricing.setLive([
            "claude-opus-4-7": Pricing.Rates(input: 1, output: 2, cacheWrite: 3, cacheRead: 4)
        ])
        let r = try XCTUnwrap(Pricing.rates(for: "claude-opus-4-7"))
        XCTAssertEqual(r.input,  1, accuracy: 0.0001)
        XCTAssertEqual(r.output, 2, accuracy: 0.0001)
    }

    func testLiveSubstringMatch() throws {
        // Live table keyed on a richer name; query uses the short form.
        Pricing.setLive([
            "us.anthropic.claude-opus-4-7": Pricing.Rates(input: 10, output: 20, cacheWrite: 1, cacheRead: 1)
        ])
        let r = try XCTUnwrap(Pricing.rates(for: "claude-opus-4-7"))
        XCTAssertEqual(r.input, 10, accuracy: 0.0001)
    }
}
