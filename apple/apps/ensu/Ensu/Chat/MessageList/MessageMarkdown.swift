import Foundation
import Markdown

struct InlineContent: Equatable {
    enum Segment: Equatable {
        case text(AttributedString)
        case math(String)
    }

    var segments: [Segment] = []

    var isEmpty: Bool { segments.isEmpty }

    var hasMath: Bool {
        segments.contains {
            if case .math = $0 { return true }
            return false
        }
    }

    var attributedText: AttributedString {
        segments.reduce(into: AttributedString()) { result, segment in
            if case .text(let text) = segment { result.append(text) }
        }
    }

    func appending(_ text: String) -> Self {
        Self(segments: segments + [.text(AttributedString(text))])
    }

    static func joined(_ items: [Self], separator: String) -> Self {
        var result = Self()
        for (index, item) in items.enumerated() {
            if index > 0 { result = result.appending(separator) }
            result.segments += item.segments
        }
        return result
    }

    var lines: [Self] {
        var result = [Self()]
        for segment in segments {
            switch segment {
            case .math:
                result[result.count - 1].segments.append(segment)
            case .text(let text):
                for (index, line) in text.characters.split(
                    separator: "\n", omittingEmptySubsequences: false
                ).enumerated() {
                    if index > 0 { result.append(Self()) }
                    if !line.isEmpty {
                        result[result.count - 1].segments.append(
                            .text(AttributedString(text[line.startIndex..<line.endIndex])))
                    }
                }
            }
        }
        return result
    }
}

struct MarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case heading(level: Int, text: InlineContent)
        case paragraph(text: InlineContent)
        case blockquote(text: InlineContent)
        case code(text: String)
        case math(text: String)
        case list(items: [InlineContent])
        case divider
    }

    let id: Int
    let kind: Kind
}

struct MarkdownParser {
    private var math: [String: String] = [:]

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var nextId = 0

        func append(_ kind: MarkdownBlock.Kind) {
            blocks.append(MarkdownBlock(id: nextId, kind: kind))
            nextId += 1
        }

        let segments = text.components(separatedBy: "```")

