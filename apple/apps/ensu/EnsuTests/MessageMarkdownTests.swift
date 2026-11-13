import Foundation
import XCTest
@testable import Ensu

final class MessageMarkdownTests: XCTestCase {
    func testInlineMathPreservesEscapesAndCode() {
        let cases: [(String, [String], String)] = [
            (#"Inline: \(a+b\)."#, ["a+b"], "Inline: ."),
            (#"Escaped: \$5 and \$10; $x^2$."#, ["x^2"], "Escaped: $5 and $10; ."),
            (#"Empty: \(\); $$; before $$x$$ after."#, [], "Empty: (); $$; before $$x$$ after."),
            (#"Code: `$x$` and `\(y\)`; $z$."#, ["z"], #"Code: $x$ and \(y\); ."#),
            (#"Code: `` `$x$` ``; \(z\)."#, ["z"], "Code: `$x$`; ."),
            (#"Math: $\frac{a_b}{c_d} + *x*$."#, [#"\frac{a_b}{c_d} + *x*"#], "Math: ."),
            (#"Escaped opener: \\(x\\); $y$."#, ["y"], #"Escaped opener: \(x\); ."#),
            (#"Unicode: café 🙂 \(α + β\), $γ$."#, ["α + β", "γ"], "Unicode: café 🙂 , ."),
            (#"Streaming: \(a+b"#, [], "Streaming: (a+b"),
            (#"Streaming: $a+b"#, [], "Streaming: $a+b"),
            (#"Unclosed code: `$x$."#, ["x"], "Unclosed code: `."),
            (#"Literal tick: \`$x$."#, ["x"], "Literal tick: `."),
            (#"URL: <https://example.com/$a$>; $x$."#, ["x"], "URL: https://example.com/$a$; ."),
            ("a $x$\n b $y$", ["x", "y"], "a  b "),
            ("a $x$\r\n b $y$", ["x", "y"], "a  b "),
            ("a $x$\n   b $y$", ["x"], "a  b $y$"),
            ("a $x$\\\nb $y$", ["x"], "a \nb $y$"),
            ("![0]() and $x$", ["x"], "0 and "),
            ("<b>$x$</b> t", ["x"], "<b></b> t"),
            ("Use <v> here.", [], "Use <v> here."),
        ]
        for (source, math, text) in cases {
            let inline = paragraph(source)
            XCTAssertEqual(mathSpans(inline), math, source)
            XCTAssertEqual(String(inline.attributedText.characters), text, source)
        }
    }

    func testCodeInsideEmphasisRemainsLiteral() {
        let inline = paragraph(#"**bold `$x$` and *italic `\(y\)`***; $z$."#)
        XCTAssertEqual(mathSpans(inline), ["z"])
        XCTAssertEqual(String(inline.attributedText.characters), #"bold $x$ and italic \(y\); ."#)
        let code = inline.attributedText.runs.filter {
            $0.inlinePresentationIntent?.contains(.code) == true
        }
        XCTAssertEqual(code.count, 2)
        XCTAssertTrue(
            code.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(code.last?.inlinePresentationIntent?.contains(.emphasized) == true)
    }

    func testUnsafeMathRewritePreservesOriginalText() {
        let source = "a $x$\n   b `$y$` and $z$"
        let inline = paragraph(source)
        XCTAssertEqual(String(inline.attributedText.characters), source)
        XCTAssertTrue(mathSpans(inline).isEmpty)
    }

    func testHTMLBlocksRemainLiteral() {
        let html = "<div>\nhello $x$\n</div>\n"
        let sources = [
            html,
            "> <div>\n> hello $x$\n> </div>",
            "- <div>\n  hello $x$\n  </div>",
        ]
        for source in sources {
            let blocks = MarkdownParser.parse(source)
            XCTAssertEqual(blocks.count, 1)
            guard let block = blocks.first else { continue }
            let content: InlineContent
            switch block.kind {
            case .paragraph(let text), .blockquote(let text):
                content = text
            case .list(let items):
                XCTAssertEqual(items.count, 1)
                content = InlineContent.joined(items, separator: "")
            default:
                XCTFail("Unexpected block kind")
                continue
            }
            XCTAssertEqual(String(content.attributedText.characters), html)
            XCTAssertFalse(content.hasMath)
        }
        let details = "<details>summary</details>"
        XCTAssertEqual(String(paragraph(details).attributedText.characters), details + "\n")
    }

    func testMathInBlocksAndLinkLabels() {
        let blocks = MarkdownParser.parse(
            "# Heading \\(x\\)\n\n- Item $y$\n\n> Quote \\(z\\)\ncontinued $q$\n\n$$\\frac{1}{2}$$")
        XCTAssertEqual(blocks.count, 4)
        guard blocks.count == 4, case .heading(_, let heading) = blocks[0].kind,
            case .list(let items) = blocks[1].kind,
            case .blockquote(let quote) = blocks[2].kind,
            case .math(let display) = blocks[3].kind
        else { return XCTFail("Unexpected block kinds") }
        XCTAssertEqual(mathSpans(heading), ["x"])
        XCTAssertEqual(items.map(mathSpans), [["y"]])
        XCTAssertEqual(mathSpans(quote), ["z", "q"])
        XCTAssertEqual(display, #"\frac{1}{2}"#)

        let inline = paragraph(#"See [math $x$](https://example.com/$a$) and **bold**."#)
        XCTAssertEqual(mathSpans(inline), ["x"])
        XCTAssertTrue(
            inline.attributedText.runs.contains {
                $0.link?.absoluteString == "https://example.com/$a$"
            })

        let reference = paragraph("See [link][ref] and $x$.\n\n[ref]: https://example.com/$a$")
        XCTAssertEqual(mathSpans(reference), ["x"])
        XCTAssertTrue(
            reference.attributedText.runs.contains {
                $0.link?.absoluteString == "https://example.com/$a$"
            })
    }

    private func paragraph(_ source: String) -> InlineContent {
        let blocks = MarkdownParser.parse(source)
        guard blocks.count == 1, case .paragraph(let inline) = blocks[0].kind else {
            XCTFail("Expected one paragraph: \(source)")
            return InlineContent()
        }
        return inline
    }

    private func mathSpans(_ inline: InlineContent) -> [String] {
        inline.segments.compactMap {
            if case .math(let latex) = $0 { return latex }
            return nil
        }
    }
}
