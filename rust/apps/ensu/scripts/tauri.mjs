import cli from "@tauri-apps/cli";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../", import.meta.url)));
const args = process.argv.slice(2);
const separator = args.indexOf("--");
const cliArgs = args.slice(0, separator < 0 ? undefined : separator);
const commandIndex = cliArgs.findIndex((arg) => !arg.startsWith("-"));
const options = cliArgs.slice(commandIndex + 1);

try {
    if (
        ["build", "bundle"].includes(cliArgs[commandIndex]) &&
        !cliArgs.some((arg) =>
            ["--help", "-h", "--version", "-V"].includes(arg),
        )
    ) {
        let target =
            process.env.TAURI_ENV_TARGET_TRIPLE ??
            process.env.CARGO_BUILD_TARGET;
        for (let i = 0; i < options.length; i++) {
            const arg = options[i];
            if (arg === "--target" || arg === "-t") target = options[++i];
            else if (arg.startsWith("--target=")) target = arg.slice(9);
            else if (arg.startsWith("-t"))
                target = arg.slice(2).replace(/^=/, "");
        }
        if (target) process.env.TAURI_ENV_TARGET_TRIPLE = target;
        await import("./prepare-voice-runtime.mjs");
        const macOS = target
            ? target.includes("darwin")
            : process.platform === "darwin";
        const config = fileURLToPath(
            new URL(
                `../src-tauri/tauri.voice${macOS ? ".macos" : ""}.conf.json`,
                import.meta.url,
            ),
        );
        args.splice(commandIndex + 1, 0, "--config", config);
    }
    await cli.run(args, "npm run tauri");
} catch (error) {
    cli.logError(error.message);
    process.exitCode = 1;
}