        for (index, segment) in segments.enumerated() {
            if index % 2 == 1 {
                let code = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty {
                    append(.code(text: code))
                }
                continue
            }

            for piece in splitByMathBlocks(segment) {
                switch piece {
                case .math(let latex):
                    let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        append(.math(text: trimmed))
                    }
                case .markdown(let markdown):
                    parseMarkdownBlocks(markdown).forEach { append($0) }
                }
            }
        }

        return blocks
    }

    private enum Segment {
        case markdown(String)
        case math(String)
    }

    private static func splitByMathBlocks(_ text: String) -> [Segment] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var segments: [Segment] = []
        var markdownLines: [String] = []
        var mathLines: [String] = []
        var mathEndDelimiter: String? = nil

        func flushMarkdown() {
            if !markdownLines.isEmpty {
                segments.append(.markdown(markdownLines.joined(separator: "\n")))
                markdownLines.removeAll()
            }
        }

        func flushMath() {
            if !mathLines.isEmpty {
                segments.append(.math(mathLines.joined(separator: "\n")))
            }
            mathLines.removeAll()
            mathEndDelimiter = nil
        }

        func startMath(endDelimiter: String, initialContent: String? = nil) {
            flushMarkdown()
            mathEndDelimiter = endDelimiter
            mathLines.removeAll()
            if let initial = initialContent?.trimmingCharacters(in: .whitespacesAndNewlines),
                !initial.isEmpty
            {
                mathLines.append(initial)
            }
        }

        func isBracketMathLine(_ trimmed: String) -> Bool {
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 else {
                return false
            }
            if trimmed.contains("](") || trimmed.contains("]:") {
                return false
            }
            return true
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let endDelimiter = mathEndDelimiter {
                if trimmed == endDelimiter {
                    flushMath()
                    continue
                }
                if endDelimiter != "]" && trimmed.hasSuffix(endDelimiter) {
                    let content = String(trimmed.dropLast(endDelimiter.count)).trimmingCharacters(
                        in: .whitespaces)
                    if !content.isEmpty {
                        mathLines.append(content)
                    }
                    flushMath()
                    continue
                }
                mathLines.append(line)
                continue
            }

            if trimmed == "\\[" || trimmed == "$$" || trimmed == "[" {
                let endDelimiter = trimmed == "\\[" ? "\\]" : (trimmed == "$$" ? "$$" : "]")
                startMath(endDelimiter: endDelimiter)
                continue
            }

            if trimmed.hasPrefix("\\[") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if content.hasSuffix("\\]") {
                    let inner = String(content.dropLast(2)).trimmingCharacters(in: .whitespaces)
                    flushMarkdown()
                    segments.append(.math(inner))
                } else {
                    startMath(endDelimiter: "\\]", initialContent: content)
                }
                continue
            }

            if trimmed.hasPrefix("$$") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if content.hasSuffix("$$") {
                    let inner = String(content.dropLast(2)).trimmingCharacters(in: .whitespaces)
                    flushMarkdown()
                    segments.append(.math(inner))
                } else {
                    startMath(endDelimiter: "$$", initialContent: content)
                }
                continue
            }

            if isBracketMathLine(trimmed) {
                let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(
                    in: .whitespaces)
                flushMarkdown()
                segments.append(.math(inner))
                continue
            }

            markdownLines.append(line)
        }

        if mathEndDelimiter != nil {
            flushMath()
        } else {
            flushMarkdown()
        }

        return segments
    }

    private static func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock.Kind] {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let (document, math) = protectInlineMath(markdown)
        let parser = Self(math: math)
        var parsedBlocks: [MarkdownBlock.Kind] = []
        for child in document.children {
            parsedBlocks.append(contentsOf: parser.blocks(for: child))
        }
        return parsedBlocks
    }

    private func blocks(for markup: Markup) -> [MarkdownBlock.Kind] {
        switch markup {
        case let heading as Heading:
            let text = renderInlineChildren(heading)
            guard !text.isEmpty else { return [] }
            let level = max(1, min(heading.level, 3))
            return [.heading(level: level, text: text)]
        case let paragraph as Paragraph:
            let text = renderInlineChildren(paragraph)
            guard !text.isEmpty else { return [] }
            return [.paragraph(text: text)]
        case let blockQuote as BlockQuote:
            let text = renderBlockQuote(blockQuote)
            guard !text.isEmpty else { return [] }
            return [.blockquote(text: text)]
        case let codeBlock as CodeBlock:
            let code = codeBlock.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { return [] }
            return [.code(text: code)]
        case let html as HTMLBlock:
            return [.paragraph(text: InlineContent().appending(html.rawHTML))]
        case _ as ThematicBreak:
            return [.divider]
        case let orderedList as OrderedList:
            let items = orderedList.children.compactMap { $0 as? ListItem }.map(renderListItem)
                .filter { !$0.isEmpty }
            return items.isEmpty ? [] : [.list(items: items)]
        case let unorderedList as UnorderedList:
            let items = unorderedList.children.compactMap { $0 as? ListItem }.map(renderListItem)
                .filter { !$0.isEmpty }
            return items.isEmpty ? [] : [.list(items: items)]
        default:
            var nestedBlocks: [MarkdownBlock.Kind] = []
            for child in markup.children {
                nestedBlocks.append(contentsOf: blocks(for: child))
            }
            return nestedBlocks
        }
    }

    private func renderBlockQuote(_ quote: BlockQuote) -> InlineContent {
        var parts: [InlineContent] = []
        for child in quote.children {
            if let html = child as? HTMLBlock {
                parts.append(InlineContent().appending(html.rawHTML))
                continue
            }
            if let paragraph = child as? Paragraph {
                let text = renderInlineChildren(paragraph)
                if !text.isEmpty {
                    parts.append(text)
                }
                continue
            }
            if let heading = child as? Heading {
                let text = renderInlineChildren(heading)
                if !text.isEmpty {
                    parts.append(text)
                }
                continue
            }
            if let list = child as? OrderedList {
                let items = list.children.compactMap { $0 as? ListItem }.map(renderListItem).filter
                { !$0.isEmpty }
                if !items.isEmpty {
                    parts.append(InlineContent.joined(items, separator: "\n"))
                }
                continue
            }
            if let list = child as? UnorderedList {
                let items = list.children.compactMap { $0 as? ListItem }.map(renderListItem).filter
                { !$0.isEmpty }
                if !items.isEmpty {
                    parts.append(InlineContent.joined(items, separator: "\n"))
                }
                continue
            }
        }
        return InlineContent.joined(parts, separator: "\n")
    }

    private func renderListItem(_ item: ListItem) -> InlineContent {
        var parts: [InlineContent] = []
        for child in item.children {
            if let html = child as? HTMLBlock {
                parts.append(InlineContent().appending(html.rawHTML))
                continue
            }
            if let paragraph = child as? Paragraph {
                let text = renderInlineChildren(paragraph)
                if !text.isEmpty {
                    parts.append(text)
                }
                continue
            }
            if let list = child as? OrderedList {
                let items = list.children.compactMap { $0 as? ListItem }.map(renderListItem).filter
                { !$0.isEmpty }
                if !items.isEmpty {
                    parts.append(InlineContent.joined(items, separator: "\n"))
                }
                continue
            }
            if let list = child as? UnorderedList {
                let items = list.children.compactMap { $0 as? ListItem }.map(renderListItem).filter
                { !$0.isEmpty }
                if !items.isEmpty {
                    parts.append(InlineContent.joined(items, separator: "\n"))
                }
                continue
            }
        }
        return InlineContent.joined(parts, separator: "\n")
    }

    private func renderInlineChildren(
        _ markup: Markup, attributes: AttributeContainer = AttributeContainer()
    ) -> InlineContent {
        InlineContent(
            segments: markup.children.flatMap {
                renderInline(from: $0, attributes: attributes).segments
            })
    }

    private func renderInline(from markup: Markup, attributes: AttributeContainer) -> InlineContent
    {
        if let image = markup as? Markdown.Image, let source = image.source,
            let latex = math[source]
        {
            return InlineContent(segments: [.math(latex)])
        }
        var attributes = attributes
        var intent = attributes.inlinePresentationIntent ?? []
        switch markup {
        case let text as Markdown.Text:
            return InlineContent(segments: [
                .text(AttributedString(text.string, attributes: attributes))
            ])
        case let html as InlineHTML:
            return InlineContent(segments: [
                .text(AttributedString(html.rawHTML, attributes: attributes))
            ])
        case is SoftBreak:
            return InlineContent(segments: [.text(AttributedString(" ", attributes: attributes))])
        case is LineBreak:
            return InlineContent(segments: [.text(AttributedString("\n", attributes: attributes))])
        case let code as InlineCode:
            intent.insert(.code)
            attributes.inlinePresentationIntent = intent
            return InlineContent(segments: [
                .text(AttributedString(code.code, attributes: attributes))
            ])
        case is Emphasis:
            intent.insert(.emphasized)
        case is Strong:
            intent.insert(.stronglyEmphasized)
        case is Strikethrough:
            intent.insert(.strikethrough)
        case let link as Markdown.Link:
            attributes.link = link.destination.flatMap(URL.init(string:))
        default:
            break
        }
        attributes.inlinePresentationIntent = intent
        return renderInlineChildren(markup, attributes: attributes)
    }
}

