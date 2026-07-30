---
title: CLI (Command Line Interface)
description: Ente's command-line tool for advanced users
---

# CLI (Command Line Interface)

The Ente CLI is a command-line tool for advanced users that provides programmatic access to Ente Photos. It's particularly useful for automation, server environments, and power users who prefer terminal-based tools.

## What is the CLI?

The Ente CLI allows you to:

- Export your entire library or specific albums to local storage
- Set up automated exports with cron jobs
- Sync data to NAS or other storage systems
- Perform bulk operations programmatically

## Why use the CLI?

The CLI is particularly useful for:

- **Regular automated backups** to local/NAS storage
- **Server-to-server transfers** without a GUI
- **Power users** who prefer command-line tools
- **Scheduled tasks** using cron or similar schedulers
- **Scripting and automation** workflows

## Installation

Ente's CLI is distributed directly over [GitHub](https://github.com/ente/ente/releases?q=tag%3Acli-v0).

**Steps:**

1. Go to the [CLI releases page](https://github.com/ente/ente/releases?q=tag%3Acli-v0)
2. Download the appropriate version for your platform:
    - Linux (x64, ARM64)
    - macOS (Intel, Apple Silicon)
    - Windows (x64)
3. Follow the installation instructions in the [CLI README](https://github.com/ente/ente/tree/main/cli#readme)

## Basic usage

### Authentication

Before using the CLI, you need to authenticate:

```sh
ente account login
```

This will prompt for your email and password, then store your session securely.

### Exporting photos

The CLI supports **incremental exports**, downloading only new or changed files. Set or change the destination directory per account, then run the export:

```sh
# Configure the export directory for your account (run once)
ente account update --app photos --email you@example.com --dir /path/to/backup

# Export all photos to the configured directory
ente export

# Export specific albums
ente export --albums "Album Name","Another Album"
```

**Key features:**

- Incremental exports (only new/changed files)
- Gracefully handles interruptions
- Safe to stop and restart without re-downloading
- Preserves album structure and metadata

For complete command documentation, see the [CLI README](https://github.com/ente/ente/tree/main/cli#readme).

## Automated exports

### Setting up cron jobs

You can automate exports using cron (Linux/macOS) or Task Scheduler (Windows).

Set the export directory for the account once (outside cron) and then schedule `ente export`:

```sh
# Run once to set the directory the export job should use
/usr/local/bin/ente account update --app photos --email you@example.com --dir /nas/ente-backup

# Daily export at 2 AM
0 2 * * * /usr/local/bin/ente export
```

**Steps to set up:**

1. Open crontab editor: `crontab -e`
2. Add the cron job line
3. Save and exit
4. Verify with: `crontab -l`

### NAS sync setup

The recommended approach for keeping NAS and Ente synced is to use the CLI to **pull data from Ente to your NAS**:

**Setup:**

1. Install the CLI on your NAS or a machine that can access it
2. Authenticate the CLI with your Ente account
3. Set up a cron job to run periodic exports
4. Use the CLI's incremental export feature to keep data synced

**Example for daily NAS sync:**

```sh
/usr/local/bin/ente account update --app photos --email you@example.com --dir /nas/ente-backup
0 2 * * * /usr/local/bin/ente export
```

> [!IMPORTANT]
>
> Two-way sync is not currently supported. The CLI only pulls data from Ente to local storage - changes to local files won't sync back to Ente.

## Export details

### Album structure preservation

Exports maintain your exact album structure from Ente. Each album becomes a separate folder.

### Metadata handling

Metadata is exported as JSON files in the same format as Google Takeout, making it compatible with tools that support Google Takeout imports.

**Format:**

```
photo.jpg
.meta/photo.jpg.json
```

Learn more in the [Export feature guide](/photos/features/backup-and-sync/export).

## CLI vs Desktop export

| Feature         | CLI                      | Desktop App          |
| --------------- | ------------------------ | -------------------- |
| Platform        | All platforms (terminal) | Desktop GUI          |
| Automation      | ✅ Cron jobs, scripts    | ✅ Continuous export |
| Server use      | ✅ Headless servers      | ❌ Requires GUI      |
| Album selection | Command line flags       | GUI settings         |
| Incremental     | ✅                       | ✅                   |
| Metadata        | ✅                       | ✅                   |

**When to use CLI:**

- Server environments without GUI
- Scheduled automated backups
- Custom scripting workflows
- Power users who prefer terminal

**When to use Desktop:**

- Visual interface preferred
- Continuous background export
- One-time setup without scripting

## Source code and development

The CLI is open source and part of the Ente project:

- **Source code**: [GitHub](https://github.com/ente/ente/tree/main/cli)
- **Documentation**: [CLI README](https://github.com/ente/ente/tree/main/cli#readme)
- **Report issues**: [GitHub Issues](https://github.com/ente/ente/issues)

You can review, contribute to, or extend the CLI for your specific needs.

## Related FAQs

- [What is the Ente CLI?](/photos/faq/advanced-features#what-is-cli)
- [How do I install the CLI?](/photos/faq/advanced-features#install-cli)
- [How do I export photos with CLI?](/photos/faq/advanced-features#cli-export-photos)
- [How do I sync NAS and Ente?](/photos/faq/advanced-features#nas-sync)
- [CLI not found after installation](/photos/faq/advanced-features#cli-not-found)
- [CLI authentication issues](/photos/faq/advanced-features#cli-auth-issues)
- [CLI export interruptions](/photos/faq/advanced-features#cli-export-interruptions)
- [NAS export issues with CLI](/photos/faq/advanced-features#cli-nas-export)

## Related topics

- [Export](/photos/features/backup-and-sync/export) - Desktop export feature
- [Watch folders](/photos/features/backup-and-sync/watch-folders) - Automatic uploads
