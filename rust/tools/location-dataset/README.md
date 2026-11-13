# ente-location-dataset

Host-side generator for the assets consumed by `ente-location`.

```sh
cargo run --release -p ente-location-dataset -- \
  build --output /tmp/ente-location
```

The command downloads and caches its sources, writes `cities.bin`,
`urban-centres.bin`, `countries.bin`, and `disputes.bin`, and prints their
sizes and SHA-256 hashes.

## Attribution

- [GeoNames](https://www.geonames.org/) `cities5000`, `countryInfo`, and
  `alternateNamesV2`: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/),
  adapted by Ente.
- European Commission Joint Research Centre
  [GHS-UCDB R2024A](https://doi.org/10.2905/1a338be6-7eaf-480c-9664-3a8ade88cbcd):
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), adapted by Ente.
- [Natural Earth](https://www.naturalearthdata.com/) country boundaries and
  populated places: public domain.
