#!/bin/sh
set -e

# FreeBSD Static JRE Build Script for Cirrus CI
# This script builds a statically linked OpenJDK JRE on FreeBSD

# Configuration
OPENJDK_VERSION="17"
BUILD_DIR="/tmp/openjdk-build"
INSTALL_PREFIX="/usr/local"
OUTPUT_DIR="$PWD/jre-static"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo "${RED}[ERROR] $1${NC}"
    exit 1
}

# Determine bootstrap JDK package
determine_bootstrap_jdk() {
    log "Determining bootstrap JDK for OpenJDK ${OPENJDK_VERSION}..."
    
    case "$OPENJDK_VERSION" in
        "8")
            # JDK 8 can bootstrap with JDK 7 or 8, but we'll use a later version
            BOOTSTRAP_JDK_PKG="openjdk11"
            BOOTSTRAP_JDK_PATH="/usr/local/openjdk11"
            ;;
        "11")
            # JDK 11 can bootstrap with JDK 10 or later
            BOOTSTRAP_JDK_PKG="openjdk17"
            BOOTSTRAP_JDK_PATH="/usr/local/openjdk17"
            ;;
        "17")
            # JDK 17 can bootstrap with JDK 16 or later
            # We can use the same version or a later one
            BOOTSTRAP_JDK_PKG="openjdk17"
            BOOTSTRAP_JDK_PATH="/usr/local/openjdk17"
            ;;
        "21")
            # JDK 21 can bootstrap with JDK 20 or later
            BOOTSTRAP_JDK_PKG="openjdk21"
            BOOTSTRAP_JDK_PATH="/usr/local/openjdk21"
            ;;
        *)
            warn "Unknown OpenJDK version $OPENJDK_VERSION, defaulting to OpenJDK 17 as bootstrap"
            BOOTSTRAP_JDK_PKG="openjdk17"
            BOOTSTRAP_JDK_PATH="/usr/local/openjdk17"
            ;;
    esac
    
    log "Using bootstrap JDK: $BOOTSTRAP_JDK_PKG at $BOOTSTRAP_JDK_PATH"
}

# Fix package repository configuration
fix_pkg_repos() {
    log "Fixing package repository configuration..."
    
    # Get actual FreeBSD version
    FREEBSD_VERSION=$(freebsd-version | cut -d'-' -f1)
    FREEBSD_MAJOR=$(echo $FREEBSD_VERSION | cut -d'.' -f1)
    
    log "Detected FreeBSD version: $FREEBSD_VERSION (Major: $FREEBSD_MAJOR)"
    
    # Backup original config
    cp /etc/pkg/FreeBSD.conf /etc/pkg/FreeBSD.conf.backup 2>/dev/null || true
    
    # Create correct repository configuration
    cat > /etc/pkg/FreeBSD.conf << EOF
FreeBSD: {
    url: "pkg+http://pkg.FreeBSD.org/\${ABI}/quarterly",
    mirror_type: "srv",
    signature_type: "fingerprints",
    fingerprints: "/usr/share/keys/pkg",
    enabled: yes
}
EOF
    
    # Alternative: Use latest packages instead of quarterly
    # cat > /etc/pkg/FreeBSD.conf << EOF
# FreeBSD: {
#     url: "pkg+http://pkg.FreeBSD.org/\${ABI}/latest",
#     mirror_type: "srv",
#     signature_type: "fingerprints",
#     fingerprints: "/usr/share/keys/pkg",
#     enabled: yes
# }
# EOF
    
    # Force update package database
    pkg update -f
    
    log "Package repository configuration fixed"
}

# Check if running as root for package installation
check_root() {
    if [ "$(id -u)" != "0" ]; then
        error "This script must be run as root for package installation"
    fi
}

