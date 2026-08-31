#!/bin/bash

# Add credentials in integration_test/app_init_test.dart. Configure
# app_init_summary and the output filename in test_driver/perf_driver.dart.
# --keep-app-running lets later runs use the already logged-in app.

export ENDPOINT="https://api.ente.com"

flutter drive \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/app_init_test.dart \
  --dart-define=endpoint=$ENDPOINT \
  --profile --flavor independent \
  --no-dds \
  --keep-app-running

exit $?
