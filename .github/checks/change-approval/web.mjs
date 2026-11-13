export function checkWeb({ files, readAddedLines }) {
    return files
        .filter(
            ({ path, binary, deleted }) =>
                !binary && !deleted && /^web\/.*\.[cm]?[jt]sx?$/.test(path),
        )
        .filter(({ path }) => /\beslint(?:[-\s]|$)/m.test(readAddedLines(path)))
        .map(({ path }) => path);
}