# Install required packages
install_dependencies() {
    log "Installing build dependencies..."
    
    # Fix package repository configuration
    fix_pkg_repos
    
    log "Updating package database with timeout..."
    timeout 300 pkg update -f || {
        warn "Package update timed out or failed, continuing anyway..."
    }
    
    # Determine bootstrap JDK based on target version
    determine_bootstrap_jdk
    
    log "Installing essential build tools..."
    # Install packages with timeout and better error handling
    timeout 600 pkg install -y \
        ${BOOTSTRAP_JDK_PKG} \
        gmake \
        autoconf \
        automake \
        libtool \
        pkgconf \
        bash \
        zip \
        unzip \
        git \
        curl \
        wget || {
        error "Failed to install essential build tools"
    }
    
    log "Installing additional libraries (optional)..."
    # Additional libraries that might be needed (with timeout and non-fatal errors)
    timeout 300 pkg install -y \
        freetype2 \
        fontconfig \
        libX11 \
        libXext \
        libXi \
        libXrender \
        libXrandr \
        libXtst \
        alsa-lib \
        cups || {
        warn "Some additional libraries failed to install, continuing anyway..."
    }
    
    # Verify essential commands are available
    verify_essential_tools
    
    log "Dependencies installed successfully"
}

# Verify essential tools are available
verify_essential_tools() {
    log "Verifying essential tools..."
    
    # Check for commands that should be in base system
    for cmd in which make; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            warn "$cmd not found in base system"
        else
            log "✓ $cmd available"
        fi
    done
    
    # Check for gmake specifically
    if ! command -v gmake >/dev/null 2>&1; then
        error "gmake not installed - this is required for OpenJDK build"
    fi
}

# Download OpenJDK source
download_source() {
    log "Downloading OpenJDK ${OPENJDK_VERSION} source..."
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Download OpenJDK 17 source
    case "$OPENJDK_VERSION" in
        "17")
            if [ ! -d "jdk17u" ]; then
                log "Downloading OpenJDK 17 LTS source..."
                git clone --depth 1 https://github.com/openjdk/jdk17u.git
            fi
            SOURCE_DIR="jdk17u"
            ;;
        "8")
            if [ ! -d "jdk8u" ]; then
                git clone --depth 1 https://github.com/openjdk/jdk8u.git
            fi
            SOURCE_DIR="jdk8u"
            ;;
        "11")
            if [ ! -d "jdk11u" ]; then
                git clone --depth 1 https://github.com/openjdk/jdk11u.git
            fi
            SOURCE_DIR="jdk11u"
            ;;
        "21")
            if [ ! -d "jdk21u" ]; then
                git clone --depth 1 https://github.com/openjdk/jdk21u.git
            fi
            SOURCE_DIR="jdk21u"
            ;;
        *)
            error "Unsupported OpenJDK version: $OPENJDK_VERSION"
            ;;
    esac
    
    cd "$SOURCE_DIR"
    log "Source downloaded successfully to $PWD"
}

# Configure build for static linking
configure_build() {
    log "Configuring OpenJDK build..."
    
    # Verify bootstrap JDK exists
    if [ ! -d "$BOOTSTRAP_JDK_PATH" ]; then
        error "Bootstrap JDK not found at $BOOTSTRAP_JDK_PATH"
    fi
    
    # Set environment variables for static linking
    export CC=clang
    export CXX=clang++
    export LDFLAGS="-static -L/usr/local/lib"
    export CFLAGS="-static -I/usr/local/include"
    export CXXFLAGS="-static -I/usr/local/include"
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"
    
    # Configure OpenJDK 17 build with static linking options
    bash configure \
        --with-boot-jdk="$BOOTSTRAP_JDK_PATH" \
        --with-native-debug-symbols=none \
        --with-debug-level=release \
        --with-toolchain-type=clang \
        --disable-warnings-as-errors \
        --with-extra-ldflags="-static" \
        --with-extra-cflags="-static" \
        --with-extra-cxxflags="-static" \
        --prefix="$INSTALL_PREFIX" \
        --with-version-string="${OPENJDK_VERSION}.0.0-freebsd-static" \
        --with-vendor-name="FreeBSD-Static-Build" \
        --with-vendor-url="https://github.com/your-repo" \
        --with-vendor-bug-url="https://github.com/your-repo/issues"
    
    log "Build configured successfully"
}

