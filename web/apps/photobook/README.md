# Ente Photobook

A fully private photobook maker that runs entirely in your browser. No uploads, no accounts, no tracking. Just drag in your photos, design your book, and download the result. What you do with it is up to you: print it at home, take it to a local print shop, or order online.

## Why?

Every photobook service out there requires you to upload your personal photos to their servers. Photobook flips that: everything happens locally in your browser. Your photos never leave your device.

## Features

- **Drag-and-drop photo import** with automatic chronological sorting via EXIF data
- **Smart auto-layout** that arranges photos across pages based on orientation, varying layouts (1–4 photos per page) to keep things interesting
- **Interactive editor** — reorder pages, reposition and crop photos within their slots, add captions and text blocks
- **Multiple export formats:**
    - Print-ready PDF with 210 × 210 mm square pages
    - ZIP of numbered square PNG pages
- **Print product selection** — choose hardcover or softcover and paper stock; PDF and PNG downloads check the product's page limits, counting covers and even-page padding
- **Persistent state** — your book is saved locally in your browser so you can come back to it

## Getting started

Go to [photobook.ente.com](https://photobook.ente.com) and start making your photobook.

## Development

Use Node.js 24 and npm 11.12.1. Install the pinned dependencies and start the app:

```bash
npm ci
npm run dev
```

Then open [http://localhost:3000](http://localhost:3000).

Run the checks before submitting changes:

```bash
npm run lint
npm run typecheck
npm test
npm run build
```

Tests use Vitest and cover layouts, saved-book compatibility, print products, page ordering, and export sequencing. The unit export tests mock canvas and PDF conversion.

Install Chromium once and run the browser checks:

```bash
npm exec -- playwright install chromium
npm run test:browser
```

The browser command builds the production app, then starts local test servers on ports 4317 and 4318. Playwright uses an isolated browser to check import, saved-book restoration, page insertion, undo/redo, binding selection, preview navigation, PDF download, and reset. A separate Vite fixture exercises the PNG ZIP exporter. The tests check 24-page output, page dimensions, CMYK PDF images, and that the production WASM asset matches the installed ImageMagick package. CI installs Chromium with its system dependencies and keeps traces and screenshots when a test fails. HEIC conversion and live Ente album imports are not covered by this suite.

The production build exports static files to `out/`. Development output lives in `.next-dev/`, so a production build can run without replacing the development server's files. Both builds use webpack for the browser-only canvas and WASM dependencies.

Dependencies shared with Ente match the versions in its web workspace. External dependencies use exact versions, and npm lifecycle scripts are disabled. ImageMagick's WASM is bundled from the package export; there is no separate copy to update in `public/`.

`npm run lint` checks Ente's Prettier formatting, ESLint rules, unused files/exports/dependencies with Knip, and documentation comments. Use `npm run format` to apply formatting. The comment checker is adapted from Ente's `.github/checks/documentation-comments/check.mjs`; the generated Ente WASM files are excluded, while their handwritten wrapper is checked. Inline ESLint suppression is disallowed. TypeScript uses Ente's stricter Next.js options, including checked array access, unused locals and parameters, and explicit type-only imports.

ESLint recognizes App Router metadata and the icon factory as Fast Refresh exports. The standalone React lint plugin needs a targeted ESLint peer override and Ente's compatibility shim until its peer range includes ESLint 10.

Keep changes focused and do not add code comments. Shared workspace configuration, Pages Router conversion, and the Rust PDF exporter remain part of the later monorepo migration.
