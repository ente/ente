Generate random keys that can be used in the museum configuration file.

## Details

This tool can be used to generate new random values for various cryptographic secrets that should be overridden in `configuration/local.yaml` when running a new instance of museum.

```sh
go run tools/gen-random-keys/main.go
```
