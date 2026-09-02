export const rawWasmPath = String.raw`(?:^|/)pkg(?:/|$)|\.wasm(?:[?#].*)?$`;

const selectorRawWasmPath = rawWasmPath.replaceAll("/", "\\u002F");
const payloadImport = `ImportExpression:matches([source.value=/${selectorRawWasmPath}/], [source.type=TemplateLiteral][source.expressions.length=0][source.quasis.0.value.cooked=/${selectorRawWasmPath}/])`;
const payloadRequire = `CallExpression[callee.name=require]:matches([arguments.0.value=/${selectorRawWasmPath}/], [arguments.0.type=TemplateLiteral][arguments.0.expressions.length=0][arguments.0.quasis.0.value.cooked=/${selectorRawWasmPath}/])`;
const restrictedPayloadRequire = {
    selector: payloadRequire,
    message: "Load generated WASM with import() inside its wrapper.",
};

export default [
    {
        ignores: [
            "**/pkg/**",
            "**/.next*/**",
            "**/dist/**",
            "**/out/**",
            "**/public/**",
            "**/*.d.ts",
            "**/*.test.*",
        ],
    },
    {
        files: ["**/*.{js,jsx,mjs,cjs,ts,tsx,mts,cts}"],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    patterns: [
                        {
                            regex: rawWasmPath,
                            allowTypeImports: true,
                            message:
                                "Use an import-safe wrapper that loads generated WASM on demand.",
                        },
                    ],
                },
            ],
            "no-restricted-syntax": [
                "error",
                {
                    selector: payloadImport,
                    message:
                        "Load generated WASM through a wrapper in web/packages/wasm.",
                },
                restrictedPayloadRequire,
            ],
        },
    },
    {
        files: ["packages/wasm/**"],
        rules: {
            "no-restricted-syntax": [
                "error",
                {
                    selector:
                        payloadImport +
                        ":not(:matches(FunctionDeclaration, FunctionExpression, ArrowFunctionExpression) ImportExpression)",
                    message: "Defer loading generated WASM inside a function.",
                },
                restrictedPayloadRequire,
            ],
        },
    },
];
