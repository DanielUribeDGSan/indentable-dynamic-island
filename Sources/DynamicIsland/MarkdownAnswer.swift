import AppKit
import SwiftUI

enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(Int, String)
    case bullets([String])
    case numbers([String])
    case code(String, String)
    case rule
}

func markdownBlocks(_ source: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = source.components(separatedBy: "\n")
    var index = 0
    var paragraph: [String] = []

    func flushParagraph() {
        let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            blocks.append(.paragraph(text))
        }
        paragraph.removeAll()
    }

    while index < lines.count {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            flushParagraph()
            let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            index += 1
            var code: [String] = []
            while index < lines.count {
                let row = lines[index].trimmingCharacters(in: .whitespaces)
                if row.hasPrefix("```") { break }
                code.append(lines[index])
                index += 1
            }
            if index < lines.count { index += 1 }
            blocks.append(.code(language, code.joined(separator: "\n")))
            continue
        }
        if trimmed.isEmpty {
            flushParagraph()
            index += 1
            continue
        }
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            flushParagraph()
            blocks.append(.rule)
            index += 1
            continue
        }
        if let heading = headingParts(trimmed) {
            flushParagraph()
            blocks.append(.heading(heading.0, heading.1))
            index += 1
            continue
        }
        if bulletText(trimmed) != nil {
            flushParagraph()
            var items: [String] = []
            while index < lines.count, let item = bulletText(lines[index].trimmingCharacters(in: .whitespaces)) {
                items.append(item)
                index += 1
            }
            blocks.append(.bullets(items))
            continue
        }
        if numberedText(trimmed) != nil {
            flushParagraph()
            var items: [String] = []
            while index < lines.count, let item = numberedText(lines[index].trimmingCharacters(in: .whitespaces)) {
                items.append(item)
                index += 1
            }
            blocks.append(.numbers(items))
            continue
        }
        paragraph.append(lines[index])
        index += 1
    }
    flushParagraph()
    return blocks
}

func markdownAnswerHeight(_ source: String, width: CGFloat) -> CGFloat {
    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
    let body = NSFont.systemFont(ofSize: 13, weight: .regular)
    let title = NSFont.systemFont(ofSize: 15, weight: .semibold)
    var height: CGFloat = 8
    for block in markdownBlocks(source) {
        switch block {
        case .paragraph(let text):
            height += measuredBlock(plainInline(text), font: body, width: width) + 8
        case .heading(let level, let text):
            let font = level <= 2 ? title : NSFont.systemFont(ofSize: 13, weight: .semibold)
            height += measuredBlock(plainInline(text), font: font, width: width) + 8
        case .bullets(let items), .numbers(let items):
            for item in items {
                height += measuredBlock(plainInline(item), font: body, width: width - 16) + 4
            }
            height += 6
        case .code(_, let code):
            let lines = max(1, code.components(separatedBy: "\n").count)
            height += 16 + CGFloat(lines) * 16 + 8
        case .rule:
            height += 12
        }
    }
    return height
}

