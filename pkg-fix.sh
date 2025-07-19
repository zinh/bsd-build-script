#!/bin/sh
# pkg-fix.sh - Fix FreeBSD package repository issues for FreeBSD 13.4

set -e

# Fix package repository configuration for Cirrus CI
fix_cirrus_pkg() {
    echo "=== Fixing FreeBSD package repository configuration ==="
    
    # Show current system info
    echo "FreeBSD version: $(freebsd-version)"
    echo "Architecture: $(uname -m)"
    echo "Current pkg configuration:"
    pkg -vv 2>/dev/null | grep -E "(url|ABI)" || true
    
    # Get system ABI
    ABI=$(pkg config ABI 2>/dev/null || echo "FreeBSD:13:$(uname -m)")
    echo "System ABI: $ABI"
    
    # Method 1: Bootstrap pkg first to ensure it's working
    echo "Method 1: Bootstrapping pkg..."
    env ASSUME_ALWAYS_YES=yes pkg bootstrap -f
    
    # Method 2: Update repository configuration for FreeBSD 13.4
    echo "Method 2: Updating repository configuration..."
    
    # Create/update the repository configuration
    mkdir -p /usr/local/etc/pkg/repos
    
    # For FreeBSD 13.4, we might need to use the latest repository
    # since quarterly might not have packages for newer point releases
    cat > /usr/local/etc/pkg/repos/FreeBSD.conf << 'EOF'
FreeBSD: {
    url: "pkg+http://pkg.FreeBSD.org/${ABI}/latest",
    mirror_type: "srv",
    signature_type: "fingerprints",
    fingerprints: "/usr/share/keys/pkg",
    enabled: yes
}
EOF
    
    # Alternative: Try quarterly first, fallback to latest if needed
    # cat > /usr/local/etc/pkg/repos/FreeBSD.conf << 'EOF'
    # FreeBSD: {
    #     url: "pkg+http://pkg.FreeBSD.org/${ABI}/quarterly",
    #     mirror_type: "srv",
    #     signature_type: "fingerprints",
    #     fingerprints: "/usr/share/keys/pkg",
    #     enabled: yes
    # }
    # EOF
    
    # Method 3: Force update with retry logic
    echo "Method 3: Force updating package database..."
    
    # Try quarterly first
    if ! pkg update -f 2>/dev/null; then
        echo "Quarterly repository failed, trying latest..."
        cat > /usr/local/etc/pkg/repos/FreeBSD.conf << 'EOF'
FreeBSD: {
    url: "pkg+http://pkg.FreeBSD.org/${ABI}/latest",
    mirror_type: "srv",
    signature_type: "fingerprints",
    fingerprints: "/usr/share/keys/pkg",
    enabled: yes
}
EOF
        pkg update -f
    fi
    
    echo "=== Package repository fix completed ==="
}

# Test package installation
test_pkg() {
    echo "Testing package installation..."
    
    # Test with a simple package first
    if pkg install -y curl; then
        echo "Package installation test: SUCCESS"
        pkg info curl
    else
        echo "Package installation test: FAILED"
        
        # Show more debug info
        echo "Debug information:"
        pkg -vv
        pkg update -f
        return 1
    fi
    
    # Verify common commands are available
    echo "Checking for required commands:"
    command -v which >/dev/null 2>&1 && echo "✓ which command available" || echo "✗ which command missing"
    command -v gmake >/dev/null 2>&1 && echo "✓ gmake available" || echo "✗ gmake missing (will be installed)"
    command -v git >/dev/null 2>&1 && echo "✓ git available" || echo "✗ git missing (will be installed)"
}

# Show repository status
show_repo_status() {
    echo "=== Repository Status ==="
    pkg stats
    echo ""
    echo "Available repositories:"
    pkg -vv | grep -A 5 -B 5 "Repositories:" || true
}

# Main execution
main() {
    fix_cirrus_pkg
    show_repo_status
    test_pkg
    echo "Package repository is now ready!"
}

main "$@"
