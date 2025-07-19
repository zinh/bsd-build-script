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

# Check if running as root for package installation
check_root() {
    if [ "$(id -u)" != "0" ]; then
        error "This script must be run as root for package installation"
    fi
}

# Install required packages
install_dependencies() {
    log "Installing build dependencies..."
    
    pkg update -f
    
    # Essential build tools
    pkg install -y \
        openjdk${OPENJDK_VERSION} \
        gmake \
        autoconf \
        automake \
        libtool \
        pkgconf \
        bash \
        zip \
        unzip \
        which \
        git \
        curl \
        wget
    
    # Additional libraries that might be needed
    pkg install -y \
        freetype2 \
        fontconfig \
        libX11 \
        libXext \
        libXi \
        libXrender \
        libXrandr \
        libXtst \
        alsa-lib \
        cups
    
    log "Dependencies installed successfully"
}

# Download OpenJDK source
download_source() {
    log "Downloading OpenJDK ${OPENJDK_VERSION} source..."
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Download from official OpenJDK repository
    if [ ! -d "jdk${OPENJDK_VERSION}u" ]; then
        git clone --depth 1 https://github.com/openjdk/jdk${OPENJDK_VERSION}u.git
    fi
    
    cd "jdk${OPENJDK_VERSION}u"
    log "Source downloaded successfully"
}

# Configure build for static linking
configure_build() {
    log "Configuring OpenJDK build..."
    
    # Set environment variables for static linking
    export CC=clang
    export CXX=clang++
    export LDFLAGS="-static -L/usr/local/lib"
    export CFLAGS="-static -I/usr/local/include"
    export CXXFLAGS="-static -I/usr/local/include"
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"
    
    # Configure with static linking options
    bash configure \
        --with-boot-jdk="/usr/local/openjdk${OPENJDK_VERSION}" \
        --with-native-debug-symbols=none \
        --with-debug-level=release \
        --enable-static-build \
        --disable-warnings-as-errors \
        --with-extra-ldflags="-static" \
        --with-extra-cflags="-static" \
        --with-extra-cxxflags="-static" \
        --prefix="$INSTALL_PREFIX" \
        --with-version-string="${OPENJDK_VERSION}.0.0+custom" \
        --with-vendor-name="FreeBSD-Static" \
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
