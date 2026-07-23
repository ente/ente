# Ente Photos Documentation Style Guide

This guide ensures consistency across all Ente Photos documentation.

## Voice and Tone

### Use "Ente" or "Ente Photos"

- ✅ "Ente backs up your photos automatically"
- ✅ "Ente Photos provides end-to-end encryption"
- ❌ "We back up your photos" (except in support/personal contexts)

**Exception**: Use "we" when:

- Offering support ("we'll be happy to help")
- Making commitments ("we store 3 copies")
- Explaining company decisions ("we chose this approach because...")

### Imperative voice for instructions

- ✅ "Open Settings and select Backup"
- ❌ "You can open Settings and select Backup"
- ❌ "Users should open Settings"

## Terminology Standards

### UI Elements

- **Menu icon**: The three horizontal lines (☰) at top left
- **Overflow menu**: The three dots (...) button
- **Info button**: The (i) icon

### Feature Names (Use exact capitalization)

- **Settings** (not "settings" or "Preferences" on mobile)
- **Preferences** (only on desktop)
- **Backup** (not "backup" or "Back up" when referring to the feature)
- **Albums** (capitalize when referring to the section)
- **Uncategorized** (capitalize - it's a special album)
- **Trash** (capitalize - it's a special section)
- **Hidden** (capitalize when referring to the special section)
- **Archive** (capitalize when referring to the section)

### Platform Names

- **iOS** (not "IOS" or "ios")
- **Android** (capitalize)
- **macOS** (not "Mac OS" or "MacOS")
- **Windows** (capitalize)
- **Linux** (capitalize)

### Action Consistency

- **Tap** (mobile) vs. **Click** (desktop/web)
- **Open** (for UI elements, menus, settings, tabs, sections)
    - ✅ "Open `Settings > Backup`"
    - ✅ "Open the Albums tab"
    - ✅ "Open sharing settings"
    - ❌ "Go to Settings" (use "Open" instead)
    - ❌ "Navigate to the Albums tab" (use "Open" instead)
    - **Exception**: "Go to [URL]" is acceptable when directing users to external websites
- **Select** (for choosing from options)
- **Enable/Disable** (for toggles)
- **Enter** (for text input)

### Path Navigation

Use consistent format with `>` separator:

- **Settings > Backup > Backed up folders** (mobile)
- **Settings > Machine learning** (mobile)
- **Preferences > Machine learning** (desktop)

### Links and References

- **"Learn more"** (standard phrase for linking to detailed guides)
    - ✅ "Learn more in the [Feature guide](#)"
    - ✅ "Learn more about [Topic](#)"
    - ❌ "For more details, see..." (use "Learn more" instead)
    - ❌ "Read more here:" (use "Learn more" instead)
    - ❌ "See more at..." (use "Learn more" instead)
- **"See [Page Name](#)"** (for direct references in prose)
- **Internal links**: Always use title case for link text

## Formatting Standards

### Headings

- H1 (`#`): Page title only
- H2 (`##`): Major sections
- H3 (`###`): Subsections / FAQ questions
- H4 (`####`): Sub-subsections (use sparingly)

**Spacing**: H3 headings automatically have increased top margin (48px) for better visual separation between sections, especially important in FAQ pages with many consecutive questions. This is handled by CSS - no manual spacing needed.

### Emphasis

- **Bold**: UI elements, section labels (e.g. "**On mobile:**")
- _Italic_: Emphasis, terminology introduction (use sparingly)
- `Code`: File paths, commands, technical values

### Lists

- Use `-` for unordered lists (consistent)
- Use `1.` for numbered steps
- Use sub-bullets for nested information

### Code Blocks

Always specify language:

````markdown
```sh
command here
```
````

````

### FAQ Question Format
Always use H3 with mandatory anchor for deep linking:
```markdown
### Question text here? {#your-anchor-id}
````

**Anchor ID requirements:**

- Use lowercase letters, numbers, and hyphens only
- Make anchors descriptive and meaningful
- Must be unique across ALL FAQ files (not just within one file)
- ✅ `{#enable-face-recognition-ml}`
- ✅ `{#backup-slow-speed}`
- ❌ `{#faq1}` (not descriptive)
- ❌ Duplicate anchors across different FAQ files

**Testing for duplicates:**

```sh
# Run this command to check for duplicate anchor IDs:
grep -rh "{#[a-z0-9-]*}" docs/photos/faq/*.md | sed 's/.*{#\([^}]*\)}.*/\1/' | sort | uniq -d
```

## Content Structure

### Feature Pages

Should include:

1. Title and brief description
2. Main content sections
3. Platform-specific instructions (if applicable)
4. **Related FAQs** section at bottom

### FAQ Pages

Should include:

1. Title
2. Groups of related questions (H2 sections)
3. Questions as H3
4. Clear, concise answers with links to detailed guides
5. **Related Features** section at bottom (optional)

### Getting Started Pages

Should include:

1. Title and context
2. Step-by-step instructions
3. Platform-specific notes
4. **FAQs** section
5. **Next steps** section

## Cross-Linking Best Practices

### Always link to:

- Related feature pages from FAQ answers
- Related FAQ from feature pages
- Next logical steps in getting started guides
- Troubleshooting from relevant feature pages

### Link text should:

- Be descriptive (not "click here")
- Use the target page's title
- Be consistent across the docs

## Platform-Specific Guidance

When providing platform-specific instructions, use bold headers:

```markdown
**On mobile:**

1. Open `Settings > Backup`
2. Select the albums to back up

**On desktop:**

1. Open `Preferences > Backup`
2. Configure watch folders

**On web:**

1. Click the menu icon
2. Select Export
```

**Platform header variations:**

- `**On mobile:**` - Generic mobile (both iOS and Android)
- `**On iOS:**` - iOS-specific instructions
- `**On Android:**` - Android-specific instructions
- `**On desktop:**` - Desktop app (all platforms)
- `**On web:**` - Web browser interface
- `**On web/desktop:**` - When instructions are identical for web and desktop
- `**On mobile and web:**` - When instructions are identical for mobile and web

**Always bold the platform headers** - never use plain text like "On mobile:" without bold formatting.

## Common Patterns

### Prerequisites

When needed, start with:

```markdown
**Prerequisites:**

- Item one
- Item two
```

### Time Estimates

Include when relevant:

```markdown
This may take 10-30 minutes for large libraries.
```

### Callouts

Use GitHub-style alerts (`> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`) for callouts.

```markdown
> [!NOTE]
>
> This feature is available on mobile apps starting v0.9.98.
```

## Examples

### Good Example

```markdown
### How do I enable face recognition? {#enable-face-recognition-example}

**On mobile:**

1. Open `Settings > Machine learning`
2. Enable "Face recognition"
3. Wait for indexing to complete

**On desktop:**

1. Open `Preferences > Machine learning`
2. Enable "Face recognition"
3. Monitor indexing progress

The app will download your photos to index them. This is faster over WiFi.

Learn more in the [Machine learning guide](/photos/features/search-and-discovery/machine-learning).
```

### Bad Example

```markdown
### How to enable face recognition?

On mobile you can enable face recognition in the settings. Go to the three horizontal lines button at the top left, then you'll find Machine learning where you can enable it.

For more details, see: /photos/features/search-and-discovery/machine-learning
```

**What's wrong with the bad example:**

- ❌ Missing anchor ID (should have `{#unique-anchor-id}`)
- ❌ "Go to" instead of "Open"
- ❌ Platform header not bolded
- ❌ "For more details, see" instead of "Learn more"
- ❌ Lacks clear numbered steps
- ❌ Missing code formatting for Settings paths

## Checklist for New Content

### General

- [ ] Used consistent terminology from this guide
- [ ] Followed formatting standards
- [ ] Used imperative voice for instructions ("Open Settings" not "You can open Settings")
- [ ] Used proper heading hierarchy (H1 → H2 → H3)

### FAQ-Specific

- [ ] All H3 questions have unique anchor IDs (format: `{#descriptive-anchor}`)
- [ ] Verified no duplicate anchor IDs across all FAQ files (run the grep command)
- [ ] Used "Open" for UI navigation (not "Go to" or "Navigate to")
- [ ] Platform headers are bold: `**On mobile:**` `**On desktop:**` `**On web:**`
- [ ] Settings paths use code format: `` `Settings > Backup > Folders` ``

### Links and Cross-References

- [ ] Used "Learn more" consistently (not "See more", "For more details", "Read more")
- [ ] Added cross-links to related feature pages
- [ ] Checked all internal links work correctly
- [ ] Link text uses title case and is descriptive

### Platform Instructions

- [ ] Specified platforms where relevant with bold headers
- [ ] Provided mobile, desktop, and/or web instructions as needed
- [ ] Used platform-appropriate action verbs (Tap vs Click)