private func protectInlineMath(_ markdown: String) -> (Document, [String: String]) {
    let document = Document(parsing: markdown)
    var textRanges: [SourceRange] = []
    func collectTextRanges(_ markup: Markup) {
        if let text = markup as? Markdown.Text, let range = text.range {
            textRanges.append(range)
        } else if (markup as? Markdown.Link)?.isAutolink != true {
            for child in markup.children { collectTextRanges(child) }
        }
    }
    collectTextRanges(document)

    let bytes = Array(markdown.utf8)
    let prefix = UUID().uuidString
    var protected: [UInt8] = []
    var math: [String: String] = [:]
    var location = SourceLocation(line: 1, column: 1, source: nil)
    var rangeIndex = 0
    var index = 0
    while index < bytes.count {
        while rangeIndex < textRanges.count && textRanges[rangeIndex].upperBound <= location {
            rangeIndex += 1
        }
        let isText =
            rangeIndex < textRanges.count && textRanges[rangeIndex].contains(location)
        if isText, let match = inlineMathMatch(bytes, at: index) {
            let id = "\(prefix)-\(math.count)"
            math[id] = match.latex
            // Image nodes keep math opaque while Markdown parses the surrounding formatting.
            protected += "![](\(id))".utf8
            location.column += match.end - index
            index = match.end
        } else if bytes[index] == UInt8(ascii: "\\") && index + 1 < bytes.count
            && bytes[index + 1] != UInt8(ascii: "\n") && bytes[index + 1] != UInt8(ascii: "\r")
        {
            protected += bytes[index...index + 1]
            index += 2
            location.column += 2
        } else {
            protected.append(bytes[index])
            if bytes[index] == UInt8(ascii: "\r")
                || (bytes[index] == UInt8(ascii: "\n")
                    && (index == 0 || bytes[index - 1] != UInt8(ascii: "\r")))
            {
                location.line += 1
                location.column = 1
            } else if bytes[index] != UInt8(ascii: "\n") {
                location.column += 1
            }
            index += 1
        }
    }
    guard !math.isEmpty else { return (document, math) }
    let rewritten = Document(parsing: String(decoding: protected, as: UTF8.self))
    var recovered: Set<String> = []
    func literalContent(_ markup: Markup) -> [String] {
        var content: [String] = []
        switch markup {
        case let image as Markdown.Image:
            if let source = image.source, math[source] != nil {
                recovered.insert(source)
                return []
            }
            content = ["image", image.source ?? "", image.title ?? ""]
        case let link as Markdown.Link:
            content = ["link", link.destination ?? "", link.title ?? ""]
        case let code as InlineCode:
            content = ["code", code.code]
        case let code as CodeBlock:
            content = ["code block", code.code]
        case let html as InlineHTML:
            content = ["html", html.rawHTML]
        case let html as HTMLBlock:
            content = ["html block", html.rawHTML]
        default:
            break
        }
        return content + markup.children.flatMap(literalContent)
    }
    // Source ranges can drift on continuation lines.
    guard literalContent(document) == literalContent(rewritten), recovered.count == math.count
    else {
        return (Document(Paragraph(Markdown.Text(markdown))), [:])
    }
    return (rewritten, math)
}

