export function checkSwift({ files, readAddedLines }) {
    return files
        .filter(
            ({ path, binary, deleted }) =>
                !binary && !deleted && /^apple\/.*\.swift$/.test(path),
        )
        .filter(({ path }) =>
            /\b(?:swiftlint\s*:|swift-format-ignore\b)/.test(
                readAddedLines(path),
            ),
        )
        .map(({ path }) => path);
}
