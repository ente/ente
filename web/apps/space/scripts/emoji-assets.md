# Space emoji assets

The picker is Space UI. Its English names, keywords and categories
come from Emojibase Data 17.0.0 (MIT). Fully qualified sequences
come from Unicode's Emoji 17.0 test data (Unicode License V3). Artwork comes from Noto
Emoji v2.051, commit `8998f5dd683424a73e2314a8c1f1e359c19e8742` (Apache 2.0;
region flags have separate public-domain notices). Both cover Emoji 17.0.

The generator rasterizes the SVG artwork at 64 pixels into lossless WebP sheets.
Space serves these files locally; no external service receives picker searches or
reaction values. Licenses are included alongside the generated artwork.

To regenerate from the repository root:

```sh
mkdir -p /tmp/space-emoji-data
curl -fL https://cdn.jsdelivr.net/npm/emojibase-data@17.0.0/en/data.json -o /tmp/space-emoji-data/en-data.json
curl -fL https://cdn.jsdelivr.net/npm/emojibase-data@17.0.0/LICENSE -o /tmp/space-emoji-data/LICENSE
curl -fL https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt -o /tmp/space-emoji-data/emoji-test.txt
curl -fL https://www.unicode.org/license.txt -o /tmp/space-emoji-data/UNICODE-LICENSE.txt
curl -fL https://www.apache.org/licenses/LICENSE-2.0.txt -o /tmp/space-emoji-data/APACHE-LICENSE.txt
git clone --depth 1 --branch v2.051 https://github.com/googlefonts/noto-emoji.git /tmp/space-noto-emoji
node web/apps/space/scripts/generate-emoji-assets.mts /tmp/space-emoji-data /tmp/space-noto-emoji
```

The same run writes the Rust outgoing reaction catalog. Keep this catalog, the
web search catalog and artwork together when upgrading. Persist encrypted Unicode
strings, never image paths or sheet positions. Readers accept bounded values from
newer clients, falling back to Unicode when local artwork is unavailable. Native
clients can use the same Rust validation and choose their own picker and renderer.