struct MarkdownAnswer: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(markdownBlocks(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    inline(text, size: 13, weight: .regular, color: IslandPalette.silver)
                case .heading(let level, let text):
                    inline(text, size: level <= 2 ? 15 : 13, weight: .semibold, color: IslandPalette.paper)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(IslandPalette.cloud)
                                inline(item, size: 13, weight: .regular, color: IslandPalette.silver)
                            }
                        }
                    }
                case .numbers(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(offset + 1).")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(IslandPalette.cloud)
                                    .frame(minWidth: 16, alignment: .trailing)
                                inline(item, size: 13, weight: .regular, color: IslandPalette.silver)
                            }
                        }
                    }
                case .code(let language, let code):
                    codeBlock(language: language, code: code)
                case .rule:
                    Rectangle()
                        .fill(IslandPalette.graphite)
                        .frame(height: 1)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private func codeBlock(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(IslandPalette.stone)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }
            Text(code)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(IslandPalette.paper)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .textSelection(.enabled)
        }
        .background(IslandPalette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(IslandPalette.graphite, lineWidth: 1)
        )
    }

    private func inline(_ text: String, size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        Text(inlineAttributed(text, size: size, weight: weight, color: color))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func headingParts(_ line: String) -> (Int, String)? {
    guard line.hasPrefix("#") else { return nil }
    var level = 0
    var rest = line[...]
    while rest.first == "#" && level < 6 {
        level += 1
        rest = rest.dropFirst()
    }
    guard level > 0, rest.first == " " || rest.isEmpty else { return nil }
    let title = rest.drop(while: { $0 == " " })
    return (level, String(title))
}

private func bulletText(_ line: String) -> String? {
    for marker in ["- ", "* ", "• ", "+ "] where line.hasPrefix(marker) {
        return String(line.dropFirst(marker.count))
    }
    return nil
}

private func numberedText(_ line: String) -> String? {
    var digits = 0
    var rest = line[...]
    while let first = rest.first, first.isNumber {
        digits += 1
        rest = rest.dropFirst()
        if digits > 3 { return nil }
    }
    guard digits > 0, rest.first == "." || rest.first == ")" else { return nil }
    rest = rest.dropFirst()
    guard rest.first == " " else { return nil }
    return String(rest.dropFirst())
}

private func plainInline(_ text: String) -> String {
    var output = ""
    output.reserveCapacity(text.count)
    var index = text.startIndex
    while index < text.endIndex {
        if text[index...].hasPrefix("**") || text[index...].hasPrefix("__") {
            index = text.index(index, offsetBy: 2)
            continue
        }
        let character = text[index]
        if character == "*" || character == "_" || character == "`" {
            index = text.index(after: index)
            continue
        }
        output.append(character)
        index = text.index(after: index)
    }
    return output
}

private func inlineAttributed(_ text: String, size: CGFloat, weight: Font.Weight, color: Color) -> AttributedString {
    var result = AttributedString()
    var rest = text[...]
    while !rest.isEmpty {
        if rest.hasPrefix("**") || rest.hasPrefix("__") {
            let marker = rest.hasPrefix("**") ? "**" : "__"
            let after = rest.dropFirst(marker.count)
            if let range = after.range(of: marker) {
                var piece = inlineAttributed(String(after[..<range.lowerBound]), size: size, weight: .semibold, color: IslandPalette.paper)
                piece.font = .system(size: size, weight: .semibold)
                result += piece
                rest = after[range.upperBound...]
                continue
            }
            rest = after
            continue
        }
        if rest.hasPrefix("`") {
            let after = rest.dropFirst()
            if let end = after.firstIndex(of: "`") {
                var piece = AttributedString(String(after[..<end]))
                piece.font = .system(size: max(11, size - 1), weight: .medium, design: .monospaced)
                piece.foregroundColor = IslandPalette.paper
                piece.backgroundColor = IslandPalette.ink
                result += piece
                rest = after[after.index(after: end)...]
                continue
            }
            rest = after
            continue
        }
        if rest.hasPrefix("*") || rest.hasPrefix("_") {
            let marker = String(rest.prefix(1))
            let after = rest.dropFirst()
            if let range = after.range(of: marker), !range.isEmpty, after[..<range.lowerBound].contains(where: { !$0.isWhitespace }) {
                var piece = inlineAttributed(String(after[..<range.lowerBound]), size: size, weight: weight, color: color)
                piece.font = .system(size: size, weight: weight).italic()
                result += piece
                rest = after[range.upperBound...]
                continue
            }
        }
        let next = rest.firstIndex(where: { $0 == "*" || $0 == "_" || $0 == "`" }) ?? rest.endIndex
        let slice = next == rest.startIndex ? rest.prefix(1) : rest[..<next]
        var plain = AttributedString(String(slice))
        plain.font = .system(size: size, weight: weight)
        plain.foregroundColor = color
        result += plain
        rest = rest[slice.endIndex...]
    }
    return result
}

private func measuredBlock(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let rect = (text as NSString).boundingRect(
        with: NSSize(width: max(40, width), height: 4_000),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font]
    )
    return ceil(rect.height)
}
