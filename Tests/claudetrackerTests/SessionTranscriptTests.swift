import XCTest
@testable import claudetracker

final class SessionTranscriptTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Pricing.setLive([:])
    }

    /// Minimal synthetic transcript covering: assistant message with usage
    /// (both 5m and 1h cache writes), a tool_use block with a Write file_path
    /// (should be captured in filesTouched), and a Read (should count in
    /// toolCounts but not in filesTouched since Read doesn't write).
    private let fixture = """
{"type":"user","sessionId":"sess-fix","cwd":"/tmp/proj","timestamp":"2026-04-20T09:00:00Z","message":{"role":"user","content":"hello"}}
{"type":"assistant","sessionId":"sess-fix","cwd":"/tmp/proj","timestamp":"2026-04-20T09:00:05Z","message":{"id":"msg-1","model":"claude-opus-4-7","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"/tmp/proj/a.swift","content":"x"}},{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/tmp/proj/b.swift"}}],"usage":{"input_tokens":500,"output_tokens":300,"cache_creation_input_tokens":1000,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":1000,"ephemeral_1h_input_tokens":0}}}}
{"type":"user","sessionId":"sess-fix","cwd":"/tmp/proj","timestamp":"2026-04-20T09:10:00Z","message":{"role":"user","content":"again"}}
{"type":"assistant","sessionId":"sess-fix","cwd":"/tmp/proj","timestamp":"2026-04-20T09:10:04Z","message":{"id":"msg-2","model":"claude-opus-4-7","role":"assistant","content":[{"type":"tool_use","id":"t3","name":"Edit","input":{"file_path":"/tmp/proj/a.swift"}}],"usage":{"input_tokens":200,"output_tokens":100,"cache_creation_input_tokens":500,"cache_read_input_tokens":800,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":500}}}}
"""

    private func writeFixtureToDisk() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ct-transcript-\(UUID().uuidString).jsonl")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testTranscriptExtractsCoreFacts() throws {
        let url = try writeFixtureToDisk()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = SessionTranscriptParser.parse(jsonlURL: url)
        XCTAssertNotNil(t)
        let transcript = t!

        XCTAssertEqual(transcript.sessionId, "sess-fix")
        XCTAssertEqual(transcript.cwd, "/tmp/proj")
        XCTAssertEqual(transcript.userMessageCount, 2)
        XCTAssertEqual(transcript.assistantMessageCount, 2)

        // Tool counts: Write + Read + Edit → 1 each.
        XCTAssertEqual(transcript.toolCounts["Write"], 1)
        XCTAssertEqual(transcript.toolCounts["Read"],  1)
        XCTAssertEqual(transcript.toolCounts["Edit"],  1)

        // Only file-writing tools contribute to filesTouched; the file is deduped
        // across Write then Edit, so exactly one path.
        XCTAssertEqual(transcript.filesTouched, ["/tmp/proj/a.swift"])

        // Usage: two assistant messages summed.
        let total = transcript.totalBucket
        XCTAssertEqual(total.inputTokens, 700)
        XCTAssertEqual(total.outputTokens, 400)
        XCTAssertEqual(total.cacheWriteTokens, 1500)
        XCTAssertEqual(total.cacheReadTokens, 800)

        // Two distinct hours (09:00, 09:10 map to same hour → one HourlyBucket).
        XCTAssertEqual(transcript.hourly.count, 1)
        XCTAssertEqual(transcript.hourly.first?.bucket.totalTokens, 3400)
    }
}
