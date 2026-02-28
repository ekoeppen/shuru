#!/bin/bash
set -euo pipefail

DEBIAN_RELEASE="bookworm"
DEBIAN_VERSION="12"
ARCH="arm64"
DATA_DIR="${HOME}/.local/share/shuru"
ROOTFS_IMG="${DATA_DIR}/rootfs-debian.ext4"
GUEST_BINARY="target/aarch64-unknown-linux-gnu/release/shuru-guest"
ROOTFS_SIZE_MB=2048

EXTRA_PACKAGES="libgomp1,zsh,xz-utils,less,git,openssh-client,jq,file"

DEBIAN_MIRROR="http://deb.debian.org/debian"
DEBIAN_SECURITY="http://security.debian.org/debian-security"

echo "==> Shuru rootfs preparation script (Debian edition), excluding kernel and initramfs"
echo "    Debian ${DEBIAN_RELEASE} for ${ARCH}"
echo ""

# Check for required tools
for tool in curl tar dd container; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: Required tool '$tool' not found."
        exit 1
    fi
done

# Check for guest binary
if [ ! -f "$GUEST_BINARY" ]; then
    echo "ERROR: Guest binary not found at ${GUEST_BINARY}"
    echo "       Run: cargo build -p shuru-guest --target aarch64-unknown-linux-gnu --release"
    echo "       Note: Debian uses glibc, not musl - use 'aarch64-unknown-linux-gnu' target"
    exit 1
fi

mkdir -p "$DATA_DIR"

# --- Create Debian base rootfs using debootstrap ---
DEBIAN_ROOTFS_TAR="${DATA_DIR}/debian-${DEBIAN_RELEASE}-${ARCH}.tar.gz"
if [ ! -f "$DEBIAN_ROOTFS_TAR" ]; then
    echo "==> Creating Debian base rootfs with debootstrap..."
    echo "    This may take several minutes..."
    
    # Use container to run debootstrap
    container run --rm \
        --platform linux/arm64/v8 \
        -v "${DATA_DIR}:/output" \
        debian:${DEBIAN_RELEASE}-slim /bin/bash -c "
            set -e
            apt-get update > /dev/null 2>&1
            apt-get install -y debootstrap > /dev/null 2>&1
            
            echo 'Running debootstrap...'
            debootstrap --arch=arm64 --variant=minbase \
                --include=kmod,udev,iproute2,iputils-ping,ca-certificates,${EXTRA_PACKAGES} \
                ${DEBIAN_RELEASE} /target ${DEBIAN_MIRROR}
            
            echo 'Creating tarball...'
            cd /target
            tar czf /output/debian-${DEBIAN_RELEASE}-${ARCH}.tar.gz .
            echo 'Debian rootfs tar file created successfully'
        "
    
    echo "    Rootfs saved to ${DEBIAN_ROOTFS_TAR}"
else
    echo "==> Debian rootfs tar file already created."
fi

# --- Create ext4 rootfs image ---
echo "==> Creating ext4 rootfs image (${ROOTFS_SIZE_MB}MB)..."

# Create empty image file
dd if=/dev/zero of="$ROOTFS_IMG" bs=1M count="$ROOTFS_SIZE_MB" 2>&1 | grep -v records || true

echo ""
echo "==> Using container for ext4 formatting and population."
echo ""

DOCKER_WORKDIR=$(mktemp -d)
cp "$DEBIAN_ROOTFS_TAR" "${DOCKER_WORKDIR}/rootfs.tar.gz"
cp "$GUEST_BINARY" "${DOCKER_WORKDIR}/shuru-guest"

# Format + populate entirely inside Docker
container run --rm \
    --platform linux/arm64/v8 \
    -v "${ROOTFS_IMG}:/rootfs.ext4" \
    -v "${DOCKER_WORKDIR}:/workdir:ro" \
    debian:${DEBIAN_RELEASE}-slim /bin/bash -c '
        set -e
        apt-get update > /dev/null 2>&1
        apt-get install -y e2fsprogs > /dev/null 2>&1
        
        echo "Formatting ext4 filesystem..."
        mkfs.ext4 -F /rootfs.ext4
        
        echo "Mounting and populating rootfs..."
        mkdir -p /mnt/rootfs
        mount -o loop /rootfs.ext4 /mnt/rootfs
        
        tar xzf /workdir/rootfs.tar.gz -C /mnt/rootfs
        
        # Copy shuru-guest as init
        cp /workdir/shuru-guest /mnt/rootfs/usr/bin/shuru-init
        chmod 755 /mnt/rootfs/usr/bin/shuru-init
        
        # Ensure essential directories exist
        mkdir -p /mnt/rootfs/proc /mnt/rootfs/sys /mnt/rootfs/dev 
        mkdir -p /mnt/rootfs/tmp /mnt/rootfs/run /mnt/rootfs/var/tmp
        
        # Basic system configuration
        echo "shuru-debian" > /mnt/rootfs/etc/hostname
        echo "127.0.0.1 localhost" > /mnt/rootfs/etc/hosts
        echo "127.0.1.1 shuru-debian" >> /mnt/rootfs/etc/hosts
        echo "nameserver 8.8.8.8" > /mnt/rootfs/etc/resolv.conf
        echo "nameserver 8.8.4.4" >> /mnt/rootfs/etc/resolv.conf
        
        # Prevent systemd from interfering (if it exists)
        if [ -f /mnt/rootfs/bin/systemctl ]; then
            rm -f /mnt/rootfs/bin/systemctl
            rm -f /mnt/rootfs/sbin/init
        fi
        
        # Set proper permissions
        chmod 1777 /mnt/rootfs/tmp /mnt/rootfs/var/tmp
        
        umount /mnt/rootfs
        echo "==> Rootfs populated successfully"
    '

rm -rf "$DOCKER_WORKDIR"

echo ""
echo "==> Done!"
echo "    Rootfs:     ${ROOTFS_IMG}"
echo ""
echo "    IMPORTANT: Build guest binary with glibc target:"
echo "               cargo build -p shuru-guest --target aarch64-unknown-linux-gnu --release"
echo ""
echo "    To run:    cargo build -p shuru-cli && codesign --entitlements shuru.entitlements --force -s - target/debug/shuru"
echo "               ./target/debug/shuru run -- echo hello"
