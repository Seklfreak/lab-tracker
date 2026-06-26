import SwiftUI

/// Lightweight markdown renderer for the stored AI analyses: headers, bullets,
/// and inline emphasis (bold/italic/links via AttributedString). Avoids pulling
/// in a markdown dependency for the handful of block types the analyses use.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, raw in
                row(for: raw.trimmingCharacters(in: .whitespaces))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lines: [String] { text.components(separatedBy: "\n") }

    @ViewBuilder private func row(for line: String) -> some View {
        if line.hasPrefix("### ") {
            Text(line.dropFirst(4)).font(.subheadline.bold()).padding(.top, 2)
        } else if line.hasPrefix("## ") {
            Text(line.dropFirst(3)).font(.headline).padding(.top, 4)
        } else if line.hasPrefix("# ") {
            Text(line.dropFirst(2)).font(.title3.bold()).padding(.top, 4)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                Text(inline(String(line.dropFirst(2)))).font(.callout)
            }
        } else if line.isEmpty {
            EmptyView()
        } else {
            Text(inline(line)).font(.callout)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}
