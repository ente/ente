import config from "ente-build-config/eslintrc-next-app.mjs";

export default [
    ...config,
    { ignores: [".next-desktop"] },
    {
        files: ["src/components/gallery/navigation/RailIcon.tsx"],
        rules: {
            "@typescript-eslint/no-deprecated": [
                "error",
                {
                    allow: [
                        {
                            from: "package",
                            package: "@rive-app/canvas-lite",
                            name: "stateMachineInputs",
                        },
                    ],
                },
            ],
        },
    },
];
