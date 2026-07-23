/**
 * @file [Note: SVG paths of MUI icons]
 *
 * When creating buttons for use with PhotoSwipe, we need to provide just the
 * contents of the SVG element (e.g. paths) as an HTML string.
 *
 * Since we only need a handful, these strings were created by temporarily
 * adding the following code in some existing React component to render the
 * corresponding MUI icon React component to a string, and retain the path.
 *
 *
 *     import { renderToString } from "react-dom/server";
 *     import InfoOutlinedIcon from "@mui/icons-material/InfoOutlined";
 *
 *     console.log(renderToString(<InfoOutlinedIcon />));
 */

// The transforms are not part of the originals, they have been applied
// separately to get these icons to align with the ones built into PhotoSwipe.
const paths = {
    // "@mui/icons-material/ErrorOutlined"
    error: '<path d="M11 15h2v2h-2zm0-8h2v6h-2zm.99-5C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2M12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8" transform="translate(7, 5.7) scale(0.85)"',
    // Custom heart outline icon (30x26 viewBox)
    heart: '<path d="M12.4926 23.4794C8.64537 20.6025 1.02344 14.0254 1.02344 8.10676C1.02344 4.19475 3.89425 1.02344 7.84162 1.02344C9.88707 1.02344 11.9325 1.70526 14.6598 4.43253C17.3871 1.70526 19.4325 1.02344 21.478 1.02344C25.4253 1.02344 28.2962 4.19475 28.2962 8.10676C28.2962 14.0254 20.6743 20.6025 16.827 23.4794C15.5324 24.4474 13.7872 24.4474 12.4926 23.4794Z" stroke="white" stroke-width="2.04545" stroke-linecap="round" stroke-linejoin="round" fill="none"',
    // Custom heart filled icon (30x26 viewBox) - green fill for liked state
    "heart-fill":
        '<path d="M12.4926 23.4794C8.64537 20.6025 1.02344 14.0254 1.02344 8.10676C1.02344 4.19475 3.89425 1.02344 7.84162 1.02344C9.88707 1.02344 11.9325 1.70526 14.6598 4.43253C17.3871 1.70526 19.4325 1.02344 21.478 1.02344C25.4253 1.02344 28.2962 4.19475 28.2962 8.10676C28.2962 14.0254 20.6743 20.6025 16.827 23.4794C15.5324 24.4474 13.7872 24.4474 12.4926 23.4794Z" stroke="#22c55e" stroke-width="2.04545" stroke-linecap="round" stroke-linejoin="round" fill="#22c55e"',
    // Custom comment bubble icon (28x28 viewBox, scaled to match heart)
    comment:
        '<path d="M13.636 25.9087C16.0633 25.9087 18.4361 25.189 20.4544 23.8404C22.4726 22.4919 24.0456 20.5751 24.9745 18.3326C25.9034 16.09 26.1465 13.6224 25.6729 11.2417C25.1994 8.86105 24.0305 6.67426 22.3141 4.95788C20.5978 3.24151 18.411 2.07265 16.0303 1.5991C13.6496 1.12556 11.182 1.3686 8.93944 2.29749C6.69689 3.22639 4.78015 4.79941 3.43161 6.81765C2.08306 8.83589 1.36328 11.2087 1.36328 13.636C1.36328 15.6651 1.85419 17.5783 2.72692 19.2637L1.36328 25.9087L8.00828 24.5451C9.69373 25.4178 11.6083 25.9087 13.636 25.9087Z" stroke="white" stroke-width="2.04545" stroke-linecap="round" stroke-linejoin="round" fill="none" transform="translate(1.5, 1.5) scale(0.9)"',
    // "@mui/icons-material/AlbumOutlined"
    live: '<path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2m0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8m0-12.5c-2.49 0-4.5 2.01-4.5 4.5s2.01 4.5 4.5 4.5 4.5-2.01 4.5-4.5-2.01-4.5-4.5-4.5m0 5.5c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1" transform="translate(2, 8.7) scale(0.75)"',
    // "@mui/icons-material/VolumeUp"
    vol: '<path d="M3 9v6h4l5 5V4L7 9zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02M14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77" transform="translate(0, 9) scale(0.75)"',
    // Custom star icon (outline)
    favorite:
        '<path d="M8.69381 1.56975C9.38617 0.609562 10.7995 0.609562 11.4919 1.56975L13.7114 4.64784C13.9253 4.9445 14.2255 5.16569 14.5699 5.28031L18.1427 6.46961C19.2572 6.84061 19.6939 8.20365 19.0073 9.16808L16.8062 12.2597C16.5941 12.5577 16.4794 12.9156 16.4783 13.2831L16.4669 17.0962C16.4634 18.2857 15.32 19.1281 14.2033 18.764L10.6234 17.5966C10.2784 17.4841 9.90729 17.4841 9.56228 17.5966L5.98245 18.764C4.86575 19.1281 3.72231 18.2857 3.71876 17.0962L3.70737 13.2831C3.70628 12.9156 3.5916 12.5577 3.37946 12.2597L1.17839 9.16808C0.491785 8.20365 0.928537 6.84061 2.04305 6.46961L5.61584 5.28031C5.96017 5.16569 6.26041 4.9445 6.47432 4.64784L8.69381 1.56975Z" fill="none" stroke="white" stroke-width="1.7" transform="translate(5.5, 6)"',
    // Custom star icon (filled)
    "favorite-fill":
        '<path d="M8.69381 1.56975C9.38617 0.609562 10.7995 0.609562 11.4919 1.56975L13.7114 4.64784C13.9253 4.9445 14.2255 5.16569 14.5699 5.28031L18.1427 6.46961C19.2572 6.84061 19.6939 8.20365 19.0073 9.16808L16.8062 12.2597C16.5941 12.5577 16.4794 12.9156 16.4783 13.2831L16.4669 17.0962C16.4634 18.2857 15.32 19.1281 14.2033 18.764L10.6234 17.5966C10.2784 17.4841 9.90729 17.4841 9.56228 17.5966L5.98245 18.764C4.86575 19.1281 3.72231 18.2857 3.71876 17.0962L3.70737 13.2831C3.70628 12.9156 3.5916 12.5577 3.37946 12.2597L1.17839 9.16808C0.491785 8.20365 0.928537 6.84061 2.04305 6.46961L5.61584 5.28031C5.96017 5.16569 6.26041 4.9445 6.47432 4.64784L8.69381 1.56975Z" transform="translate(5.5, 6)"',
    // "@mui/icons-material/FileDownloadOutlined"
    download:
        '<path d="M18 15v3H6v-3H4v3c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2v-3zm-1-4-1.41-1.41L13 12.17V4h-2v8.17L8.41 9.59 7 11l5 5z" transform="translate(0, 4)"',
    // "@mui/icons-material/InfoOutlined"
    info: '<path d="M11 7h2v2h-2zm0 4h2v6h-2zm1-9C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2m0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8" transform="translate(1, 4.5) scale(0.95)"',
    // "@mui/icons-material/MoreHoriz"
    more: '<path d="M6 10c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2m12 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2m-6 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2" transform="translate(0, 4.5)"',
    // "@mui/icons-material/FullscreenOutlined"
    fullscreen:
        '<path d="M7 14H5v5h5v-2H7zm-2-4h2V7h3V5H5zm12 7h-3v2h5v-5h-2zM14 5v2h3v3h2V5z" transform="translate(0, 4.5)"',
    // "@mui/icons-material/FullscreenExitOutlined"
    "fullscreen-exit":
        '<path d="M5 16h3v3h2v-5H5zm3-8H5v2h5V5H8zm6 11h2v-3h3v-2h-5zm2-11V5h-2v5h5V8z" transform="translate(0, 4.5)"',
};

