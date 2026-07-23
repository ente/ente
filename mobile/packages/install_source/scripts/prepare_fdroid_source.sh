#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "prepare_fdroid_source: $*" >&2
    exit 1
}

remove_play_referrer_dependency() {
    local count
    count=$(rg -c "^[[:space:]]*playstoreImplementation ['\"]com\\.android\\.installreferrer:installreferrer:" android/build.gradle || true)
    [[ "$count" == "1" ]] || fail "expected one Play install referrer dependency in android/build.gradle"
    perl -0pi -e 's/^[[:space:]]*playstoreImplementation ['\''"]com\.android\.installreferrer:installreferrer:[^'\''"]+['\''"]\n//mg' android/build.gradle
}

remove_playstore_sources() {
    rm -rf android/src/playstore/kotlin
}

assert_fdroid_source() {
    if rg -n "com\\.android\\.installreferrer|InstallReferrer(Client|StateListener)|installreferrer" android; then
        fail "Play install referrer dependency or source remains"
    fi
}

remove_play_referrer_dependency
remove_playstore_sources
assert_fdroid_source
