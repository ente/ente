# ente-location-dataset

Host-side generator for the assets consumed by `ente-location`.

```sh
cargo run --release -p ente-location-dataset -- \
  build --output /tmp/ente-location
```

The command downloads and caches its sources, writes `cities.bin`,
`countries.bin`, and `disputes.bin`, and prints their sizes and SHA-256 hashes.

## Source

City data is derived from [GeoNames](https://www.geonames.org/) `cities5000`
and `countryInfo`, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Ente filters and
converts the data, which is provided without warranty.

Country boundaries are derived from [Natural Earth](https://www.naturalearthdata.com/),
which is in the public domain.
