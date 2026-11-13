# Test fixtures

Generate small inputs from format specifications and explicit API contracts, with
independently calculable expected values. Use common scenarios or independently
documented behavior; do not copy fixtures or distinctive cases from other projects.
Malformed lengths, truncations, cycles and budgets exercise parser invariants.

One integration-test binary shares the fixture builders. The inputs describe
metadata layouts, not fully decodable media: PNG CRCs and video sample tables are
not populated. Motion tests establish byte ranges, not playback or proprietary
vendor conformance. Truncation/mutation sweeps are deterministic regression checks,
not coverage-guided fuzzing.

## References

- ISO/IEC 18181-1:2024 Annex D and 18181-2:2021 clauses 8–9: JPEG XL
  dimensions/orientation, boxes and ordered partial codestreams.
- [RFC 7932 §§9.1–9.3](https://www.rfc-editor.org/rfc/rfc7932.html): Brotli windows
  and stored blocks. The inline compressed sample is its test XML plus 40,000
  spaces, generated with `brotli -q 5 -w 16`; tests need no encoder.
- [PNG textual profiles](https://exiftool.org/TagNames/PNG.html#TextualData) and
  [Exiv2's metadata book](https://clanmills.com/exiv2/book/#PNG): ImageMagick raw profiles.
- [WHATWG Windows-1252](https://encoding.spec.whatwg.org/index-windows-1252.txt):
  explicit legacy decoding, a caller compatibility choice for TIFF ASCII fields.
- [XML namespaces](https://www.w3.org/TR/xml-names/) §§2, 6 and
  [RDF/XML](https://www.w3.org/TR/rdf-syntax-grammar/) §§2.5, 2.7, 2.11, 2.15:
  namespace identity, attributes, languages, structures and list ownership.
- [Adobe XMP](https://developer.adobe.com/xmp/docs/) and
  [date types](https://developer.adobe.com/xmp/docs/xmp-namespaces/xmp-data-types/):
  shared photo fields and date precision. Missing timezones remain unknown;
  capture-date normalization is this library's policy.
- [CIPA EXIF specifications](https://www.cipa.jp/e/std/std-sec.html) and
  [Exif 2.32 §4.6.6 F](https://www.cipa.jp/std/documents/e/DC-X008-Translation-2019-E.pdf):
  GPS coordinates, date families, subseconds and blank offsets.
- [HEIF](https://nokiatech.github.io/heif/technical.html) and
  [QuickTime clean aperture](https://developer.apple.com/documentation/quicktime-file-format/clean_aperture):
  primary-image properties and ordered transforms. Exact pixel crops and EXIF
  fallback without an active native orientation are library policies.
- [Motion Photo](https://developer.android.com/media/platform/motion-photo-format):
  Camera/Container fields, padding and appended video; not a legacy footer spec.
- [Google tag documentation](https://exiftool.org/TagNames/Google.html): opaque
  HDRPlusMakerNote data. Skipping it without exhausting retention is library policy.
- [Photoshop resources](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/):
  resource IDs, lengths and padding.
- [PNG text](https://www.w3.org/TR/png-3/#11keywords): keywords and text encodings.
- [IPTC IIM 4.2](https://iptc.org/std/IIM/4.2/specification/IIMV4.2.pdf): headers,
  values, UTF-8 announcements and record scope. Accepting a zero-filled trailing
  region, while rejecting nonzero malformed tails, is library policy.
