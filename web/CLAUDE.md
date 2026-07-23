# CLAUDE.md

## Commit Message Guidelines

When making commits, follow these rules:

- Keep messages CONCISE (no walls of text)
- Subject line under 72 chars as a single sentence (no body text, no bullets, no lists)
- NO emojis
- NO promotional text or links
- NO Co-Authored-By lines
- ONLY run pre-commit checks (format, lint, typecheck, build) when explicitly creating a commit

Example:

```
Format markdown files with Prettier for consistent styling
```

## Commands

```sh
# Install dependencies from the committed lockfile
npm ci
# Fast path when the lock file has not changed since the last npm ci, OR when
# adding or updating dependencies.
npm install

# Run development servers
npm run dev          # Photos app (port 3000)
npm run dev:auth     # Auth app (port 3003)
# ...
npm run              # To see the full list of apps

# Production builds
npm run build        # Photos app
npm run build:auth   # Auth app
...

# Code quality. Run when:
# 1. Explicitly requested by user
# 2. Before creating a commit (pre-commit)
# Do not run automatically after file modifications
npm run lint          # Check formatting, linting, and TypeScript types
npm run lint:fix      # Auto-fix linting and formatting issues
```

## Structure

This is a monorepo containing multiple Ente web applications using npm workspaces.

Shared code goes in `packages/`. All apps use Next.js for static export except `payments`. Run `ls apps/` and `ls packages/` to see the full list.
