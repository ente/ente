import Foundation
import SwiftParser
import SwiftSyntax

struct Input: Decodable {
    let path: String
    let source: String
}

struct Comment: Encodable {
    let path: String
    let line: Int
    let text: String
}

let inputs = try JSONDecoder().decode(
    [Input].self, from: FileHandle.standardInput.readDataToEndOfFile())
var comments: [Comment] = []
for input in inputs {
    let tree = Parser.parse(source: input.source)
    let locations = SourceLocationConverter(fileName: input.path, tree: tree)
    for token in tree.tokens(viewMode: .sourceAccurate) {
        for (trivia, start) in [
            (token.leadingTrivia, token.position),
            (token.trailingTrivia, token.endPositionBeforeTrailingTrivia),
        ] {
            var position = start
            for piece in trivia {
                switch piece {
                case .lineComment(let text), .blockComment(let text), .docLineComment(let text),
                    .docBlockComment(let text):
                    comments.append(
                        Comment(
                            path: input.path, line: locations.location(for: position).line,
                            text: text))
                default: break
                }
                position = position.advanced(by: piece.sourceLength.utf8Length)
            }
        }
    }
}
FileHandle.standardOutput.write(try JSONEncoder().encode(comments))
