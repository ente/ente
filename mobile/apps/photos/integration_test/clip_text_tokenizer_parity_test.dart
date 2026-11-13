import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";
import "package:photos/src/rust/api/ml_indexing_api.dart" as rust_ml;
import "package:photos/src/rust/frb_generated.dart";

const _kClipTotalTokens = 77;
const _kClipBpeMergeLineCount = 49152 - 256 - 2;

// Reference prefixes generated with MobileCLIP's Python tokenizer path:
// open-clip-torch v2.20.0 SimpleTokenizer (context_length=77) on the same
// synthetic BPE vocab produced by _buildSyntheticClipVocab().
const _kExpectedMobileClipPythonTokenPrefixes = <String, List<int>>{
  "hello world": [49406, 71, 68, 75, 75, 334, 86, 78, 81, 75, 323, 49407],
  "can't won't i'd we're": [
    49406,
    66,
    64,
    333,
    6,
    339,
    86,
    78,
    333,
    6,
    339,
    328,
    6,
    323,
    86,
    324,
    6,
    81,
    324,
    49407,
  ],
  "multiple    spaces\tand\nlines": [
    49406,
    76,
    84,
    75,
    83,
    72,
    79,
    75,
    324,
    82,
    79,
    64,
    66,
    68,
    338,
    64,
    77,
    323,
    75,
    72,
    77,
    68,
    338,
    49407,
  ],
  "&amp;lt;html&amp;gt; entities &amp;amp; symbols": [
    49406,
    283,
    71,
    83,
    76,
    331,
    285,
    68,
    77,
    83,
    72,
    83,
    72,
    68,
    338,
    261,
    82,
    88,
    76,
    65,
    78,
    75,
    338,
    49407,
  ],
  "numbers 1234567890 and punctuation !!! ???": [
    49406,
    77,
    84,
    76,
    65,
    68,
    81,
    338,
    272,
    273,
    274,
    275,
    276,
    277,
    278,
    279,
    280,
    271,
    64,
    77,
    323,
    79,
    84,
    77,
    66,
    83,
    84,
    64,
    83,
    72,
    78,
    333,
    0,
    0,
    256,
    30,
    30,
    286,
    49407,
  ],
  "long query long query long query long query long query long query long query long query long query long query":
      [
        49406,
        75,
        78,
        77,
        326,
        80,
        84,
        68,
        81,
        344,
        75,
        78,
        77,
        326,
        80,
        84,
        68,
        81,
        344,
        75,
        78,
        77,
        326,
        80,
        84,
        68,
        81,
        344,
        75,
        78,
        77,
        326,
        80,
        84,
        68,
        81,
        344,
        75,
        78,
        77,
        326,
        80,
        84,
        68,
        81,
        344,
        75,
        78,
        77,
        326,
        80,
        84,
        68,
        81,
        344,
        75,
        78,
        77,
        326,
        80,
        84,
        68,
        81,
        344,
        75,
        78,
        77,
        326,
        80,
        84,
        68,
        81,
        344,
        75,
        78,
        77,
        49407,
      ],
  "İstanbul ſtyle Kelvin 1234": [
    49406,
    328,
    136,
    485,
    82,
    83,
    64,
    77,
    65,
    84,
    331,
    129,
    123,
    83,
    88,
    75,
    324,
    74,
    68,
    75,
    85,
    72,
    333,
    272,
    273,
    274,
    275,
    49407,
  ],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await EntePhotosRust.init();
  });

  test("Rust CLIP tokenizer matches MobileCLIP Python tokenizer", () async {
    final tempDir = await Directory.systemTemp.createTemp(
      "clip_tokenizer_parity_",
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final vocabPath = "${tempDir.path}/bpe_simple_vocab_16e6.txt";
    await File(
      vocabPath,
    ).writeAsString(_buildSyntheticClipVocab(), flush: true);

    for (final entry in _kExpectedMobileClipPythonTokenPrefixes.entries) {
      final query = entry.key;
      final rustTokens = await rust_ml.tokenizeClipTextRust(
        text: query,
        vocabPath: vocabPath,
      );

      expect(
        rustTokens.toList(growable: false),
        _padToClipLength(entry.value),
        reason: "Tokenizer mismatch for query: '$query'",
      );
      expect(rustTokens.length, _kClipTotalTokens);
    }

    final whitespaceVariant = await rust_ml.tokenizeClipTextRust(
      text: "multiple    spaces\tand\nlines",
      vocabPath: vocabPath,
    );
    final normalizedWhitespace = await rust_ml.tokenizeClipTextRust(
      text: "multiple spaces and lines",
      vocabPath: vocabPath,
    );
    expect(
      whitespaceVariant.toList(growable: false),
      normalizedWhitespace.toList(growable: false),
      reason: "Expected tab/newline runs to normalize to single spaces",
    );
  });
}

List<int> _padToClipLength(List<int> tokens) {
  assert(tokens.length <= _kClipTotalTokens);
  return [...tokens, ...List<int>.filled(_kClipTotalTokens - tokens.length, 0)];
}

String _buildSyntheticClipVocab() {
  final buffer = StringBuffer("#version: 0.2");
  for (int i = 0; i < _kClipBpeMergeLineCount; i++) {
    buffer.write("\na b");
  }
  return buffer.toString();
}
