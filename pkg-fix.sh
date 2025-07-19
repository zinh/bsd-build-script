#!/bin/sh
# pkg-fix.sh - Fix FreeBSD package repository issues for FreeBSD 13.4

set -e

# Set timeouts for network operations
export FETCH_TIMEOUT=60
export FETCH_RETRY=3

# Fix package repository configuration for Cirrus CI
fix_cirrus_pkg() {
    echo "=== Fixing FreeBSD package repository configuration ==="
    
    # Show current system info
    echo "FreeBSD version: $(freebsd-version)"
    echo "Architecture: $(uname -m)"
    echo "Current pkg configuration:"
    timeout 30 pkg -vv 2>/dev/null | grep -E "(url|ABI)" || echo "pkg -vv timed out or failed"
    
    # Get system ABI
    ABI=$(timeout 10 pkg config ABI 2>/dev/null || echo "FreeBSD:13:$(uname -m)")
    echo "System ABI: $ABI"
    
    # Method 1: Bootstrap pkg first to ensure it's working
    echo "Method 1: Bootstrapping pkg with timeout..."
    timeout 120 env ASSUME_ALWAYS_YES=yes pkg bootstrap -f || {
        echo "pkg bootstrap failed or timed out, continuing..."
    }
    
    # Method 2: Update repository configuration for FreeBSD 13.4
    echo "Method 2: Updating repository configuration..."
    
    # Create/update the repository configuration
    mkdir -p /usr/local/etc/pkg/repos
    
    # For FreeBSD 13.4, use latest repository with timeout settings
    cat > /usr/local/etc/pkg/repos/FreeBSD.conf << 'EOF'
FreeBSD: {
    url: "pkg+http://pkg.FreeBSD.org/${ABI}/latest",
    mirror_type: "srv",
    signature_type: "fingerprints",
    fingerprints: "/usr/share/keys/pkg",
    enabled: yes
}
EOF
    
    # Method 3: Force update with timeout and retry logic
    echo "Method 3: Force updating package database with timeout..."
    
    # Try multiple times with timeout
    for attempt in 1 2 3; do
        echo "Update attempt $attempt/3..."
        if timeout 180 pkg update -f; then
            echo "Package update successful on attempt $attempt"
            break
        else
            echo "Attempt $attempt failed, waiting before retry..."
            sleep 10
            if [ $attempt -eq 3 ]; then
                echo "All update attempts failed, but continuing..."
                # Don't exit here, try to continue with whatever we have
            fi
        fi
    done
    
    echo "=== Package repository fix completed ==="
}

# Test package installation with timeout
test_pkg() {
    echo "Testing package installation with timeout..."
    
    # Test with a simple package first
    if timeout 120 pkg install -y curl; then
        echo "Package installation test: SUCCESS"
        pkg info curl || echo "Could not get package info"
    else
        echo "Package installation test: FAILED or TIMED OUT"
        
        # Show more debug info
        echo "Debug information:"
        timeout 30 pkg -vv || echo "pkg -vv failed"
        return 1
    fi
    
    # Verify common commands are available
    echo "Checking for required commands:"
    command -v which >/dev/null 2>&1 && echo "✓ which command available" || echo "✗ which command missing"
    command -v gmake >/dev/null 2>&1 && echo "✓ gmake available" || echo "✗ gmake missing (will be installed)"
    command -v git >/dev/null 2>&1 && echo "✓ git available" || echo "✗ git missing (will be installed)"
}

# Show repository status with timeout
show_repo_status() {
    echo "=== Repository Status ==="
    timeout 30 pkg stats || echo "pkg stats timed out"
    echo ""
    echo "Available repositories:"
    timeout 30 pkg -vv | grep -A 5 -B 5 "Repositories:" || echo "Could not get repository info"
}

# Main execution with error handling
main() {
    echo "Starting package repository fix with timeouts..."
    
    # Set signal handlers for cleanup
    trap 'echo "Script interrupted"; exit 130' INT TERM
    
    fix_cirrus_pkg
    show_repo_status
    test_pkg
    echo "Package repository is ready (or continuing despite issues)!"
}

main "$@"
