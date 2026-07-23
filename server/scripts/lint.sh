#!/bin/sh

# Run the configured linters.
#
# These checks will run when a PR is opened and new commits are pushed, but it
# can also be run locally.

set -o errexit
set -o xtrace

unformatted="$(gofmt -l .)"
test -z "$unformatted" || { printf '%s\n' "$unformatted"; exit 1; }
go vet ./...
go run honnef.co/go/tools/cmd/staticcheck@v0.6.1 ./...
go run golang.org/x/vuln/cmd/govulncheck@v1.5.0 ./...
