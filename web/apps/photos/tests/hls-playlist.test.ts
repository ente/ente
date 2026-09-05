import { reconstructHLSPlaylist } from "ente-gallery/utils/hls";
import { describe, expect, test } from "vitest";

const playlist = `#EXTM3U
#EXT-X-MEDIA-SEQUENCE:42
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:8
#EXT-X-KEY:METHOD=AES-128,URI="data:text/plain;base64,XjvG7qeRrsOpPUbJPh2Ikg==",IV=0x00000000000000000000000000000000
#EXTINF:8.333333,
#EXT-X-BYTERANGE:3046928@0
video.ts
#EXTINF:2.200000,
#EXT-X-BYTERANGE:834736
video.ts
#EXT-X-ENDLIST
`;

describe("reconstructHLSPlaylist", () => {
    test("reconstructs an allowed single-file playlist", () => {
        const segmentURL = "https://museum.example/video?token=secret";

        expect(reconstructHLSPlaylist(playlist, segmentURL)).toBe(
            playlist.replaceAll("video.ts", segmentURL),
        );
    });

    test("replaces every untrusted URI line", () => {
        const segmentURL = "https://museum.example/video";
        const input = playlist.replace("video.ts", "https://attacker");

        expect(reconstructHLSPlaylist(input, segmentURL)).toBe(
            playlist.replaceAll("video.ts", segmentURL),
        );
    });

    test.each([
        [
            "remote key",
            playlist.replace(
                "data:text/plain;base64,XjvG7qeRrsOpPUbJPh2Ikg==",
                "https://attacker/key",
            ),
        ],
        [
            "map",
            playlist.replace(
                "#EXTINF:8.333333,",
                '#EXT-X-MAP:URI="https://attacker/map"\n#EXTINF:8.333333,',
            ),
        ],
    ])("rejects a playlist with an unexpected %s", (_, input) => {
        expect(
            reconstructHLSPlaylist(input, "https://museum/video"),
        ).toBeUndefined();
    });
});