# Build OpenJDK
build_jdk() {
    log "Building OpenJDK (this may take 30+ minutes)..."
    
    # Use all available cores for faster build
    MAKE_JOBS=$(sysctl -n hw.ncpu)
    
    gmake JOBS="$MAKE_JOBS" images
    
    log "Build completed successfully"
}

# Create JRE-only distribution
create_jre_dist() {
    log "Creating JRE distribution..."
    
    # Find the built JRE
    BUILD_OUTPUT_DIR=$(find build -name "jdk" -type d | head -1)
    if [ -z "$BUILD_OUTPUT_DIR" ]; then
        error "Could not find built JDK directory"
    fi
    
    mkdir -p "$OUTPUT_DIR"
    
    # Copy JRE components
    cp -r "$BUILD_OUTPUT_DIR"/* "$OUTPUT_DIR/"
    
    # Remove JDK-specific tools to create JRE-only distribution
    cd "$OUTPUT_DIR"
    
    # Remove development tools
    rm -rf bin/javac* bin/jar* bin/jarsigner* bin/javadoc* bin/javap* bin/jcmd* bin/jconsole* bin/jdb* bin/jdeps* bin/jfr* bin/jhsdb* bin/jimage* bin/jinfo* bin/jlink* bin/jmap* bin/jmod* bin/jps* bin/jrunscript* bin/jshell* bin/jstack* bin/jstat* bin/keytool* bin/rmiregistry* bin/serialver*
    
    # Keep only essential JRE binaries
    # java, javaw (if exists), and any other runtime-only tools
    
    # Remove include directory (C headers)
    rm -rf include/
    
    # Remove demo and sample directories if they exist
    rm -rf demo/ sample/
    
    log "JRE distribution created in $OUTPUT_DIR"
}

# Strip binaries and create archive
package_jre() {
    log "Packaging JRE..."
    
    cd "$OUTPUT_DIR"
    
    # Strip debug symbols from binaries
    find . -type f -perm +111 -exec strip {} \; 2>/dev/null || true
    
    # Create version info file
    cat > VERSION << EOF
FreeBSD Static OpenJDK ${OPENJDK_VERSION} JRE
Built on: $(date)
Architecture: $(uname -m)
FreeBSD Version: $(freebsd-version)
Build Host: $(hostname)
EOF
    
    # Create tarball
    cd ..
    tar -czf "openjdk-${OPENJDK_VERSION}-jre-freebsd-$(uname -m)-static.tar.gz" -C "$OUTPUT_DIR" .
    
    log "JRE packaged as openjdk-${OPENJDK_VERSION}-jre-freebsd-$(uname -m)-static.tar.gz"
}

# Verify the build
verify_build() {
    log "Verifying build..."
    
    # Test java binary
    if [ -x "$OUTPUT_DIR/bin/java" ]; then
        "$OUTPUT_DIR/bin/java" -version
        log "Java binary is working"
    else
        error "Java binary not found or not executable"
    fi
    
    # Check for shared library dependencies (should be minimal for static build)
    echo "Checking dependencies:"
    ldd "$OUTPUT_DIR/bin/java" || true
}

# Cleanup function
cleanup() {
    log "Cleaning up build directory..."
    rm -rf "$BUILD_DIR"
}

# Main execution
main() {
    log "Starting FreeBSD Static JRE build process..."
    
    check_root
    install_dependencies
    download_source
    configure_build
    build_jdk
    create_jre_dist
    package_jre
    verify_build
    
    log "Build process completed successfully!"
    log "JRE archive: openjdk-${OPENJDK_VERSION}-jre-freebsd-$(uname -m)-static.tar.gz"
    log "JRE directory: $OUTPUT_DIR"
    
    # Optional cleanup
    read -p "Remove build directory? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup
    fi
}

# Handle interruption
trap cleanup INT TERM

# Run main function
main "$@"
