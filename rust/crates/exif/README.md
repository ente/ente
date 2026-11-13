# ente-exif

Reads EXIF, XMP and IPTC metadata without decoding image pixels. XMP sidecars must
be supplied explicitly; the crate does not discover adjacent files or write
metadata.

## Intended usage and policy

- Use decoder output dimensions directly when available; do not apply metadata
  orientation to them again.
- Callers choose location and caption source precedence, upload storage mapping,
  and how to pair separate live-photo files.
- Extracted motion-video byte ranges may include vendor trailer bytes. Finding a
  range does not establish playback support.
- Keep local capture time, embedded timezone offset and resolved epoch separate.
  Unknown offsets remain unknown. Applications may resolve local times using
  their timezone and daylight-saving rules, or reject a capture-date candidate.
  An assumed offset must not replace the embedded offset.
- Capture-date selection normalizes partial dates to the start of their period at
  midnight UTC without inventing an embedded offset. Reading an individual date
  source preserves its precision without this normalization.
- Choose a fallback text encoding explicitly when metadata does not declare one.

## Limitations

Read, decompression and retention budgets constrain parser work, not exact
process memory. I/O errors and exhausted budgets stop parsing. Recoverable
malformed metadata is reported separately; inspect reported issues before
treating a result as complete.

BigTIFF, manufacturer MakerNotes and non-TIFF RAW adapters are unsupported. JPEG
scanning ends at the first image scan. PNG CRCs and extended-XMP GUID digests are
not authenticated. Structured XMP is not a complete RDF graph or a typed
face-region API.

## Development

From `rust/`:

```sh
cargo test --locked -p ente-exif
cargo test --locked -p ente-exif --test integration jxl::
cargo run --release --locked -p ente-exif --example inspect -- photo.heic
cargo run --release --locked -p ente-exif --example extract_motion -- photo.jpg motion.mp4
```

Tests generate metadata containers in memory; no downloads or external fixtures
are needed. See [fixture rules and references](tests/README.md). Shared lint and
build commands are in the [workspace README](../../README.md).
