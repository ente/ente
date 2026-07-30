#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "prepare_fdroid_source: $*" >&2
    exit 1
}

remove_direct_dependencies() {
    local count
    count=$(rg -c "^  (firebase_core|firebase_messaging|in_app_purchase):" pubspec.yaml || true)
    [[ "$count" == "3" ]] || fail "expected three restricted dependencies in pubspec.yaml"
    perl -0pi -e 's/^  (firebase_core|firebase_messaging|in_app_purchase):[^\n]*\n//mg' pubspec.yaml
}

remove_playstore_sources() {
    ../../packages/install_source/scripts/prepare_fdroid_source.sh
}

copy_fdroid_overlay() {
    cp -R fdroid/overlay/lib/. lib/
}

assert_fdroid_source() {
    if rg -n "package:(firebase_core|firebase_messaging|in_app_purchase)" lib pubspec.yaml; then
        fail "restricted package imports or direct dependencies remain"
    fi

    if rg -n "FirebaseMessaging|Firebase\\.initializeApp|RemoteMessage|InAppPurchase|PurchaseStatus" lib; then
        fail "restricted Firebase or in-app purchase references remain"
    fi

    if rg -n "com\\.android\\.installreferrer|InstallReferrer(Client|StateListener)|installreferrer" android/app/build.gradle android/app/src ../../packages/install_source/android; then
        fail "Play install referrer dependency or source remains"
    fi
}

remove_direct_dependencies
remove_playstore_sources
copy_fdroid_overlay
assert_fdroid_source
