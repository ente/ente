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

## Filter and sort files

```sh
ente photos file list --type video --since 2024-01-01 --before 2025-01-01
ente photos file list --search "beach sunset" --no-location
ente photos file list --sort size --limit 20
ente photos file list --type video --min-size 500MB
```

- `--type` takes `image`, `video` or `livephoto`; repeat it to include several types.
- `--since` and `--before` compare `createdAt`, which includes dates edited in Ente. `--since` includes the given instant and `--before` excludes it. Both accept `YYYY-MM-DD` (midnight UTC) or RFC 3339 with a timezone, such as `2024-06-01T00:00:00+02:00`.
- `--search` finds files where every word occurs in either the name or the caption, ignoring case.
- `--no-location` keeps files without a location.
- `--min-size` and `--max-size` keep files whose `sizeBytes` is at least or at most the given size. Both accept KB, MB or GB in powers of 1024, such as `500KB`, `100MB` or `1.5GB`. `sizeBytes` is the size of the stored encrypted file, slightly larger than the original. Files with an unknown size are left out.

A file must match every filter you pass. `--sort created` lists the newest files first and `--sort size` the largest first; add `--reverse` for the opposite order. Files with an unknown size sort as the smallest, and ties keep ID order. Without `--sort`, files are listed by ID.

## Find files by place

```sh
ente photos place list
ente photos place list --countries --album Holidays
ente photos file list --place lisbon
ente photos file list --country JP --type video
```

`place list` shows the cities where your files were taken, with the number of files in each, most first. `--countries` lists countries instead. Places come from each file's location; files without one are not counted. Locations that match no city or country in the dataset are omitted from that list, so city and country totals can differ. Country filters use the groups shown by `place list --countries`, which can differ from a city's country. For example, photos in French Guiana count under France.

`--place` keeps files taken in a city whose name contains the given text. When one of the cities `place list` shows for the same `--album` has exactly that name, only cities with that name match, so `--place nice` leaves out Venice. `--country` takes a two-letter code such as `PT`, or a full English country name, which matches only that country, so `--country niger` leaves out Nigeria; other text matches every country whose name contains it. `UK` also works for the United Kingdom, whose code is `GB`, and an unknown two-letter code is an error. Both ignore case and accent marks, and combine with the other filters. Type letters such as ł or ø as `place list` shows them: `--place wrocław` finds Wrocław, but `--place wroclaw` does not.

The first time you use places, the CLI downloads about 7 MB of location data from Ente (`assets.ente.com`) and keeps it in the CLI home, where all your accounts share it. After that, places work with `--offline`. The location data is adapted from [GeoNames](https://www.geonames.org/) and the European Commission Joint Research Centre's [GHS-UCDB R2024A](https://doi.org/10.2905/1a338be6-7eaf-480c-9664-3a8ade88cbcd), both under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), and from [Natural Earth](https://www.naturalearthdata.com/), which is in the public domain.

## Check storage and file count

```sh
ente photos usage
```

```
Email   alice@example.com
Total   20 GB
Used    3.61 GB
Free    16.39 GB
Plan    10 GB
Status  active
Bonus   10 GB
Files   339
Family  none
```

`Total` is the plan plus bonuses such as referrals, `Used` and `Files` are what Photos holds, and `Status` says whether the plan is active or expired. In a family the plan and total are the family admin's, and `Family` lists its members, followed by the shared totals and your own limit when the admin has set one.

## Read as JSON

Lists return arrays and `view` returns one object. IDs are strings; timestamps are RFC 3339 strings in UTC.

| Command                    | Fields                                                                                                                                                                                                                                                                           |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `album list`, `album view` | `id`, `name`, `type` (`album`, `folder`, `favorites`, `uncategorized`, `defaultHidden`, `quicklink`), `visibility` (`visible`, `archived`, `hidden`), `ownerId`, `updatedAt`                                                                                                     |
| `file list`, `file view`   | `id`, `name`, `type` (`image`, `video`, `livephoto`), `ownerId`, `albumIds`, `createdAt`, `updatedAt`; nullable `modifiedAt`, `location` (`latitude`, `longitude`), `caption`, `hash`, `dateTime`, `offsetTime`, `visibility`, `durationSeconds`, `width`, `height`, `sizeBytes` |
| `file download`            | `id`, `output`, `bytes`                                                                                                                                                                                                                                                          |
| `place list`               | `name`, `country`, `countryCode`, `latitude` and `longitude` (the city's position), `fileCount`                                                                                                                                                                                  |
| `place list --countries`   | `name`, `code`, `fileCount`                                                                                                                                                                                                                                                      |
| `usage`                    | `email`, `planExpiresAt`, `planActive`, `totalBytes`, `usedBytes`, `freeBytes`, `planBytes`, `bonusBytes`; nullable `files`, `family` (`usedBytes`, `storageBytes`, `members`: `email`, `status`, `admin`, `usedBytes`, `storageLimitBytes`)                                     |
| `export`                   | See [Automation](./automation.md#export-summary)                                                                                                                                                                                                                                 |

## Read offline

`album list`, `album view`, `file list`, `file view` and `place list` work with `--offline` using the metadata an earlier online run synced. An online `album list` syncs albums only; run `file list` online for each album whose files you want to read offline. Places also need the location data that an earlier online `place list`, `--place` or `--country` downloaded. Export, download and usage need the network.

## Limits

- The CLI does not import or upload photos.
- Up to 16 files are processed at once; change that with `--jobs N`.
- A non-empty destination must already be an export.
