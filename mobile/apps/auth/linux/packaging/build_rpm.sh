#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building Ente Auth RPM package${NC}"

# Get script directory (location of this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_ROOT"

# Extract version from pubspec.yaml
FULL_VERSION=$(grep -E "^version:" pubspec.yaml | cut -d' ' -f2)
VERSION=$(echo "$FULL_VERSION" | cut -d'+' -f1)
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Could not extract version from pubspec.yaml${NC}"
    exit 1
fi

echo -e "${YELLOW}Full Version: ${FULL_VERSION}${NC}"
echo -e "${YELLOW}RPM Version: ${VERSION}${NC}"

# Define directories
STAGING_DIR="dist/rpm-staging"
OUTPUT_DIR="dist/$FULL_VERSION"
BUNDLE_DIR="build/linux/x64/release/bundle"

# Clean up any existing staging directory
if [ -d "$STAGING_DIR" ]; then
    echo -e "${YELLOW}Cleaning existing staging directory...${NC}"
    rm -rf "$STAGING_DIR"
fi

# Create staging directories
echo -e "${YELLOW}Creating staging directories...${NC}"
mkdir -p "$STAGING_DIR/usr/share/enteauth"
mkdir -p "$STAGING_DIR/usr/share/metainfo"
mkdir -p "$STAGING_DIR/usr/share/pixmaps"
mkdir -p "$STAGING_DIR/usr/share/applications"
mkdir -p "$STAGING_DIR/usr/share/polkit-1/actions"
mkdir -p "$STAGING_DIR/usr/bin"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Verify build directory exists
if [ ! -d "$BUNDLE_DIR" ]; then
    echo -e "${RED}Error: Build directory not found at $BUNDLE_DIR${NC}"
    echo -e "${YELLOW}Please run 'flutter build linux --release' first${NC}"
    exit 1
fi

# Copy Flutter build files
echo -e "${YELLOW}Copying Flutter build files...${NC}"
cp -r "$BUNDLE_DIR"/* "$STAGING_DIR/usr/share/enteauth/"

# Copy metainfo file
echo -e "${YELLOW}Copying metainfo file...${NC}"
cp linux/packaging/enteauth.appdata.xml "$STAGING_DIR/usr/share/metainfo/"

# Copy icon
echo -e "${YELLOW}Copying icon...${NC}"
cp "assets/generation-icons/icon-windows-linux.png" "$STAGING_DIR/usr/share/pixmaps/io.ente.auth.png"

# Copy desktop file
echo -e "${YELLOW}Copying desktop file...${NC}"
cp linux/packaging/enteauth.desktop "$STAGING_DIR/usr/share/applications/"

# Copy Polkit policy.
echo -e "${YELLOW}Copying Polkit policy...${NC}"
install -D -m 0644 assets/polkit/com.ente.auth.policy "$STAGING_DIR/usr/share/polkit-1/actions/com.ente.auth.policy"

# Create symlink
echo -e "${YELLOW}Creating symlink...${NC}"
ln -s /usr/share/enteauth/enteauth "$STAGING_DIR/usr/bin/enteauth"

# Check if fpm is installed
if ! command -v fpm &> /dev/null; then
    echo -e "${RED}Error: fpm is not installed${NC}"
    echo -e "${YELLOW}Install it with: gem install fpm${NC}"
    exit 1
fi

# Build RPM package
echo -e "${YELLOW}Building RPM package...${NC}"
fpm -s dir -t rpm \
  -n enteauth \
  -v "$VERSION" \
  --vendor "Ente" \
  --maintainer "Ente Developers <auth@ente.com>" \
  --license "AGPLv3" \
  --url "https://github.com/ente/ente" \
  --description "2FA app with free end-to-end encrypted backup and sync" \
  --category "Application/Utility" \
  --depends sqlite-libs \
  --depends libsecret \
  --depends libappindicator \
  --depends polkit \
  -C "$STAGING_DIR" \
  -p "$OUTPUT_DIR/enteauth-VERSION.ARCH.rpm" \
  .

# Clean up staging directory
echo -e "${YELLOW}Cleaning up staging directory...${NC}"
rm -rf "$STAGING_DIR"

# Display success message
RPM_FILE=$(ls "$OUTPUT_DIR"/enteauth-*.rpm 2>/dev/null | head -n1)
if [ -f "$RPM_FILE" ]; then
    RPM_SIZE=$(du -h "$RPM_FILE" | cut -f1)
    echo -e "${GREEN}✓ RPM package created successfully!${NC}"
    echo -e "${GREEN}  Location: $RPM_FILE${NC}"
    echo -e "${GREEN}  Size: $RPM_SIZE${NC}"
    echo ""
    echo -e "${YELLOW}Install with:${NC}"
    echo -e "  sudo rpm -ivh $RPM_FILE"
else
    echo -e "${RED}Error: RPM package not found${NC}"
    exit 1
fi
