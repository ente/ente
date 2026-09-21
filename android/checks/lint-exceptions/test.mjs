import assert from "node:assert/strict";
import { check, parse } from "./check.mjs";

const suppressions = [
    ["kt", '@Suppress("NewApi") fun example() {}'],
    ["kts", '@file:Suppress("NewApi")'],
    ["kt", '@file:[Suppress("NewApi")]'],
    [
        "kt",
        '@[Other(values = ["value"]) SuppressLint("NewApi")] fun example() {}',
    ],
    ["kt", '@Suppress(\n/* reason */ "NewApi",\n) fun example() {}'],
    ["kt", '@Suppress(names = ["NewApi"]) fun example() {}'],
    ["kt", '@Suppress(names = arrayOf("NewApi")) fun example() {}'],
    ["kt", '@Suppress(names = arrayOf<String>("NewApi")) fun example() {}'],
    ["kt", '@Suppress(*arrayOf("NewApi")) fun example() {}'],
    [
        "kt",
        'import kotlin.Suppress as Quiet\n@Quiet("NewApi") fun example() {}',
    ],
    ["kt", 'val text = """${run {\n@Suppress("NewApi")\noldMethod()\n}}"""'],
    ["kt", "//noinspection NewApi\nfun example() {}"],
    ["java", '@android.annotation.SuppressLint("NewApi") class Example {}'],
    ["java", '@SuppressWarnings(value = {"NewApi"}) class Example {}'],
    ["java", "//noinspection NewApi\nclass Example {}"],
    [
        "xml",
        '<root xmlns:tools="http://schemas.android.com/tools">\n  <view\n    tools:ignore="NewApi" />\n</root>',
        3,
    ],
    [
        "xml",
        '<view xmlns:lint="http://schemas.android.com/tools" lint:ignore="NewApi" />',
    ],
];
const invalid = [
    '@Suppress("NewApi", "MissingPermission") fun example() {}',
    '@Suppress("all") fun example() {}',
    "@Suppress(RULE) fun example() {}",
    '@Suppress("New" + "Api") fun example() {}',
    "//noinspection",
    'typealias Quiet = Suppress\n@Quiet("NewApi") fun example() {}',
];
const ordinary = [
    [
        "kt",
        'fun Suppress(text: String) {}\nfun example() { Suppress("NewApi") }',
    ],
    ["kt", '// @Suppress("NewApi")'],
    ["kt", '/* outer /* nested */ @Suppress("NewApi") */'],
    ["kt", 'val text = "@Suppress(\\"NewApi\\")"'],
    ["kt", 'val text = """\n@Suppress("NewApi")\n//noinspection NewApi\n"""'],
    ["xml", '<root><!-- <view tools:ignore="NewApi" /> --></root>'],
    ["xml", '<value><![CDATA[tools:ignore="NewApi"]]></value>'],
    ["xml", '<string name="example">tools:ignore="NewApi"</string>'],
    ["xml", `<view text='tools:ignore="NewApi"' />`],
];
const sources = [
    ...suppressions,
    ...invalid.map((source) => ["kt", source]),
    ...ordinary,
].map(([extension, source], i) => ({
    path: `android/Example${i}.${extension}`,
    source,
}));
const parsed = parse(sources);
for (const [i, { path, source }] of sources.entries()) {
    const records = parsed.filter((record) => record.path === path);
    const allowed = { [path]: ["NewApi"] };
    if (i < suppressions.length) {
        const line = suppressions[i][2];
        if (line)
            assert.deepEqual(
                records.map((record) => record.line),
                [line],
            );
        assert.ok(check(records, {}).length, source);
        assert.deepEqual(check(records, allowed), [], source);
        assert.ok(
            check(records, { "android/Other.kt": ["NewApi"] }).length,
            source,
        );
        assert.deepEqual(check([...records, ...records], allowed), []);
    } else if (i < suppressions.length + invalid.length) {
        assert.ok(check(records, {}).length, source);
        assert.ok(check(records, allowed).length, source);
    } else {
        assert.deepEqual(check(records, {}), [], source);
    }
}
assert.match(
    check([], { "android/Deleted.kt": ["NewApi"] }).join("\n"),
    /NewApi has no suppression/,
);
assert.deepEqual(check([], {}), []);