type IconKeys = Exclude<
    keyof typeof paths,
    "favorite-fill" | "fullscreen-exit"
>;

/**
 * Return an object that can be passed verbatim to the "html" option expected by
 * PhotoSwipe's registerElement function.
 *
 * API docs for registerElement:
 * https://photoswipe.com/adding-ui-elements/#uiregisterelement-api
 *
 * Example:
 *
 *     html: {
 *         isCustomSVG: true,
 *         inner: '<path d="M11 7h2v2h-2zm0 4h2v6h-2zm1-9C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2m0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8" transform="translate(3.5, 3.5)" id="pswp__icn-info" />',
 *         outlineID: "pswp__icn-info",
 *     }
 *
 */
export const createPSRegisterElementIconHTML = (name: IconKeys) => ({
    isCustomSVG: true,
    inner:
        name == "favorite"
            ? favoriteInner()
            : name == "fullscreen"
              ? fullscreenInner()
              : `${paths[name]} id="pswp__icn-${name}" />`,
    outlineID: `pswp__icn-${name}`,
});

// Favorite is a special case since it consists of two layers: outline and fill.
const favoriteInner = () => {
    // Main outline (white stroke)
    const outline = `${paths.favorite} id="pswp__icn-favorite" />`;
    // Fill (for favorited state)
    const fill = `${paths["favorite-fill"]} id="pswp__icn-favorite-fill" />`;
    return outline + fill;
};

// Fullscreen is also a special case since it has two states.
const fullscreenInner = () =>
    `${paths.fullscreen} id="pswp__icn-fullscreen" />${paths["fullscreen-exit"]} id="pswp__icn-fullscreen-exit" />`;

/**
 * The path of "@mui/icons-material/Settings" as as string.
 *
 * Assumes `viewBox="0 0 24 24"`.
 */
export const settingsSVGPath = `<path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6"></path>`;

/**
 * The path for the custom heart outline icon.
 *
 * Assumes `viewBox="0 0 30 26"`.
 */
export const heartSVGPath = paths.heart;

/**
 * The path for the custom heart filled icon (green).
 *
 * Assumes `viewBox="0 0 30 26"`.
 */
export const heartFillSVGPath = paths["heart-fill"];

/**
 * The path for the custom comment bubble icon.
 *
 * Assumes `viewBox="0 0 28 28"`.
 */
export const commentSVGPath = paths.comment;
