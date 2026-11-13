#!/bin/bash

LATEST_TAG=$(git describe --tags "$(git rev-list --tags='cli-*' --max-count=1)")

if [ -z "$LATEST_TAG" ]; then
    echo "No 'cli-' tag found. Exiting..."
    exit 1
fi
VERSION=${LATEST_TAG#cli-}
mkdir -p bin

OS_TARGETS=("windows" "linux" "darwin")

ARCH_TARGETS=("386 amd64" "386 amd64 arm arm64" "amd64 arm64")

export CGO_ENABLED=0
for index in "${!OS_TARGETS[@]}"
do
    OS=${OS_TARGETS[$index]}
    for ARCH in ${ARCH_TARGETS[$index]}
    do
        export GOOS="$OS"
        export GOARCH="$ARCH"

        BINARY_NAME="ente-$OS-$ARCH"

        if [ "$OS" == "windows" ]; then
            BINARY_NAME="ente-$OS-$ARCH.exe"
        fi

        go build -ldflags="-X main.AppVersion=${VERSION} -s -w" -trimpath -o "bin/$BINARY_NAME" main.go

        echo "Built for $OS ($ARCH) as bin/$BINARY_NAME"
    done
done

echo "Build process completed for all platforms and architectures. Binaries are in the 'bin' directory."
