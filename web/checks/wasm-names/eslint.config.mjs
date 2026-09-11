import tseslint from "typescript-eslint";

export default [
    { ignores: ["**/*.wasm.d.ts"] },
    {
        files: ["packages/wasm/*/pkg/*.d.ts"],
        languageOptions: { parser: tseslint.parser },
        plugins: { "@typescript-eslint": tseslint.plugin },
        rules: {
            "@typescript-eslint/naming-convention": [
                "error",
                {
                    selector: ["function", "method", "property", "accessor"],
                    format: ["camelCase"],
                },
                { selector: "typeLike", format: ["PascalCase"] },
            ],
        },
    },
];
