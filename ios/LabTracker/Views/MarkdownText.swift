import SwiftUI

/// Lightweight markdown for the stored AI analyses. The expensive part — parsing
/// each line into an AttributedString — is done once via `parse(_:)` (off the
/// view's render path); the view just lays out precomputed blocks.
struct MarkdownText: View {
    enum Block {
        case header(String, Font)
        case bullet(AttributedString)
        case paragraph(AttributedString)
    }

    let blocks: [Block]

    static func parse(_ text: String) -> [Block] {
        var out: [Block] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("### ") {
                out.append(.header(String(line.dropFirst(4)), .subheadline.bold()))
            } else if line.hasPrefix("## ") {
                out.append(.header(String(line.dropFirst(3)), .headline))
            } else if line.hasPrefix("# ") {
                out.append(.header(String(line.dropFirst(2)), .title3.bold()))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                out.append(.bullet(inline(String(line.dropFirst(2)))))
            } else {
                out.append(.paragraph(inline(line)))
            }
        }
        return out
    }

    private static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .header(text, font):
                    Text(text).font(font).padding(.top, 2)
                case let .bullet(text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(text)
                    }
                    .font(.callout)
                case let .paragraph(text):
                    Text(text).font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
