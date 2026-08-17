#!/bin/bash

# Add credentials in integration_test/home_gallery_scroll_test.dart.
# Configure home_gallery_scrolling_summary and the output filename in
# test_driver/perf_driver.dart.

export ENDPOINT="https://api.ente.com"

flutter drive \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/home_gallery_scroll_test.dart \
  --dart-define=endpoint=$ENDPOINT \
  --profile --flavor independent \
  --no-dds

exit $?
