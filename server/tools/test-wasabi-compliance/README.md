Run through the process of using [Wasabi's compliance feature](https://wasabi.com/wp-content/themes/wasabi/docs/API_Guide/index.html#t=topics%2FCompliance.htm&rhsyns=%20) to ensure that it does indeed behave the way we expect it to.

Also acts as a test for the code in `pkg/external/wasabi`.

## What does it do?

The command runs through the two checklist:

- First checklist is for enabling compliance on the bucket, adding a new object, and then disabling the conditional hold on that object (See `Sequence 1` for the full sequence that'll be run through).

- Second checklist is for deleting the object. This checklist can be executed by running the command with the `--only-delete` flag (See `Sequence 2` for the full sequence).

Since the minimum retention duration is 1 day, these two checklists need to be manually run through after the requisite gap.

## Running

Use the `--profile` flag (or set the `AWS_PROFILE` environment variable) to specify which AWS config and credentials to use:

```sh
go run tools/test-wasabi-compliance/main.go --profile my-test-profile
```

For more details about how to profiles work, or alternative ways to provide credentials, see the documentation for `ParseAndCreateSession`.
