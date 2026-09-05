const allowedTag =
    /^#(?:EXTM3U|EXT-X-(?:VERSION:\d+|TARGETDURATION:\d+|MEDIA-SEQUENCE:\d+|KEY:METHOD=AES-128,URI="data:text\/plain;base64,[A-Za-z0-9+/]{22}==",IV=0x[0-9a-fA-F]{32}|BYTERANGE:\d+(?:@\d+)?|ENDLIST)|EXTINF:\d+(?:\.\d+)?,$)$/;

export const reconstructHLSPlaylist = (
    template: string,
    segmentURL: string,
) => {
    const result: string[] = [];
    let hasKey = false;
    let hasSegment = false;
    for (const line of template.split(/\r?\n/)) {
        if (!line || (line.startsWith("#") && !line.startsWith("#EXT"))) {
            continue;
        }
        if (!line.startsWith("#")) {
            result.push(segmentURL);
            hasSegment = true;
        } else if (allowedTag.test(line)) {
            result.push(line);
            hasKey ||= line.startsWith("#EXT-X-KEY:");
        } else {
            return undefined;
        }
    }

    if (
        !hasKey ||
        !hasSegment ||
        result[0] != "#EXTM3U" ||
        result.at(-1) != "#EXT-X-ENDLIST"
    ) {
        return undefined;
    }
    return [...result, ""].join("\n");
};
