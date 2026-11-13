export function checkAndroid({ files, readAddedLines }) {
    return files
        .filter(
            ({ path, binary, deleted }) =>
                !binary &&
                !deleted &&
                /^android\/.*\.(?:kt|kts|java|xml)$/.test(path),
        )
        .filter(({ path }) =>
            /\b(?:Suppress(?:Lint|Warnings)?\s*\(|tools\s*:\s*ignore\b|noinspection\b)/.test(
                readAddedLines(path),
            ),
        )
        .map(({ path }) => path);
}
