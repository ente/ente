# Photos

Export your library to a directory:

```sh
ente photos export "$HOME/Pictures/Ente"
```

Progress goes to the terminal while originals download:

```
Refreshing album metadata.
Refreshing selected albums and Favorites.
Maintaining 1200 selected copies.
Completed 480/1200 selected copies.
/home/alice/Pictures/Ente: 1200/1200 album copies complete, 1200 exported, 0 moved to Trash, 0 failures (0 conflicts).
```

An album copy is a photo placed in an album; a photo in two albums is two copies, and the summary counts copies. The command exits with status 0 when every copy is complete and 1 otherwise. Press Ctrl-C to stop; the next run continues where it left off.

## Choose albums

```sh
ente photos export "$HOME/Pictures/Ente" --album Holidays --album Family
ente photos export "$HOME/Pictures/Ente" --exclude-album Screenshots --exclude-shared --exclude-hidden
```

An album selector is an album ID or its exact, case-sensitive name; find both with `ente photos album list`. `--exclude-shared` leaves out albums owned by other accounts, and `--exclude-hidden` leaves out hidden albums; files hidden individually inside an exported album are still exported. Filters apply to the run you pass them to; files already exported from an album you now exclude stay where they are.

## Export layout

```
Ente/
├── export.json
├── Holidays/
│   ├── metadata.json
│   ├── IMG_0001.jpg
│   ├── IMG_0002.heic
│   ├── IMG_0002.mov
│   └── metadata/
│       ├── IMG_0001.jpg.json
│       ├── IMG_0002.heic.json
│       └── IMG_0002.mov.json
└── Trash/
    └── 2019 trip/
```

- `export.json` records which account the export belongs to in `userID`.
- `<Album>/metadata.json` is the album record: `title` and an `ente` object with `albumID`, `ownerID` and `type`. When `ownerID` equals the `userID` in `export.json`, you own the album.
- `<Album>/<file>` is the original. A Live Photo is exported as separate image and video files with the same name and different extensions.
- `<Album>/metadata/<file>.json` is the sidecar for one file: `title`, `photoTakenTime`, `geoData`, `description`, `favorited`, and an `ente` object with `fileID` and `type`.
- `Trash/` holds albums and files that were removed from your library or from an album since the last run.

Characters that are not portable across filesystems are replaced with `_` in names; a name that is already taken gets a numeric suffix such as `-1`.

## Keep an export updated

Run the same command again. Unchanged files are reused, new files are exported, renamed albums are renamed on disk, removed items move to `Trash/`, and every sidecar is regenerated. Edits you make to an exported original are protected: the CLI leaves the file alone, reports `conflict: at /home/alice/Pictures/Ente/Holidays/IMG_0001.jpg: locally changed media`, and counts it under `failures (conflicts)`. A file of your own that occupies a path the export needs is reported the same way and left alone. To take the library version again, move the edited file elsewhere and rerun; a missing original is downloaded again.

## Save space with hard links

```sh
ente photos export "$HOME/Pictures/Ente" --hardlinks
```

A photo that is in several albums is stored once and linked from each exported album folder; the copy it links to can also be in `Trash/` or in an album you no longer export. Linked files share contents, timestamps and permissions: editing one changes every copy. Later runs without the flag keep the links. The destination filesystem must support hard links.

## Reconnect or adopt an export

To adopt (`--adopt`) an export means to take over one made by the previous CLI or the Ente Photos desktop app, or to reconnect an export this CLI made after you moved it or lost the CLI home. Without the flag, the CLI refuses:

```
Error: cannot open Photos export /home/alice/Pictures/Ente: This folder contains an export from the old CLI or Ente Desktop. Use --adopt if you want to take it over.
```

1. Stop the previous CLI job or the desktop app's export.
2. Log in with the account that made the export.
3. Run `ente photos export "$HOME/Pictures/Ente" --adopt`, with the same album filters as before or none. The CLI checks the existing files before taking over.

The flag cannot adopt an arbitrary folder of photos; the folder must contain an export it recognises. Learn more in [Migration](./migration.md#take-over-a-photos-export).

## Find and download a file

```sh
ente photos album list
ente photos file list --album Holidays
ente photos file view IMG_0001.jpg
ente photos file download 1580559962386999 --output ./IMG_0001.jpg
```

A file selector is a file ID or an exact name; when several files share a name, the CLI lists the candidates and you pick an ID. Download prints `Downloaded "IMG_0001.jpg" to ./IMG_0001.jpg.` and refuses to overwrite an existing file. A Live Photo downloads as a ZIP archive. Lists show 100 results and then print `Showing first 100 results; use --limit N or --all to see more.` on the terminal.

## Read as JSON

Lists return arrays and `view` returns one object. IDs are strings; timestamps are RFC 3339 strings in UTC.

| Command                    | Fields                                                                                                                                                                                                                                                              |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `album list`, `album view` | `id`, `name`, `type` (`album`, `folder`, `favorites`, `uncategorized`, `defaultHidden`, `quicklink`), `visibility` (`visible`, `archived`, `hidden`), `ownerId`, `updatedAt`                                                                                        |
| `file list`, `file view`   | `id`, `name`, `type` (`image`, `video`, `livephoto`), `ownerId`, `albumIds`, `createdAt`, `updatedAt`; nullable `modifiedAt`, `location` (`latitude`, `longitude`), `caption`, `hash`, `dateTime`, `offsetTime`, `visibility`, `durationSeconds`, `width`, `height` |
| `file download`            | `id`, `output`, `bytes`                                                                                                                                                                                                                                             |
| `export`                   | See [Automation](./automation.md#export-summary)                                                                                                                                                                                                                    |

## Read offline

`album list`, `album view`, `file list` and `file view` work with `--offline` using the metadata an earlier online run synced. An online `album list` syncs albums only; run `file list` online for each album whose files you want to read offline. Export and download need the network.

## Limits

- The CLI does not import or upload photos.
- Up to 16 files are processed at once; change that with `--jobs N`.
- A non-empty destination must already be an export.
