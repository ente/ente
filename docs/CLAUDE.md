# CLAUDE.md

Documentation for Ente's products published at [ente.com/help](https://ente.com/help). Built with VitePress.

## Development commands

```sh
npm ci          # Install dependencies
npm run dev     # Start local dev server
npm run build   # Build for production
```

Use `npm install` only when intentionally adding or updating dependencies, or if `package-lock.json` has not changed since the last `npm ci`.

## Commit messages

Keep commit messages brief — one-liners unless asked otherwise. No emojis, no promotional text or links, no Co-Authored-By lines.

## Sidebar

New pages must be added by hand to `docs/.vitepress/sidebar.ts` — VitePress does not auto-generate the sidebar.

## Style guide

Full guide: `docs/photos/STYLE_GUIDE.md`. Key conventions:

Voice and terminology:

- Imperative voice: "Open Settings", not "You can open Settings".
- "Open" for navigation, not "Go to" or "Navigate to".
- "Tap" on mobile, "Click" on desktop and web.
- Settings paths are code-formatted with `>`, e.g. `` `Settings > Backup > Folders` ``.

Platform instructions use bold headers: `**On mobile:**`, `**On desktop:**`, `**On web:**`, `**On iOS:**`, and so on.

FAQ questions need unique anchor IDs: `### Question? {#descriptive-anchor-id}`. Use descriptive IDs (`{#enable-face-recognition-ml}`, not `{#faq1}`), and keep them unique across all FAQ files. Check for duplicates with:

```sh
grep -rh "{#[a-z0-9-]*}" docs/photos/faq/*.md | sed 's/.*{#\([^}]*\)}.*/\1/' | sort | uniq -d
```

Links: use "Learn more", not "See more", "For more details", or "Read more".
