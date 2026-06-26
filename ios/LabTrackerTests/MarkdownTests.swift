import Testing
@testable import LabTracker

struct MarkdownTests {
    @Test func parsesHeadersBulletsAndParagraphs() {
        let blocks = MarkdownText.parse("## Title\n\nA paragraph.\n- one\n- two")
        #expect(blocks.count == 4) // header, paragraph, 2 bullets (blank line skipped)

        guard case .header = blocks[0] else { Issue.record("expected header"); return }
        guard case .paragraph = blocks[1] else { Issue.record("expected paragraph"); return }
        guard case .bullet = blocks[2] else { Issue.record("expected bullet"); return }
        guard case .bullet = blocks[3] else { Issue.record("expected bullet"); return }
    }

    @Test func skipsBlankLines() {
        #expect(MarkdownText.parse("\n\n  \n").isEmpty)
    }

    @Test func headerLevels() {
        let blocks = MarkdownText.parse("# H1\n## H2\n### H3")
        #expect(blocks.count == 3)
        for block in blocks {
            guard case .header = block else { Issue.record("expected header"); return }
        }
    }
}