private func inlineMathMatch(_ bytes: [UInt8], at start: Int) -> (latex: String, end: Int)? {
    let parenthesized =
        bytes[start] == UInt8(ascii: "\\") && start + 1 < bytes.count
        && bytes[start + 1] == UInt8(ascii: "(")
    if !parenthesized {
        guard bytes[start] == UInt8(ascii: "$"),
            (start == 0 || bytes[start - 1] != UInt8(ascii: "$")),
            start + 1 < bytes.count, bytes[start + 1] != UInt8(ascii: "$")
        else { return nil }
    }
    let contentStart = start + (parenthesized ? 2 : 1)
    var index = contentStart
    while index < bytes.count {
        if bytes[index] == UInt8(ascii: "\n") || bytes[index] == UInt8(ascii: "\r") { return nil }
        if parenthesized && bytes[index] == UInt8(ascii: "\\") && index + 1 < bytes.count
            && bytes[index + 1] == UInt8(ascii: ")")
        {
            guard index > contentStart else { return nil }
            return (String(decoding: bytes[contentStart..<index], as: UTF8.self), index + 2)
        }
        if bytes[index] == UInt8(ascii: "\\") {
            index += 2
            continue
        }
        if !parenthesized && bytes[index] == UInt8(ascii: "$") {
            guard index > contentStart,
                index + 1 == bytes.count || bytes[index + 1] != UInt8(ascii: "$")
            else {
                return nil
            }
            return (String(decoding: bytes[contentStart..<index], as: UTF8.self), index + 1)
        }
        index += 1
    }
    return nil
}
