Find all pending multipart uploads, and abort any of them that are older than x days.

This shouldn't be needed in practice since we already track and clear temp_objects. However, in rare cases it might happen that museum gets restarted in the middle of a multipart replication. This tool can be used to list and clean up such stale replication attempts.

## Running

```sh
go run tools/abort-unfinished-multipart-uploads/main.go \
  --profile my-profile --endpoint-url https://s3.example.org --bucket my-bucket
```

For more details, see `ParseAndCreateSession`.

To see all the uploads which'll get aborted, you can

```sh
go run tools/abort-unfinished-multipart-uploads/main.go \
  --profile p --endpoint-url e --bucket b | grep 'Dry run:'
```
