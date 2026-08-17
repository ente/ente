import baseConfig from "ente-build-config/eslintrc-react.mjs";

export default [
    ...baseConfig,
    {
        files: ["**/*.{ts,tsx}"],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    paths: [
                        {
                            name: "ente-base/crypto",
                            message:
                                "Use ente-accounts/services/crypto instead.",
                        },
                        {
                            name: "ente-base/crypto/types",
                            message:
                                "Use ente-accounts/services/crypto instead.",
                        },
                        {
                            name: "ente-base/session",
                            message:
                                "Use ente-accounts/services/session-storage instead.",
                        },
                        {
                            name: "fast-srp-hap",
                            message:
                                "Use Rust/WASM SRP helpers from ente-accounts/services/srp.",
                        },
                        {
                            name: "bip39",
                            message:
                                "Use Rust/WASM recovery helpers from ente-accounts/services/crypto.",
                        },
                    ],
                },
            ],
        },
    },
];
