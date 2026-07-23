# Dependencies

## Dev

These are some global dev dependencies in the root `package.json`. These set the baseline for how our code should be in all the workspaces in this npm monorepo.

- [prettier](https://prettier.io) - Formatter

- [eslint](https://eslint.org) - Linter

- [typescript](https://www.typescriptlang.org/) - Type checker

They also need some support packages, which come from the leaf `ente-build-config` package:

- [@eslint/js](https://eslint.org/) provides JavaScript ESLint functionality, and provides the configuration recommended the by ESLint team.

- [typescript-eslint](https://typescript-eslint.io/packages/typescript-eslint/) - provides TypeScript ESLint functionality and provides a set of recommended configurations (`typescript-eslint` is the new entry point, our yet-unmigrated packages use the older method of separately including [@typescript-eslint/parser](https://typescript-eslint.io/packages/eslint-plugin/) - which tells ESLint how to read TypeScript syntax - and [@typescript-eslint/eslint-plugin](https://typescript-eslint.io/packages/eslint-plugin/) - which provides the TypeScript rules and presets).

- [eslint-plugin-react](https://github.com/jsx-eslint/eslint-plugin-react), [eslint-plugin-react-hooks](https://reactjs.org/) - Some React specific ESLint rules and configurations that are used by the workspaces that have React code.

- [eslint-plugin-react-refresh](https://github.com/ArnaudBarre/eslint-plugin-react-refresh) - A plugin to ensure that React components are exported in a way that they can be HMR-ed.

- [prettier-plugin-organize-imports](https://github.com/simonhaenisch/prettier-plugin-organize-imports) - A Prettier plugin to sort imports.

- [prettier-plugin-packagejson](https://github.com/matzkoh/prettier-plugin-packagejson) - A Prettier plugin to also prettify `package.json`.

The root `package.json` also has a convenience dev dependency:

- [concurrently](https://github.com/open-cli-tools/concurrently) for spawning parallel tasks when we invoke various npm scripts.

> [!NOTE]
>
> We need to repeat some of the dependencies in multiple `package.json`s to avoid spurious missing peer dependency warnings.
>
> For example, ideally we'd just have specified the react dependencies in _ente-base_, but that leads to missing peer dependency warnings in our other packages, so we need to need to repeat them. For now, we manually ensure that all of them use the same version.
>
> Additionally, we pin the versions of the react types using the overrides field in the top level `package.json`, to avoid type errors because of multiple versions of react types being in scope.

## Cryptography

We use [libsodium](https://libsodium.gitbook.io/doc/) for our cryptography primitives. We use its WebAssembly target, accessible via JavaScript wrappers maintained by the original authors of libsodium themselves - [libsodium-wrappers](https://github.com/jedisct1/libsodium.js).

More precisely, we use the sumo variant, "libsodium-wrappers-sumo", since the standard variant does not provide the `crypto_pwhash_*` functions.

## Meta frameworks

### Next.js

[Next.js](https://nextjs.org) (package: [next](https://github.com/vercel/next.js)) provides the meta framework for both the photos and the auth app, and also for some of the sidecar apps like accounts and cast.

We use a limited subset of Next.js. The main thing we get out of it is a reasonable set of defaults for bundling our app into a static export which we can then deploy to our webserver. In addition, the Next.js page router is convenient. Overall our apps can be described as regular React SPAs, and are not particularly tied to Next.js.

### Vite

For some of our newer code, we have started to use [Vite](https://vitejs.dev). It is likely the future (both generally, and for our code) since Next.js is becoming less suitable for SPAs and static SSR with their push towards RSC and dynamic SSR.

## UI

### React

[React](https://react.dev) (package: [react](https://github.com/facebook/react)) is our core framework. We also import its a sibling [react-dom](https://github.com/facebook/react) package that renders JSX to the DOM.

### MUI and Material Icons

We use [MUI](https://mui.com)'s [@mui/material](https://mui.com/material-ui/getting-started/installation/) as our base React component library (In our code and documentation, we use the name "MUI" to refer to the the combination of both MUI's "Material UI" and "System" packages that we use).

MUI uses [Emotion](https://emotion.sh/) as its preferred CSS-in-JS library, for which we need to install install two Emotion packages (`@emotion/react` and `@emotion/styled`) as peer dependencies.

We also use MUI's [@mui/material-icons](https://mui.com/material-ui/material-icons/) package, which provides Material icons exported as React components (a `SvgIcon`).

> [!NOTE]
>
> For a similar reason as with react,
>
> - the `@mui/material` dependency is also repeated at more places - the one in _ente-base_ is the canonical one.
> - we need to add an explicit dependency to `mui/system` in _ente-new_ even though we don't directly depend on it.

### Date pickers

[@mui/x-date-pickers](https://mui.com/x/react-date-pickers/getting-started/) is used to get a date/time picker component. This is the community version of the DateTimePicker component provided by MUI.

[dayjs](https://github.com/iamkun/dayjs) is used as the date library that that `@mui/x-date-pickers` will internally use to manipulate dates.

### Translations

For showing the app's UI in multiple languages, we use the [i18next](https://www.i18next.com), specifically its three components

- [i18next](https://github.com/i18next/i18next): The core `i18next` library.

- [react-i18next](https://github.com/i18next/react-i18next): React specific support in `i18next`.

- [i18next-http-backend](https://github.com/i18next/i18next-http-backend): Adds support for initializing `i18next` with JSON file containing the translation in a particular language, fetched at runtime.

Note that inspite of the "next" in the name of the library, it has nothing to do with Next.js.

[get-user-locale](https://github.com/wojtekmaj/get-user-locale) is used for enumerating the user's locale's to find the best match.

For more details, see [translations.md](translations.md).

### Font

Inter Variable (with support for weights 100 - 90) is used as the primary font, via [@fontsource-variable/inter](https://fontsource.org/fonts/inter/install).

### UI components

- [react-window](https://github.com/bvaughn/react-window) is used for lazy-ily rendering large lists of dynamically created content, each item being of a variable height. It is usually used in tandem with its sibling package, [react-virtualized-auto-sizer](https://github.com/bvaughn/react-virtualized-auto-sizer) which allows the lazy list to resize itself automatically to fill the entire remaining space available in the container.

- [formik](https://github.com/jaredpalmer/formik) provides an easier to use abstraction for dealing with form state, validation and submission states when using React.

- [react-select](https://react-select.com/) is used for search dropdowns.

- [react-otp-input](https://github.com/devfolioco/react-otp-input) is used to render a segmented OTP input field for 2FA authentication.

## Utilities

- [comlink](https://github.com/GoogleChromeLabs/comlink) provides a minimal layer on top of web workers to make them more easier to use.

- [idb](https://github.com/jakearchibald/idb) provides a promise API over the browser-native IndexedDB APIs. Older code (the file and collection store), uses [localForage](https://github.com/localForage/localForage) for IndexedDB access.

    > For more details about IDB and its role, see [storage.md](storage.md).

- [zod](https://github.com/colinhacks/zod) is used for runtime typechecking (e.g. verifying that API responses match the expected TypeScript shape).

- [nanoid](https://github.com/ai/nanoid) is used for generating unique identifiers. For one particular use case, we also need [uuid](https://github.com/uuidjs/uuid) for UUID v4 generation.

- [bs58](https://github.com/cryptocoinjs/bs58) is used for base-58 conversion (used for encoding the collection key to use as the hash in the share URL).

- [debounce](https://github.com/sindresorhus/debounce) and its promise-supporting sibling [p-debounce](https://github.com/sindresorhus/p-debounce) are used for debouncing operations (See also: `[Note: Throttle and debounce]`).

- [bip39](https://github.com/bitcoinjs/bip39) is used for generating the 24-word recovery key mnemonic.

- [zxcvbn](https://github.com/dropbox/zxcvbn) is used for password strength estimation.

- [fast-srp-hap](https://github.com/homebridge/fast-srp) is used for the maths underlying the SRP protocol.

## Media

- [@ffmpeg/ffmpeg](https://github.com/ffmpegwasm/ffmpeg.wasm) is used to run FFmpeg in the browser using WebAssembly (Wasm). Note that this is substantially slower than native ffmpeg (the desktop app can, and does, bundle the faster native ffmpeg implementation too).

- [exifreader](https://github.com/mattiasw/ExifReader) is used for Exif parsing.

- [jszip](https://github.com/Stuk/jszip) is used for reading zip files in the web code (Live photos are zip files under the hood). Note that the desktop app uses also has a ZIP parser (that one supports streaming).

- [file-type](https://github.com/sindresorhus/file-type) is used for MIME type detection.

- [heic-convert](https://github.com/catdad-experiments/heic-convert) is used for converting HEIC files (which browsers don't natively support) into JPEG. For (much more) details, see [heic.md](heic.md).

## Photos app specific

- [photoswipe](https://photoswipe.com) provides the base image viewer on top of which we've built our file viewer.

- For streaming video (HLS), we use three libraries:
    1. [media-chrome](https://github.com/muxinc/media-chrome) provides custom video controls which we use when playing HLS playlists (we use custom controls to provide a standardized UX across browsers, but really the main reason is that Safari's default video controls are on the verge of unusable, especially for streaming playback),

    2. [hls-video-element](https://github.com/muxinc/media-elements/tree/main/packages/hls-video-element) provides a custom web component element that glues media-chrome and hls.js together, and

    3. [hls.js](https://github.com/video-dev/hls.js/) (indirect dependency via hls-video-element) is needed on HLS playback on Chrome and Firefox (which do not have native support for HLS playlists).

- [react-dropzone](https://github.com/react-dropzone/react-dropzone/) is a React hook to create a drag-and-drop input zone.

- [sanitize-filename](https://github.com/parshap/node-sanitize-filename) is for converting arbitrary strings into strings that are suitable for being used as filenames.

- [chrono-node](https://github.com/wanasit/chrono) is used for parsing natural language queries into dates for showing search results.

- [ml-matrix](https://github.com/mljs/matrix) is mathematical matrix abstraction by the machine learning code. It is used alongwith [similarity-transformation](https://github.com/shaileshpandit/similarity-transformation-js) during face alignment.

- [react-top-loading-bar](https://github.com/klendi/react-top-loading-bar) is used for showing a progress indicator for global actions (This shouldn't be used always, it is only meant as a fallback when there isn't an otherwise suitable place for showing a local activity indicator).

## Auth app specific

- [otpauth](https://github.com/hectorm/otpauth) is used for the generation of the actual OTP from the user's TOTP/HOTP secret.

- However, otpauth doesn't support steam OTPs. For these, we need to compute the SHA-1, and we use `@noble/hashes`, the same hash library that `otpauth` uses.

## Pinned

- `react-dropzone` is pinned to the 14.2.10, the last version in the 14.2 series, since if we use 14.3 onwards (I tested till 14.3.5) then we are unable to get back a path from the file by using the `webUtils.getPathForFile` function provided by Electron. See: https://github.com/react-dropzone/react-dropzone/issues/1411

- `@stripe/stripe-js` is pinned to the latest 1.x (it works as it is currently, migrating to newer major versions requires headspace since it _might_ also require museum changes).

- `base-x` is pinned to 5.0.1 via the root `overrides` field because it is pulled in transitively by `bs58`, and 5.0.0 is affected by [CVE-2025-27611](https://github.com/advisories/GHSA-xq7p-g2vc-g82p).
