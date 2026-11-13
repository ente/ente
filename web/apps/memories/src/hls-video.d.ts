import type { DetailedHTMLProps, VideoHTMLAttributes } from "react";

declare module "react" {
    namespace JSX {
        interface IntrinsicElements {
            "hls-video": DetailedHTMLProps<
                VideoHTMLAttributes<HTMLVideoElement>,
                HTMLVideoElement
            >;
        }
    }
}
