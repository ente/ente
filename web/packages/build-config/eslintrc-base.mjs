// @ts-check

import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
    eslint.configs.recommended,
    tseslint.configs.strictTypeChecked,
    tseslint.configs.stylisticTypeChecked,
    {
        languageOptions: { parserOptions: { projectService: true } },
        linterOptions: { reportUnusedDisableDirectives: "error" },
    },
    { ignores: ["eslint.config.mjs"] },
    {
        rules: {
            "@typescript-eslint/no-import-type-side-effects": "error",
            // Allow numbers to be used in template literals.
            "@typescript-eslint/restrict-template-expressions": [
                "error",
                { allowNumber: true },
            ],
            // Allow void expressions as the entire body of an arrow function.
            "@typescript-eslint/no-confusing-void-expression": [
                "error",
                { ignoreArrowShorthand: true },
            ],
            // Allow async functions to be passed as JSX attributes expected to
            // be functions that return void (typically onFoo event handlers).
            //
            // This should be safe since we have registered global unhandled
            // Promise handlers.
            "@typescript-eslint/no-misused-promises": [
                "error",
                { checksVoidReturn: { arguments: false, attributes: false } },
            ],
            // Allow force unwrapping potentially optional values.
            //
            // [Note: non-null-assertions have better stack trace]
            //
            // It is best if non-null assertions can be avoided by restructuring
            // the code, but there do arise legitimate scenarios where we know
            // from code logic that the value should be present. Of course, the
            // surrounding code might change causing that expectation to be
            // falsified, but in certain cases there isn't much we can do other
            // than throwing an exception.
            //
            // Instead of rolling our own such exception (which we in fact used
            // to do at, look in git history a utility function named "ensure"),
            // it is better rely on the JS's native undefined property access
            // exception since that conveys more information in the logs.
            "@typescript-eslint/no-non-null-assertion": "off",
            // Allow `while(true)` etc.
            "@typescript-eslint/no-unnecessary-condition": [
                "error",
                { allowConstantLoopConditions: true },
            ],
            // This one is a good suggestion in general, but it not always the
            // one we want because there are cases where we'd intentionally want
            // to map falsey values like empty strings to the default (e.g.
            // remote might be returning a blank string to indicate a missing
            // value), for which `||` is the appropriate operator, and doing it
            // without using `||` is unnecessarily convoluted.
            //
            // So the next best thing would be for us to disable this piecemeal,
            // and I tried that for a while. But that runs into a different
            // problem: currently some of our code gets linted under different
            // rules depending on the (pseudo-)package that is importing it.
            // This rules being on by default but off in some cases means that
            // for the same line of code, it is an error for some but not all
            // invocations of eslint. And so eslint then starts complaining
            // about us trying to squelch a non error.
            //
            // Given that (a) it is not always the right choice, and (b) it is
            // not not usable for our current state, disabling it globally.
            "@typescript-eslint/prefer-nullish-coalescing": "off",
        },
    },
);
