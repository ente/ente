import assert from "node:assert/strict";
import { check, parse } from "./check.mjs";

const suppressions = [
    [
        "// swift-format-ignore: NeverForceUnwrap\nlet value = optional!",
        "NeverForceUnwrap",
    ],
    [
        "// swiftlint:disable:next empty_count\nlet empty = values.count == 0",
        "empty_count",
    ],
    [
        "let empty = values.count == 0 // swiftlint:disable:this empty_count",
        "empty_count",
    ],
    ["/* swiftlint:disable empty_count */", "empty_count"],
    ["/* outer /* nested */ swiftlint:disable empty_count */", "empty_count"],
    [
        String.raw`let text = """
\({
    // swift-format-ignore: NeverForceUnwrap
    return value!
}())
"""`,
        "NeverForceUnwrap",
    ],
];
const invalid = [
    "// swift-format-ignore",
    "// swift-format-ignore-file",
    "// swiftlint:disable all",
    "// swiftlint:disable",
    "// swiftlint:disable empty_count force_cast",
];
const ordinary = [
    "// swiftlint:enable empty_count",
    'let text = "// swiftlint:disable empty_count"',
    'let text = #"a "quote" // swiftlint:disable empty_count"#',
    'let text = """\n// swift-format-ignore-file\n"""',
    'let text = #"""\n""" // swift-format-ignore-file\n"""#',
    "let expression = #/[//] swiftlint:disable all/#",
];
const sources = [
    ...suppressions.map(([source]) => source),
    ...invalid,
    ...ordinary,
].map((source, i) => ({ path: `apple/Example${i}.swift`, source }));
const parsed = parse(sources);
for (const [i, { path, source }] of sources.entries()) {
    const comments = parsed.filter((record) => record.path === path);
    if (i < suppressions.length) {
        const rule = suppressions[i][1];
        assert.ok(check(comments, {}).length, source);
        assert.deepEqual(check(comments, { [path]: [rule] }), [], source);
        assert.ok(
            check(comments, { "apple/Other.swift": [rule] }).length,
            source,
        );
        assert.deepEqual(
            check([...comments, ...comments], { [path]: [rule] }),
            [],
        );
    } else if (i < suppressions.length + invalid.length) {
        assert.ok(check(comments, {}).length, source);
        assert.ok(check(comments, { [path]: ["empty_count"] }).length, source);
    } else {
        assert.deepEqual(check(comments, {}), [], source);
    }
}
assert.match(
    check([], { "apple/Deleted.swift": ["empty_count"] }).join("\n"),
    /empty_count has no suppression/,
);
assert.deepEqual(check([], {}), []);
