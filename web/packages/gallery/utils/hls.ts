export const maxHLSMetadataBytes = 8 * 1024 * 1024;
const maxHLSPlaylistBytes = 32 * 1024 * 1024;

const allowedTag =
    /^#(?:EXTM3U|EXT-X-(?:VERSION:\d+|TARGETDURATION:\d+|MEDIA-SEQUENCE:\d+|KEY:METHOD=AES-128,URI="data:text\/plain;base64,[A-Za-z0-9+/]{22}==",IV=0x[0-9a-fA-F]{32}|BYTERANGE:\d+(?:@\d+)?|ENDLIST)|EXTINF:\d+(?:\.\d+)?,$)$/;

export const reconstructHLSPlaylist = (
    template: string,
    segmentURL: string,
) => {
    const result: string[] = [];
    const segmentURLBytes = new TextEncoder().encode(segmentURL).byteLength;
    let outputBytes = 0;
    let hasKey = false;
    let hasSegment = false;
    for (const match of template.matchAll(/([^\n]*?)(?:\r?\n|$)/g)) {
        let line = match[1]!;
        if (!line || (line.startsWith("#") && !line.startsWith("#EXT"))) {
            continue;
        }
        if (!line.startsWith("#")) {
            line = segmentURL;
            outputBytes += segmentURLBytes;
            hasSegment = true;
        } else if (allowedTag.test(line)) {
            outputBytes += line.length;
            hasKey ||= line.startsWith("#EXT-X-KEY:");
        } else {
            return undefined;
        }
        outputBytes += 1;
        if (outputBytes > maxHLSPlaylistBytes) return undefined;
        result.push(line);
    }

    if (
        !hasKey ||
        !hasSegment ||
        result[0] != "#EXTM3U" ||
        result.at(-1) != "#EXT-X-ENDLIST"
    ) {
        return undefined;
    }
    result.push("");
    return result.join("\n");
};
