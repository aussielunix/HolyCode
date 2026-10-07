# ==============================================================================
# HolyCode - Pre-configured Docker Environment for OpenCode
# https://github.com/aussielunix/holycode
# ==============================================================================

# renovate: datasource=github-releases depName=cli/cli
ARG GITHUB_CLI_VERSION=2.101.0
ARG GITHUB_CLI_REF=0cf1092493af067646fc5f3db9421c6a6ec9c938
# renovate: datasource=github-releases depName=junegunn/fzf
ARG FZF_VERSION=0.74.4
ARG FZF_REF=a140afeb4d733cad3c96a56bf6db7e26853b6757
# renovate: datasource=github-releases depName=jesseduffield/lazygit
ARG LAZYGIT_VERSION=0.65.1
ARG LAZYGIT_REF=17cb09fa7b08bc96d9f0e81b91f4720fc1a36700

# renovate: datasource=github-releases depName=aaif-goose/goose
ARG GOOSE_VERSION=1.52.0

# Rebuild exact release sources with reviewed dependency fixes.
FROM --platform=$BUILDPLATFORM golang:1.27.1-trixie@sha256:433790e515d27dc6003e847e644cc0af956985cf315c1c58a3b73ee2dd305183 AS github-cli-builder
ARG GITHUB_CLI_VERSION
ARG GITHUB_CLI_REF
ARG TARGETARCH
RUN git clone --branch "v${GITHUB_CLI_VERSION}" --depth 1 \
      https://github.com/cli/cli.git /src && \
    cd /src && \
    test "$(git rev-parse HEAD)" = "${GITHUB_CLI_REF}" && \
    test "$(git describe --tags --exact-match HEAD)" = "v${GITHUB_CLI_VERSION}" && \
    test "$(go list -m -f '{{.Version}}' google.golang.org/grpc)" = "v1.83.2" && \
    test "$(go list -m -f '{{.Version}}' golang.org/x/text)" = "v0.42.0" && \
    test "$(go list -m -f '{{.Version}}' github.com/klauspost/compress)" = "v1.20.0" && \
    test "$(go list -m -f '{{.Version}}' golang.org/x/mod)" = "v0.41.0" && \
    go mod verify && \
    mkdir -p /tmp/gh-test && \
    chown -R nobody:nogroup /src /tmp/gh-test && \
    su -s /bin/sh nobody -c \
      'HOME=/tmp/gh-test GOCACHE=/tmp/gh-test/go-cache GOPATH=/tmp/gh-test/go go test ./...' && \
    git config --global --add safe.directory /src && \
    GH_GOARCH=$(case "$TARGETARCH" in arm64) echo "arm64";; *) echo "amd64";; esac) && \
    SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)" \
      GH_VERSION="${GITHUB_CLI_VERSION}" go run ./script/build.go bin/gh \
      GOOS=linux GOARCH="${GH_GOARCH}" CGO_ENABLED=0 && \
    install -D -m 0755 bin/gh /out/gh && \
    go version -m /out/gh | grep -F "go1.27.1" && \
    go version -m /out/gh | grep -E 'github.com/klauspost/compress[[:space:]]+v1\.20\.0' && \
    go version -m /out/gh | grep -E 'golang.org/x/text[[:space:]]+v0\.42\.0' && \
    go version -m /out/gh | grep -E 'golang.org/x/mod[[:space:]]+v0\.41\.0'

FROM --platform=$BUILDPLATFORM golang:1.27.1-trixie@sha256:433790e515d27dc6003e847e644cc0af956985cf315c1c58a3b73ee2dd305183 AS fzf-builder
ARG FZF_VERSION
ARG FZF_REF
ARG TARGETARCH
COPY patches/fzf-x-sys-0.44.0.patch /tmp/fzf-x-sys-0.44.0.patch
RUN git clone --branch "v${FZF_VERSION}" --depth 1 \
      https://github.com/junegunn/fzf.git /src && \
    cd /src && \
    test "$(git rev-parse HEAD)" = "${FZF_REF}" && \
    test "$(git describe --tags --exact-match HEAD)" = "v${FZF_VERSION}" && \
    git apply --check /tmp/fzf-x-sys-0.44.0.patch && \
    git apply /tmp/fzf-x-sys-0.44.0.patch && \
    test "$(go list -m -f '{{.Version}}' golang.org/x/sys)" = "v0.44.0" && \
    for attempt in 1 2 3; do \
      if go mod download; then break; fi; \
      test "$attempt" -lt 3; \
      sleep 2; \
    done && \
    go mod verify && \
    SHELL=/bin/sh go test \
      github.com/junegunn/fzf/src \
      github.com/junegunn/fzf/src/algo \
      github.com/junegunn/fzf/src/tui \
      github.com/junegunn/fzf/src/util && \
    mkdir -p /out && \
    FZF_GOARCH=$(case "$TARGETARCH" in arm64) echo "arm64";; *) echo "amd64";; esac) && \
    GOOS=linux GOARCH="${FZF_GOARCH}" CGO_ENABLED=0 go build -a -trimpath \
      -ldflags "-s -w -X main.version=${FZF_VERSION} -X main.revision=$(git rev-parse --short=8 HEAD)" \
      -o /out/fzf && \
    go version -m /out/fzf | grep -E 'golang.org/x/sys[[:space:]]+v0\.44\.0'

FROM --platform=$BUILDPLATFORM golang:1.27.1-trixie@sha256:433790e515d27dc6003e847e644cc0af956985cf315c1c58a3b73ee2dd305183 AS lazygit-builder
ARG LAZYGIT_VERSION
ARG LAZYGIT_REF
ARG TARGETARCH
RUN git clone --branch "v${LAZYGIT_VERSION}" --depth 1 \
      https://github.com/jesseduffield/lazygit.git /src && \
    cd /src && \
    test "$(git rev-parse HEAD)" = "${LAZYGIT_REF}" && \
    test "$(git describe --tags --exact-match HEAD)" = "v${LAZYGIT_VERSION}" && \
    export GOFLAGS=-mod=mod && \
    for attempt in 1 2 3; do \
      if go mod download; then break; fi; \
      test "$attempt" -lt 3; \
      sleep 2; \
    done && \
    test "$(go list -m -f '{{.Version}}' golang.org/x/text)" = "v0.41.0" && \
    test "$(go list -m -f '{{.Version}}' golang.org/x/sys)" = "v0.47.0" && \
    go mod verify && \
    LAZYGIT_MODULE_FILES_SHA256="$(sha256sum go.mod go.sum)" && \
    go mod vendor && \
    test "$(sha256sum go.mod go.sum)" = "${LAZYGIT_MODULE_FILES_SHA256}" && \
    export GOFLAGS=-mod=vendor && \
    go test ./... && \
    mkdir -p /out && \
    LAZYGIT_GOARCH=$(case "$TARGETARCH" in arm64) echo "arm64";; *) echo "amd64";; esac) && \
    BUILD_DATE="$(git show -s --format=%cI HEAD)" && \
    GOOS=linux GOARCH="${LAZYGIT_GOARCH}" CGO_ENABLED=0 go build -trimpath \
      -ldflags "-s -w -X main.version=${LAZYGIT_VERSION} -X main.commit=${LAZYGIT_REF} -X main.date=${BUILD_DATE} -X main.buildSource=binaryRelease" \
      -o /out/lazygit && \
    go version -m /out/lazygit | grep -E 'golang.org/x/text[[:space:]]+v0\.41\.0' && \
    go version -m /out/lazygit | grep -E 'golang.org/x/sys[[:space:]]+v0\.47\.0'

# Base runtime is Fedora 44: the native home of the bootc + OCI tooling
# (bootc, podman, buildah, skopeo). Node is installed via nvm below.
FROM quay.io/fedora/fedora:44@sha256:ba35579e107f26a4c2c000390fb3ff549f3858a9584a6b5a35f7fa51f54de309

# ---------- Build args ----------
ARG GITHUB_CLI_VERSION
ARG FZF_VERSION
ARG LAZYGIT_VERSION
# renovate: datasource=github-releases depName=nvm-sh/nvm
ARG NVM_VERSION=0.40.3
# renovate: datasource=node depName=node
ARG NODE_VERSION=24.21.0
# renovate: datasource=github-releases depName=just-containers/s6-overlay
ARG S6_OVERLAY_VERSION=3.2.3.2
# renovate: datasource=github-releases depName=dandavison/delta
ARG DELTA_VERSION=0.19.2
# renovate: datasource=github-releases depName=eza-community/eza
ARG EZA_VERSION=0.23.5
# renovate: datasource=npm depName=@opencode/cli
ARG OPENCODE_VERSION=2.0.18
# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.281
# renovate: datasource=npm depName=@fission-ai/openspec
ARG OPENSPEC_VERSION=1.13.2
ARG GOOSE_VERSION=1.52.0
# renovate: datasource=npm depName=opencode-claude-auth
ARG CLAUDE_AUTH_PLUGIN_VERSION=2.2.1
# renovate: datasource=npm depName=typescript
ARG TYPESCRIPT_VERSION=6.0.3
# renovate: datasource=npm depName=npm
ARG NPM_VERSION=12.1.0
# renovate: datasource=npm depName=brace-expansion
ARG NPM_BRACE_EXPANSION_VERSION=5.0.12
# renovate: datasource=npm depName=tar
ARG NPM_TAR_VERSION=7.5.22
# renovate: datasource=npm depName=ip-address
ARG NPM_IP_ADDRESS_VERSION=10.7.2
# renovate: datasource=npm depName=js-yaml
ARG PM2_JS_YAML_VERSION=4.3.2
# renovate: datasource=npm depName=tsx
ARG TSX_VERSION=4.23.15
# renovate: datasource=npm depName=pnpm
ARG PNPM_VERSION=12.6.0
# renovate: datasource=npm depName=vite
ARG VITE_VERSION=8.3.1
# renovate: datasource=npm depName=prettier
ARG PRETTIER_VERSION=3.9.9
# renovate: datasource=npm depName=prisma
ARG PRISMA_VERSION=7.10.0
# renovate: datasource=npm depName=deepmerge-ts
ARG PRISMA_DEEPMERGE_VERSION=8.0.2
# renovate: datasource=npm depName=mysql2
ARG PRISMA_MYSQL2_VERSION=3.24.4
# renovate: datasource=npm depName=@types/node
ARG PRISMA_TYPES_NODE_VERSION=20.19.43
# renovate: datasource=npm depName=undici-types
ARG PRISMA_UNDICI_TYPES_VERSION=6.21.0
# renovate: datasource=npm depName=lighthouse
ARG LIGHTHOUSE_VERSION=13.5.0
# renovate: datasource=npm depName=wrangler
ARG WRANGLER_VERSION=4.138.0
# renovate: datasource=npm depName=miniflare
ARG WRANGLER_MINIFLARE_VERSION=5.20260921.1-alpha
# renovate: datasource=npm depName=sharp
ARG WRANGLER_SHARP_VERSION=0.35.4
# renovate: datasource=npm depName=@img/sharp-libvips-linux-x64
ARG WRANGLER_SHARP_LIBVIPS_VERSION=1.3.3
# renovate: datasource=npm depName=eslint
ARG ESLINT_VERSION=10.11.0
# renovate: datasource=pypi depName=numpy
ARG NUMPY_VERSION=2.5.3
# renovate: datasource=pypi depName=pip
ARG PIP_VERSION=26.2.1
# renovate: datasource=pypi depName=msgpack
ARG PIP_VENDOR_MSGPACK_VERSION=1.2.2
ARG PIP_VENDOR_MSGPACK_SHA256=9eb0b0e602064527a045ea28c4f174ed69383587e29cebe28947e3b84106eb2a
# pip 26.2.1 vendors pkg_resources from vulnerable setuptools 70.3.0.
ARG PIP_VENDOR_PKG_RESOURCES_VERSION=78.1.1
ARG PIP_VENDOR_PKG_RESOURCES_SHA256=fcc17fd9cd898242f6b4adfaca46137a9edef687f43e6f78469692a5e70d851d
# renovate: datasource=pypi depName=setuptools
ARG SETUPTOOLS_VERSION=84.0.0
ARG TARGETARCH

LABEL org.opencontainers.image.source=https://github.com/aussielunix/HolyCode \
    io.holycode.version.github-cli=${GITHUB_CLI_VERSION} \
    io.holycode.version.opencode=${OPENCODE_VERSION} \
    io.holycode.version.claude-code=${CLAUDE_CODE_VERSION} \
    io.holycode.version.goose=${GOOSE_VERSION} \
    io.holycode.version.openspec=${OPENSPEC_VERSION} \
    io.holycode.version.claude-auth-plugin=${CLAUDE_AUTH_PLUGIN_VERSION} \
    io.holycode.version.npm=${NPM_VERSION} \
    io.holycode.version.npm-brace-expansion=${NPM_BRACE_EXPANSION_VERSION} \
    io.holycode.version.npm-tar=${NPM_TAR_VERSION} \
    io.holycode.version.npm-ip-address=${NPM_IP_ADDRESS_VERSION} \
    io.holycode.version.pm2-js-yaml=${PM2_JS_YAML_VERSION} \
    io.holycode.version.pip-vendor-msgpack=${PIP_VENDOR_MSGPACK_VERSION} \
    io.holycode.version.pip-vendor-pkg-resources=${PIP_VENDOR_PKG_RESOURCES_VERSION} \
    io.holycode.version.typescript=${TYPESCRIPT_VERSION} \
    io.holycode.version.tsx=${TSX_VERSION} \
    io.holycode.version.pnpm=${PNPM_VERSION} \
    io.holycode.version.vite=${VITE_VERSION} \
    io.holycode.version.prettier=${PRETTIER_VERSION} \
    io.holycode.version.prisma=${PRISMA_VERSION} \
    io.holycode.version.prisma-deepmerge-ts=${PRISMA_DEEPMERGE_VERSION} \
    io.holycode.version.prisma-mysql2=${PRISMA_MYSQL2_VERSION} \
    io.holycode.version.prisma-types-node=${PRISMA_TYPES_NODE_VERSION} \
    io.holycode.version.prisma-undici-types=${PRISMA_UNDICI_TYPES_VERSION} \
    io.holycode.version.lighthouse=${LIGHTHOUSE_VERSION} \
    io.holycode.version.s6-overlay=${S6_OVERLAY_VERSION} \
    io.holycode.version.fzf=${FZF_VERSION} \
    io.holycode.version.lazygit=${LAZYGIT_VERSION} \
    io.holycode.version.wrangler=${WRANGLER_VERSION} \
    io.holycode.version.wrangler-miniflare=${WRANGLER_MINIFLARE_VERSION} \
    io.holycode.version.wrangler-sharp=${WRANGLER_SHARP_VERSION} \
    io.holycode.version.wrangler-sharp-libvips=${WRANGLER_SHARP_LIBVIPS_VERSION} \
    io.holycode.version.numpy=${NUMPY_VERSION}

# ---------- Environment ----------
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DISPLAY=:99 \
    DBUS_SESSION_BUS_ADDRESS=disabled: \
    CHROME_PATH=/usr/bin/chromium-browser \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    CHROMIUM_FLAGS="--disable-gpu --disable-dev-shm-usage" \
    OPENCODE_DISABLE_AUTOUPDATE=true \
    OPENCODE_DISABLE_TERMINAL_TITLE=true \
    # nvm-managed Node runtime; global npm packages land in /usr/local to keep
    # their canonical paths and the `npm prefix -g = /usr/local` checks intact.
    NVM_DIR=/opt/nvm \
    NPM_CONFIG_PREFIX=/usr/local \
    # /usr/local/bin precedes the nvm bin so the globally-upgraded npm (installed
    # into /usr/local) shadows nvm's bundled one; node itself still resolves from
    # the nvm runtime dir (no /usr/local/bin/node is created).
    PATH="/usr/local/bin:/usr/local/sbin:/opt/nvm/versions/node/v${NODE_VERSION}/bin:${PATH}"
ENV OPENSPEC_TELEMETRY=0

# ---------- Base packages + Node (via nvm) ----------
# Fedora 44 provides no Debian node base image; install a pinned Node build with
# nvm into /opt/nvm. Global npm packages are redirected to /usr/local (see ENV).
RUN unset NPM_CONFIG_PREFIX && \
    dnf -y install \
        curl tar xz ca-certificates git glibc-langpack-en sudo \
    && dnf clean all \
    && export NVM_DIR="${NVM_DIR}" \
    && mkdir -p "${NVM_DIR}" \
    && curl --disable --retry 8 --retry-all-errors --retry-max-time 300 --remove-on-error --connect-timeout 15 --max-time 300 -fsSL \
         "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" \
         | PROFILE=/dev/null NVM_DIR="${NVM_DIR}" bash \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install "${NODE_VERSION}" \
    && nvm alias default "${NODE_VERSION}" \
    && nvm cache clear \
    && node --version | grep -F "v${NODE_VERSION}" \
    && npm --version
# ---------- s6-overlay v3 (multi-arch) ----------
RUN S6_ARCH=$(case "$TARGETARCH" in arm64) echo "aarch64";; *) echo "x86_64";; esac) && \
    S6_ARCH_SHA256=$(case "$TARGETARCH" in \
      arm64) echo "b17f17a82e7a515c682a91edaf2ffdabb73f891981b6c1fd712115693a2f8b4c";; \
      *) echo "e6befcc96a437a3831386ecfc51808c5d3e939dc5fe3c02ae9284599e8aa2408";; \
    esac) && \
    curl --disable --retry 8 --retry-all-errors --retry-max-time 300 --remove-on-error --connect-timeout 15 --max-time 300 -fsSL -o /tmp/s6-overlay-noarch.tar.xz \
      "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" && \
    curl --disable --retry 8 --retry-all-errors --retry-max-time 300 --remove-on-error --connect-timeout 15 --max-time 300 -fsSL -o /tmp/s6-overlay-arch.tar.xz \
      "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" && \
    echo "5379750ed30a84bbd2e2dd74847ba6b5bd29cd0b2e3ea2ec58049b57eb2eda12  /tmp/s6-overlay-noarch.tar.xz" | sha256sum -c - && \
    echo "${S6_ARCH_SHA256}  /tmp/s6-overlay-arch.tar.xz" | sha256sum -c - && \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz && \
    rm /tmp/s6-overlay-*.tar.xz

# ---------- Locale configuration ----------
RUN locale -a | grep -qi '^en_US' && \
    localedef -i en_US -f UTF-8 en_US.UTF-8 2>/dev/null || true

# ---------- Create agent1 user ----------
# Fedora's base has no pre-existing UID 1000 user; create agent1 with a
# persistent home directory and passwordless sudo.
RUN groupadd --gid 1000 agent1 && \
    useradd --uid 1000 --gid 1000 --home-dir /home/agent1 --create-home --shell /bin/bash agent1 && \
    mkdir -p /home/agent1 && \
    echo "agent1 ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent1 && \
    chmod 0440 /etc/sudoers.d/agent1

# ---------- Rootless Podman (replaces dockerd) for smolvm container workloads ----------
# Podman is daemonless and runs entirely unprivileged as agent1 in a user
# namespace: no root daemon, no /var/run/docker.pid, no socket group. Container
# storage MUST live on the machine's dedicated /storage ext4 disk because the
# smolvm rootfs is an overlay and container storage cannot nest on it (the same
# reason Docker's overlay2 data-root was previously pointed at /storage). See
# the smol-machines docker-in-a-machine guide and the Smolfile.
#
# podman-docker provides a `docker`-compatible CLI shim so in-machine tooling
# that shells out to `docker` (coding agents, compose) keeps working against
# rootless Podman. fuse-overlayfs gives the fast overlay driver; slirp4netns
# supplies rootless networking. newuidmap/newgidmap come from shadow-utils.
RUN dnf -y install podman podman-docker podman-compose fuse-overlayfs slirp4netns \
    && dnf clean all \
    # Grant agent1 subordinate UID/GID ranges so rootless user namespaces can map
    # container-internal users without colliding with real host ids.
    && printf 'agent1:100000:65536\n' > /etc/subuid \
    && printf 'agent1:100000:65536\n' > /etc/subgid \
    # newuidmap/newgidmap must be setuid root: without it rootless Podman cannot
    # write the container's uid_map/gid_map when entering a user namespace.
    && chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap \
    && podman --version \
    && docker --version

# Convenience entry to prepare rootless Podman's durable storage on the /storage
# ext4 disk and, on the managed/cloud path, expose the rootless API socket so
# smolvm's docker_socket=true can bridge it to a host client over vsock. Podman
# needs no daemon to run; this only ensures the graphroot is on /storage and
# starts the optional API service for host drive-by.
RUN <<'PODEOF'
cat > /usr/local/bin/start-podman <<'SCRIPT'
#!/bin/sh
set -e
RUNTIME=/run/user/1000
STORAGE=/storage/containers
RUNROOT=$RUNTIME/containers
CONF=/home/agent1/.config/containers/storage.conf

mkdir -p "$STORAGE" "$RUNROOT" "$RUNTIME"
chown -R 1000:1000 "$STORAGE" "$RUNROOT" "$RUNTIME" 2>/dev/null || true
mkdir -p "$(dirname "$CONF")"

# Prefer the fast overlay driver (via fuse-overlayfs) when /dev/fuse is present;
# otherwise fall back to the always-available vfs driver (safe on ext4, slower).
if [ -e /dev/fuse ]; then
    DRIVER=overlay
    MOUNT='    mount_program = "/usr/bin/fuse-overlayfs"'
else
    DRIVER=vfs
    MOUNT=''
fi

if [ ! -f "$CONF" ] || ! grep -q 'graphroot = "/storage/containers"' "$CONF"; then
    {
        echo '[storage]'
        echo "driver = \"$DRIVER\""
        echo "runroot = \"$RUNROOT\""
        echo "graphroot = \"$STORAGE\""
        echo ''
        echo '[storage.options]'
        echo "$MOUNT"
    } > "$CONF"
fi
chown 1000:1000 "$CONF"

# Start the rootless API service in the background for host socket access, then
# bridge it at /var/run/docker.sock so smolvm's vsock docker-socket proxy works.
SOCK=$RUNTIME/podman/podman.sock
if [ ! -S "$SOCK" ]; then
    su -s /bin/sh agent1 -c "XDG_RUNTIME_DIR=$RUNTIME nohup podman system service --time=0 >/tmp/podman-service.log 2>&1 &"
    for i in $(seq 1 20); do [ -S "$SOCK" ] && break; sleep 1; done
fi
ln -sfn "$SOCK" /var/run/docker.sock

# Verify as agent1 that rootless Podman can reach its /storage-backed storage.
su -s /bin/sh agent1 -c "XDG_RUNTIME_DIR=$RUNTIME exec podman info"
SCRIPT
chmod +x /usr/local/bin/start-podman
PODEOF

# ---------- QEMU (test qcow / disk images) ----------
# Run inside the microVM with KVM acceleration. The machine must be started with
# --nested / nested=true so /dev/kvm is exposed (see Smolfile).
RUN dnf -y install qemu-system-x86 qemu-img \
    && dnf clean all \
    && qemu-system-x86_64 --version && qemu-img --version

# ---------- bootc / OCI artifact tooling ----------
# Fedora natively packages the full bootc stack for building, inspecting and
# publishing bootable OCI (container) images:
#   - podman / buildah  : build the bootc container image from a Containerfile
#   - skopeo            : inspect / copy OCI artifacts between registries
#   - bootc             : container-native install/upgrade (incl. to-disk)
# Nested container builds (the host rootfs is itself an overlay) need a
# storage driver that works without either a nested overlay mount or a
# /dev/fuse device, so pin containers storage to the always-available `vfs`
# driver. To produce qcow2/raw/Anaconda disk images for QEMU, run the
# quay.io/bootc-image-builder/bootc-image-builder image with podman here.
RUN dnf -y install bootc podman buildah skopeo fuse-overlayfs \
    && dnf clean all \
    && printf '[storage]\ndriver = "vfs"\nrunroot = "/run/containers/storage"\ngraphroot = "/var/lib/containers/storage"\n' \
         > /etc/containers/storage.conf \
    && bootc --version \
    && podman --version \
    && buildah --version \
    && skopeo --version \
    # bootc ships /usr/lib/bootc/storage -> ../../../../sysroot/ostree/bootc/storage,
    # a relative symlink authored for the OSTree deployment depth, not for the
    # flat layer layout. Its 4x '..' resolves above the extraction root, so
    # unpacking the layer into a .smolmachine artifact fails with "tar symlink
    # ... escapes destination directory". Normalize it to an absolute target,
    # which extractors jail to the guest root. bootc still resolves /sysroot.
    && ln -sfn /sysroot/ostree/bootc/storage /usr/lib/bootc/storage \
    && test "$(readlink /usr/lib/bootc/storage)" = "/sysroot/ostree/bootc/storage"

# ---------- osbuild image-builder (disk image building) ----------
# osbuild/image-builder produces OS disk images (qcow2/raw/Anaconda) without a
# hypervisor, complementing the bootc/OCI tooling above. It is not in the
# Fedora repos, so enable the @osbuild/osbuild and @osbuild/image-builder COPR
# groups first. The COPR stack moves quickly, so pin the package version and
# verify the CLI at build time. There is no Renovate datasource for COPR
# packages, so this ARG is versioned manually.
ARG IMAGE_BUILDER_VERSION=85.0.0
RUN dnf -y copr enable @osbuild/osbuild \
    && dnf -y copr enable @osbuild/image-builder \
    && dnf -y install "image-builder-${IMAGE_BUILDER_VERSION}" \
    && dnf clean all \
    && command -v image-builder \
    && image-builder version | grep -F "version: ${IMAGE_BUILDER_VERSION}"

# ---------- cloud-init nocloud seed ISO tooling ----------
# cloud-localds produces the cloud-init nocloud seed ISO (user-data / meta-data)
# that is attached to the qcow2/raw images built above so they can boot with
# cloud-init. It depends on genisoimage, which provides mkisofs. util-linux is
# needed explicitly: cloud-localds shells out to getopt, which the minimal
# Fedora base does not ship.
RUN dnf -y install cloud-utils-cloud-localds util-linux \
    && dnf clean all \
    && command -v cloud-localds \
    && command -v mkisofs \
    && command -v getopt
RUN printf '\n# Prepare rootless Podman storage on the /storage ext4 disk for this sandbox.\ncommand -v podman >/dev/null 2>&1 && sudo -n start-podman >/dev/null 2>&1 || true\n' >> /home/agent1/.bashrc && \
    printf '\n# Prepare rootless Podman storage on the /storage ext4 disk for this sandbox.\ncommand -v podman >/dev/null 2>&1 && sudo -n start-podman >/dev/null 2>&1 || true\n' >> /home/agent1/.profile && \
    chown 1000:1000 /home/agent1/.bashrc /home/agent1/.profile


# ==============================================================================
# TOOL SECTIONS - Edit these to customize your image
# ==============================================================================

# ---------- Core tools ----------
RUN dnf -y install \
    # Shell essentials
    git curl wget2 jq unzip zip tar tree less vim-enhanced \
    # Search and navigation
    ripgrep fd-find bat bubblewrap \
    # Process and network
    htop procps-ng iproute lsof strace \
    # Build essentials (needed for native npm addons)
    gcc gcc-c++ make pkgconf-pkg-config \
    postgresql redis sqlite \
    # SSH client (NOT server)
    openssh-clients \
    ImageMagick \
    tmux \
    && dnf clean all

RUN chmod u+s /usr/bin/bwrap

# ---------- bat symlink (Debian names it batcat) ----------
RUN ln -sf /usr/bin/batcat /usr/local/bin/bat 2>/dev/null || true

# ---------- fzf ----------
COPY --from=fzf-builder /out/fzf /usr/local/bin/fzf

# ---------- Python 3 (for user projects) ----------
RUN dnf -y install python3 python3-pip python3-devel patch which \
    && dnf clean all

RUN dnf -y install pandoc-cli ffmpeg-free \
    && dnf clean all \
    && pandoc --version | head -1 \
    && ffmpeg -version | head -1

# ---------- GitHub CLI ----------
COPY --from=github-cli-builder /out/gh /usr/local/bin/gh
RUN gh --version | grep -F "gh version ${GITHUB_CLI_VERSION}"

# ---------- lazygit ----------
COPY --from=lazygit-builder /out/lazygit /usr/local/bin/lazygit
RUN lazygit --version | grep -F "version=${LAZYGIT_VERSION}"

# ---------- goose (agentic CLI) ----------
RUN curl -fsSL https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh \
    | GOOSE_VERSION="${GOOSE_VERSION}" GOOSE_BIN_DIR=/usr/local/bin CONFIGURE=false bash \
    && goose --version | grep -F "${GOOSE_VERSION}"

# ---------- delta (git diff pager) ----------
RUN DELTA_ARCH=$(case "$TARGETARCH" in arm64) echo "aarch64-unknown-linux-gnu";; *) echo "x86_64-unknown-linux-gnu";; esac) && \
    DELTA_SHA256=$(case "$TARGETARCH" in \
      arm64) echo "0bfce159a5cddd5feb3d6db4a616d883ff51253ce08ac7ec11cb1d208cfaab9e";; \
      *) echo "8e695c5f586a8c53d6c3b01be0b4a422ed218bfed2a56191caebe373a1c18ab2";; \
    esac) && \
    curl --disable --retry 8 --retry-all-errors --retry-max-time 300 --remove-on-error --connect-timeout 15 --max-time 300 -fsSL -o /tmp/delta.tar.gz \
      "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${DELTA_ARCH}.tar.gz" && \
    echo "${DELTA_SHA256}  /tmp/delta.tar.gz" | sha256sum -c - && \
    tar -C /tmp -xzf /tmp/delta.tar.gz && \
    install -m 0755 "/tmp/delta-${DELTA_VERSION}-${DELTA_ARCH}/delta" /usr/local/bin/delta && \
    rm -rf /tmp/delta.tar.gz "/tmp/delta-${DELTA_VERSION}-${DELTA_ARCH}"

# ---------- eza (modern ls replacement) ----------
RUN EZA_ARCH=$(case "$TARGETARCH" in arm64) echo "aarch64";; *) echo "x86_64";; esac) && \
    EZA_SHA256=$(case "$TARGETARCH" in \
      arm64) echo "40b87ae8628aa2ff0f0d2dc24ab52f689631366385c3da630bae745671fd71ec";; \
      *) echo "35c70c5c43c29108075e58b893234c67ef585f0b53a7eaf8e9e7d4eec9f339b4";; \
    esac) && \
    curl --disable --retry 8 --retry-all-errors --retry-max-time 300 --remove-on-error --connect-timeout 15 --max-time 300 -fsSL -o /tmp/eza.tar.gz \
      "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz" && \
    echo "${EZA_SHA256}  /tmp/eza.tar.gz" | sha256sum -c - && \
    tar -C /usr/local/bin -xzf /tmp/eza.tar.gz && \
    rm /tmp/eza.tar.gz

# ---------- Headless browser (Chromium + Xvfb + fonts) ----------
RUN dnf -y install \
    chromium \
    xorg-x11-server-Xvfb \
    liberation-sans-fonts liberation-mono-fonts liberation-serif-fonts \
    dejavu-sans-mono-fonts google-noto-sans-fonts google-noto-color-emoji-fonts \
    && dnf clean all \
    # Fedora ships the userns sandbox (not a setuid helper), so require the
    # sandbox binary to exist rather than carry the setuid bit.
    && test -x /usr/lib64/chromium-browser/chrome-sandbox \
    && test -x /usr/bin/chromium-browser \
    && rpm -q --qf '%{VERSION}\n' chromium | grep -E '^(15[1-9]|1[6-9][0-9]|[2-9][0-9]{2})\.' \
    && chromium-browser --version

# ---------- Python packages ----------
COPY config/python-requirements.lock /usr/local/share/holycode/python-requirements.lock
COPY config/python-seed-requirements.lock /usr/local/share/holycode/python-seed-requirements.lock
COPY patches/pip-vendored-pkg-resources-78.1.1.patch /tmp/pip-vendored-pkg-resources.patch
RUN pyver="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')" && \
    python3 -m venv /tmp/holycode-pip-bootstrap && \
    /tmp/holycode-pip-bootstrap/bin/python -m pip install --no-cache-dir --upgrade \
      --require-hashes -r /usr/local/share/holycode/python-seed-requirements.lock && \
    /tmp/holycode-pip-bootstrap/bin/python -m pip install --no-cache-dir --upgrade \
      --target "/usr/local/lib/python${pyver}/site-packages" \
      --require-hashes -r /usr/local/share/holycode/python-seed-requirements.lock && \
    install -m 0755 /tmp/holycode-pip-bootstrap/bin/pip /usr/local/bin/pip && \
    sed -i '1c#!/usr/bin/python3' /usr/local/bin/pip && \
    ln -sf pip /usr/local/bin/pip3 && \
    ln -sf pip "/usr/local/bin/pip3.${pyver}" && \
    rm -rf /tmp/holycode-pip-bootstrap && \
    python3 -m pip install --no-cache-dir --break-system-packages --ignore-installed \
      --require-hashes -r /usr/local/share/holycode/python-requirements.lock

# Replace Debian's vulnerable wheel metadata after installing fixed copies in
# /usr/local. pip remains available from the exact PyPI package.
RUN python3 -m pip install --no-cache-dir --break-system-packages --ignore-installed \
      --require-hashes -r /usr/local/share/holycode/python-seed-requirements.lock && \
    curl --disable --retry 8 --retry-all-errors --retry-max-time 300 --remove-on-error --connect-timeout 15 --max-time 300 -fsSL -o /tmp/msgpack.tar.gz \
      "https://files.pythonhosted.org/packages/6d/44/ea2100ec54d30c46ee9dba10a3bfb79b655e96c6df237238a3234c75869b/msgpack-${PIP_VENDOR_MSGPACK_VERSION}.tar.gz" && \
    echo "${PIP_VENDOR_MSGPACK_SHA256}  /tmp/msgpack.tar.gz" | sha256sum -c - && \
    curl --disable --retry 8 --retry-all-errors --retry-max-time 300 --remove-on-error --connect-timeout 15 --max-time 300 -fsSL -o /tmp/setuptools.tar.gz \
      "https://files.pythonhosted.org/packages/81/9c/42314ee079a3e9c24b27515f9fbc7a3c1d29992c33451779011c74488375/setuptools-${PIP_VENDOR_PKG_RESOURCES_VERSION}.tar.gz" && \
    echo "${PIP_VENDOR_PKG_RESOURCES_SHA256}  /tmp/setuptools.tar.gz" | sha256sum -c - && \
    mkdir -p /tmp/msgpack /tmp/setuptools && \
    tar -xzf /tmp/msgpack.tar.gz -C /tmp/msgpack --strip-components=1 && \
    tar -xzf /tmp/setuptools.tar.gz -C /tmp/setuptools --strip-components=1 && \
    (cd /tmp/setuptools && patch -p1 < /tmp/pip-vendored-pkg-resources.patch) && \
    PIP_VENDOR_DIR="$(python3 -c 'import pathlib,pip._vendor; print(pathlib.Path(pip._vendor.__file__).parent)')" && \
    rm -rf "$PIP_VENDOR_DIR/msgpack" "$PIP_VENDOR_DIR/pkg_resources" && \
    cp -a /tmp/msgpack/msgpack "$PIP_VENDOR_DIR/msgpack" && \
    cp -a /tmp/setuptools/pkg_resources "$PIP_VENDOR_DIR/pkg_resources" && \
    cp /tmp/msgpack/COPYING "$PIP_VENDOR_DIR/msgpack/COPYING" && \
    cp /tmp/setuptools/LICENSE "$PIP_VENDOR_DIR/pkg_resources/LICENSE" && \
    rm -rf "$PIP_VENDOR_DIR/pkg_resources/tests" "$PIP_VENDOR_DIR/pkg_resources/api_tests.txt" && \
    sed -i \
      "s/^msgpack==.*/msgpack==${PIP_VENDOR_MSGPACK_VERSION}/; s/^setuptools==.*/setuptools==${PIP_VENDOR_PKG_RESOURCES_VERSION}/" \
      "$PIP_VENDOR_DIR/vendor.txt" && \
    python3 -c 'import json,pathlib,sys; path=pathlib.Path(sys.argv[1]); data=json.loads(path.read_text()); versions={"msgpack":sys.argv[2],"setuptools":sys.argv[3]}; [(component.update(version=versions[component["name"]],purl="pkg:pypi/{0}@{1}".format(component["name"],versions[component["name"]])) if component.get("name") in versions else None) for component in data.get("components",[])]; path.write_text(json.dumps(data,indent=2)+"\n")' \
      "$PIP_VENDOR_DIR/bom.cdx.json" "$PIP_VENDOR_MSGPACK_VERSION" "$PIP_VENDOR_PKG_RESOURCES_VERSION" && \
    rm -rf /tmp/msgpack /tmp/setuptools /tmp/msgpack.tar.gz /tmp/setuptools.tar.gz \
      /tmp/pip-vendored-pkg-resources.patch && \
    dnf clean all >/dev/null 2>&1 || true; \
    python3 -m pip --version | grep -F "pip ${PIP_VERSION}" && \
    python3 -c 'import pip._vendor.msgpack as msgpack; assert msgpack.__version__ == "1.2.2"; assert msgpack.unpackb(msgpack.packb({"holycode": True})) == {"holycode": True}; import pip._vendor.pkg_resources' && \
    _PIP_USE_IMPORTLIB_METADATA=0 python3 -m pip list --format=json >/dev/null && \
    python3 -c 'import setuptools; assert setuptools.__version__ == "84.0.0"' && \
    python3 -m pip check

RUN rm -f /usr/local/bin/dotenv

# Install the pinned npm into /usr/local (respecting NPM_CONFIG_PREFIX=/usr/local,
# so it lands at /usr/local/lib/node_modules/npm and its vulnerability patches
# below apply to the canonical location). After the install, clear the shell's
# command hash so the freshly-installed /usr/local/bin/npm is used instead of the
# stale cache pointing at nvm's bundled npm.
RUN npm install -g --ignore-scripts "npm@${NPM_VERSION}" && \
    hash -r && \
    test "$(npm --version)" = "${NPM_VERSION}" && \
    rm -rf /root/.npm
RUN test "$(npm view "brace-expansion@${NPM_BRACE_EXPANSION_VERSION}" dist.integrity)" = \
      "sha512-YovQ3rzhaLMIrDjNDMkNS01tea93qhEhG5xy8f6+R0l+dw3Ki+5sCoIoI942iuLZTHWogWktgwVDhU09iNEimQ==" && \
    BRACE_TARBALL=$(npm pack --silent --pack-destination /tmp \
      "brace-expansion@${NPM_BRACE_EXPANSION_VERSION}") && \
    BRACE_DIR=/usr/local/lib/node_modules/npm/node_modules/brace-expansion && \
    rm -rf "$BRACE_DIR" && mkdir "$BRACE_DIR" && \
    tar -xzf "/tmp/${BRACE_TARBALL}" -C "$BRACE_DIR" --strip-components=1 && \
    rm "/tmp/${BRACE_TARBALL}" && \
    test "$(node -p 'require("/usr/local/lib/node_modules/npm/node_modules/brace-expansion/package.json").version')" = \
      "${NPM_BRACE_EXPANSION_VERSION}" && \
    (cd /usr/local/lib/node_modules/npm && npm ls brace-expansion --all >/dev/null) && \
    rm -rf /root/.npm
RUN test "$(npm view "tar@${NPM_TAR_VERSION}" dist.integrity)" = \
      "sha512-MFO/QzvtAOmJbkhOaCTvbGcFN9L9b+JunIsDwaKljSOdcLMea3NJ1k9Usz/rjdfSXTq4dfzfeS7W4p4YOAAHeA==" && \
    NPM_TAR_TARBALL=$(npm pack --silent --pack-destination /tmp "tar@${NPM_TAR_VERSION}") && \
    NPM_TAR_DIR=/usr/local/lib/node_modules/npm/node_modules/tar && \
    rm -rf "$NPM_TAR_DIR" && mkdir "$NPM_TAR_DIR" && \
    tar -xzf "/tmp/${NPM_TAR_TARBALL}" -C "$NPM_TAR_DIR" --strip-components=1 && \
    rm "/tmp/${NPM_TAR_TARBALL}" && \
    test "$(node -p 'require("/usr/local/lib/node_modules/npm/node_modules/tar/package.json").version')" = \
      "${NPM_TAR_VERSION}" && \
    (cd /usr/local/lib/node_modules/npm && npm ls tar --all >/dev/null) && \
    rm -rf /root/.npm
# npm 12.1.0 resolves ip-address 10.5.0 through socks. Keep the compatible
# socks range and replace that nested copy with the fixed 10.7.2 release.
RUN test "$(npm view "ip-address@${NPM_IP_ADDRESS_VERSION}" dist.integrity)" = \
      "sha512-7H/2gFSIitxc0hG3nOI1glS8QLo/EHBFFLk8vEUjXY/xu0AdL8jZ9U1IzO2PUm0d2D/ofQcAifb0g6OBkt8U7w==" && \
    NPM_IP_ADDRESS_TARBALL=$(npm pack --silent --pack-destination /tmp \
      "ip-address@${NPM_IP_ADDRESS_VERSION}") && \
    NPM_IP_ADDRESS_DIR=/usr/local/lib/node_modules/npm/node_modules/ip-address && \
    NPM_SOCKS_PACKAGE=/usr/local/lib/node_modules/npm/node_modules/socks/package.json && \
    node -e 'const pkg=require(process.argv[1]); if(pkg.version!=="2.8.9" || pkg.dependencies["ip-address"]!=="^10.1.1") process.exit(1)' \
      "$NPM_SOCKS_PACKAGE" && \
    rm -rf "$NPM_IP_ADDRESS_DIR" && mkdir "$NPM_IP_ADDRESS_DIR" && \
    tar -xzf "/tmp/${NPM_IP_ADDRESS_TARBALL}" -C "$NPM_IP_ADDRESS_DIR" --strip-components=1 && \
    rm "/tmp/${NPM_IP_ADDRESS_TARBALL}" && \
    test "$(node -p 'require("/usr/local/lib/node_modules/npm/node_modules/ip-address/package.json").version')" = \
      "${NPM_IP_ADDRESS_VERSION}" && \
    (cd /usr/local/lib/node_modules/npm && npm ls ip-address --all >/dev/null) && \
    test "$(npm prefix -g)" = "/usr/local" && \
    rm -rf /root/.npm

# ---------- OpenCode (AI coding agent) ----------
# Installed via npm as root (global install needs write access to /usr/local/lib)
RUN npm i -g --ignore-scripts "@opencode/cli@${OPENCODE_VERSION}" "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
      "@fission-ai/openspec@${OPENSPEC_VERSION}" && \
    rm -rf /root/.npm
ENV PATH="/home/agent1/.local/bin:${PATH}"

# Drizzle Kit's stable release still declares an unused legacy loader and older
# nested esbuild; remove both in the install layer and use the audited global pin.
RUN npm i -g --ignore-scripts \
    "typescript@${TYPESCRIPT_VERSION}" "tsx@${TSX_VERSION}" \
    "pnpm@${PNPM_VERSION}" \
    "vite@${VITE_VERSION}" esbuild@0.28.2 \
    "eslint@${ESLINT_VERSION}" "prettier@${PRETTIER_VERSION}" \
    nodemon@3.1.14 \
    dotenv-cli@11.0.0 \
    "wrangler@${WRANGLER_VERSION}" \
    pm2@7.0.4 \
    "prisma@${PRISMA_VERSION}" drizzle-kit@0.31.11 \
    "lighthouse@${LIGHTHOUSE_VERSION}" \
    json-server@0.17.4 http-server@14.1.1 && \
    DRIZZLE_DIR=/usr/local/lib/node_modules/drizzle-kit && \
    jq '.dependencies |= del(."@esbuild-kit/esm-loader") | .dependencies.esbuild = "0.28.2"' \
      "$DRIZZLE_DIR/package.json" > "$DRIZZLE_DIR/package.json.tmp" && \
    mv "$DRIZZLE_DIR/package.json.tmp" "$DRIZZLE_DIR/package.json" && \
    rm -rf \
      "$DRIZZLE_DIR/node_modules/@esbuild-kit" \
      "$DRIZZLE_DIR/node_modules/@esbuild" \
      "$DRIZZLE_DIR/node_modules/esbuild" && \
    ln -s ../../esbuild "$DRIZZLE_DIR/node_modules/esbuild" && \
    test "$(node -p 'require("/usr/local/lib/node_modules/drizzle-kit/node_modules/esbuild/package.json").version')" = "0.28.2" && \
    drizzle-kit --version && \
    drizzle-kit --help >/dev/null && \
    rm -rf /root/.npm

# Prisma 7.10.0 pins deepmerge-ts 7.1.5 and mysql2 3.15.3. Replace only those
# nested copies and materialize mysql2's required declaration peer from verified payloads.
RUN PRISMA_TYPES_NODE_INTEGRITY="sha512-6oYBAi5ikg4Pl+kGsoYtawUMBT2zZMCvPNF7pVLnHZfd1zf38DRiWn/gT01RYCdUqkv7Fhr+C9ot4/tb+2sVvA==" && \
    PRISMA_UNDICI_TYPES_INTEGRITY="sha512-iwDZqg0QAGrg9Rav5H4n0M64c3mkR59cJ6wQp+7C4nI0gsmExaedaYLNO44eT4AtBBwjbTiGPMlt2Md0T9H9JQ==" && \
    test "$(npm view "deepmerge-ts@${PRISMA_DEEPMERGE_VERSION}" dist.integrity)" = \
      "sha512-uqbvqLUMrc6p0MO+WBRtTxY55hmyh94WRwI5a++PZe54X+bfVh59FSN7uWCBCW1CCVjzjnrwzfI8zidE2obMMw==" && \
    test "$(npm view "mysql2@${PRISMA_MYSQL2_VERSION}" dist.integrity)" = \
      "sha512-A2olluVlj0mvgyIRRISMEzXc51m+21mRtcMVjJyIpt2GG98+XrC9m9HzsqcMsX2LcnfccJvY5NB22g8fENBnOA==" && \
    test "$(npm view "@types/node@${PRISMA_TYPES_NODE_VERSION}" dist.integrity)" = "$PRISMA_TYPES_NODE_INTEGRITY" && \
    test "$(npm view "undici-types@${PRISMA_UNDICI_TYPES_VERSION}" dist.integrity)" = "$PRISMA_UNDICI_TYPES_INTEGRITY" && \
    test "$(npm view "@prisma/config@${PRISMA_VERSION}" dependencies.deepmerge-ts)" = "7.1.5" && \
    test "$(npm view "prisma@${PRISMA_VERSION}" dependencies.mysql2)" = "3.15.3" && \
    PRISMA_DEEPMERGE_TARBALL=$(npm pack --silent --pack-destination /tmp \
      "deepmerge-ts@${PRISMA_DEEPMERGE_VERSION}") && \
    PRISMA_MYSQL2_TARBALL=$(npm pack --silent --pack-destination /tmp \
      "mysql2@${PRISMA_MYSQL2_VERSION}") && \
    PRISMA_TYPES_NODE_TARBALL=/tmp/prisma-types-node.tgz && \
    PRISMA_UNDICI_TYPES_TARBALL=/tmp/prisma-undici-types.tgz && \
    curl --disable --retry 8 --retry-all-errors --retry-max-time 300 --remove-on-error --connect-timeout 15 --max-time 300 -fsSL \
      -o "$PRISMA_TYPES_NODE_TARBALL" \
      "https://registry.npmjs.org/@types/node/-/node-${PRISMA_TYPES_NODE_VERSION}.tgz" && \
    curl --disable --retry 8 --retry-all-errors --retry-max-time 300 --remove-on-error --connect-timeout 15 --max-time 300 -fsSL \
      -o "$PRISMA_UNDICI_TYPES_TARBALL" \
      "https://registry.npmjs.org/undici-types/-/undici-types-${PRISMA_UNDICI_TYPES_VERSION}.tgz" && \
    node -e 'const fs=require("fs"); const crypto=require("crypto"); const actual=`sha512-${crypto.createHash("sha512").update(fs.readFileSync(process.argv[1])).digest("base64")}`; if(actual!==process.argv[2]) process.exit(1)' \
      "$PRISMA_TYPES_NODE_TARBALL" "$PRISMA_TYPES_NODE_INTEGRITY" && \
    node -e 'const fs=require("fs"); const crypto=require("crypto"); const actual=`sha512-${crypto.createHash("sha512").update(fs.readFileSync(process.argv[1])).digest("base64")}`; if(actual!==process.argv[2]) process.exit(1)' \
      "$PRISMA_UNDICI_TYPES_TARBALL" "$PRISMA_UNDICI_TYPES_INTEGRITY" && \
    PRISMA_DEEPMERGE_DIR=/usr/local/lib/node_modules/prisma/node_modules/deepmerge-ts && \
    PRISMA_MYSQL2_DIR=/usr/local/lib/node_modules/prisma/node_modules/mysql2 && \
    PRISMA_TYPES_NODE_DIR=/usr/local/lib/node_modules/prisma/node_modules/@types/node && \
    PRISMA_UNDICI_TYPES_DIR=/usr/local/lib/node_modules/prisma/node_modules/undici-types && \
    PRISMA_PACKAGE=/usr/local/lib/node_modules/prisma/package.json && \
    PRISMA_CONFIG_PACKAGE=/usr/local/lib/node_modules/prisma/node_modules/@prisma/config/package.json && \
    test "$(node -p 'require(process.argv[1]).version' "$PRISMA_PACKAGE")" = "${PRISMA_VERSION}" && \
    test ! -e "$PRISMA_TYPES_NODE_DIR" && \
    test ! -e "$PRISMA_UNDICI_TYPES_DIR" && \
    rm -rf "$PRISMA_DEEPMERGE_DIR" && mkdir "$PRISMA_DEEPMERGE_DIR" && \
    tar -xzf "/tmp/${PRISMA_DEEPMERGE_TARBALL}" -C "$PRISMA_DEEPMERGE_DIR" --strip-components=1 && \
    rm -rf "$PRISMA_MYSQL2_DIR" && mkdir "$PRISMA_MYSQL2_DIR" && \
    tar -xzf "/tmp/${PRISMA_MYSQL2_TARBALL}" -C "$PRISMA_MYSQL2_DIR" --strip-components=1 && \
    node -e 'const pkg=require(process.argv[1]); if(pkg.version!==process.argv[2] || pkg.peerDependencies["@types/node"]!==">= 8" || pkg.peerDependenciesMeta?.["@types/node"]!==undefined) process.exit(1)' \
      "$PRISMA_MYSQL2_DIR/package.json" "${PRISMA_MYSQL2_VERSION}" && \
    mkdir -p "$PRISMA_TYPES_NODE_DIR" "$PRISMA_UNDICI_TYPES_DIR" && \
    tar -xzf "$PRISMA_TYPES_NODE_TARBALL" -C "$PRISMA_TYPES_NODE_DIR" --strip-components=1 && \
    tar -xzf "$PRISMA_UNDICI_TYPES_TARBALL" -C "$PRISMA_UNDICI_TYPES_DIR" --strip-components=1 && \
    npm install --prefix "$PRISMA_MYSQL2_DIR" --ignore-scripts --package-lock=false --omit=dev && \
    rm "/tmp/${PRISMA_DEEPMERGE_TARBALL}" "/tmp/${PRISMA_MYSQL2_TARBALL}" \
      "$PRISMA_TYPES_NODE_TARBALL" "$PRISMA_UNDICI_TYPES_TARBALL" && \
    node -e 'const fs=require("fs"); const file=process.argv[1]; const version=process.argv[2]; const pkg=JSON.parse(fs.readFileSync(file,"utf8")); if(pkg.dependencies["deepmerge-ts"]!=="7.1.5") process.exit(1); pkg.dependencies["deepmerge-ts"]=version; fs.writeFileSync(file,`${JSON.stringify(pkg,null,2)}\n`)' \
      "$PRISMA_CONFIG_PACKAGE" "${PRISMA_DEEPMERGE_VERSION}" && \
    node -e 'const fs=require("fs"); const file=process.argv[1]; const version=process.argv[2]; const pkg=JSON.parse(fs.readFileSync(file,"utf8")); if(pkg.dependencies.mysql2!=="3.15.3") process.exit(1); pkg.dependencies.mysql2=version; fs.writeFileSync(file,`${JSON.stringify(pkg,null,2)}\n`)' \
      "$PRISMA_PACKAGE" "${PRISMA_MYSQL2_VERSION}" && \
    test "$(node -p 'require("/usr/local/lib/node_modules/prisma/node_modules/deepmerge-ts/package.json").version')" = \
      "${PRISMA_DEEPMERGE_VERSION}" && \
    test "$(node -p 'require("/usr/local/lib/node_modules/prisma/node_modules/mysql2/package.json").version')" = \
      "${PRISMA_MYSQL2_VERSION}" && \
    node -e 'const pkg=require(process.argv[1]); if(pkg.version!==process.argv[2] || pkg.types!=="index.d.ts" || pkg.main!=="" || pkg.dependencies["undici-types"]!=="~6.21.0") process.exit(1)' \
      "$PRISMA_TYPES_NODE_DIR/package.json" "${PRISMA_TYPES_NODE_VERSION}" && \
    test "$(node -p 'require(process.argv[1]).version' "$PRISMA_UNDICI_TYPES_DIR/package.json")" = \
      "${PRISMA_UNDICI_TYPES_VERSION}" && \
    test -s "$PRISMA_TYPES_NODE_DIR/index.d.ts" && \
    test -s "$PRISMA_UNDICI_TYPES_DIR/fetch.d.ts" && \
    node -e 'const resolved=require.resolve("@types/node/package.json",{paths:[process.argv[1]]}); const pkg=require(resolved); if(pkg.version!==process.argv[2] || resolved!==process.argv[3]) process.exit(1)' \
      "$PRISMA_MYSQL2_DIR" "${PRISMA_TYPES_NODE_VERSION}" "$PRISMA_TYPES_NODE_DIR/package.json" && \
    node -e 'const resolved=require.resolve("undici-types/package.json",{paths:[process.argv[1]]}); const pkg=require(resolved); if(pkg.version!==process.argv[2] || resolved!==process.argv[3]) process.exit(1)' \
      "$PRISMA_TYPES_NODE_DIR" "${PRISMA_UNDICI_TYPES_VERSION}" "$PRISMA_UNDICI_TYPES_DIR/package.json" && \
    (cd /usr/local/lib/node_modules/prisma && npm ls deepmerge-ts mysql2 @types/node undici-types --all >/dev/null) && \
    node -e 'const mysql=require("/usr/local/lib/node_modules/prisma/node_modules/mysql2"); if(typeof mysql.createConnection!=="function") process.exit(1)' && \
    prisma --version >/dev/null && \
    rm -rf /root/.npm

# PM2 7.0.4 directly pins vulnerable js-yaml 4.3.1. Replace only that nested
# package and bind the owner's exact dependency declaration to the fixed v4 release.
RUN PM2_JS_YAML_INTEGRITY="sha512-SFNOvSJ+Dgf/9An904Yx+CgSlIPCkIpao4qo51lpee25TIRejdH3rhR4EZMGoNx3/TP3O+wzWuiTFl4sqbltzA==" && \
    test "$(npm view "js-yaml@${PM2_JS_YAML_VERSION}" dist.integrity)" = "$PM2_JS_YAML_INTEGRITY" && \
    test "$(npm view pm2@7.0.4 dependencies.js-yaml)" = "4.3.1" && \
    PM2_PACKAGE=/usr/local/lib/node_modules/pm2/package.json && \
    PM2_JS_YAML_DIR=/usr/local/lib/node_modules/pm2/node_modules/js-yaml && \
    test "$(node -p 'require(process.argv[1]).version' "$PM2_PACKAGE")" = "7.0.4" && \
    test "$(node -p 'require("/usr/local/lib/node_modules/pm2/node_modules/js-yaml/package.json").version')" = \
      "4.3.1" && \
    node -e 'const pkg=require(process.argv[1]); if(pkg.dependencies["js-yaml"]!=="4.3.1") process.exit(1)' \
      "$PM2_PACKAGE" && \
    PM2_JS_YAML_TARBALL=$(npm pack --silent --ignore-scripts --pack-destination /tmp \
      "js-yaml@${PM2_JS_YAML_VERSION}") && \
    node -e 'const fs=require("fs"); const crypto=require("crypto"); const actual=`sha512-${crypto.createHash("sha512").update(fs.readFileSync(process.argv[1])).digest("base64")}`; if(actual!==process.argv[2]) process.exit(1)' \
      "/tmp/${PM2_JS_YAML_TARBALL}" "$PM2_JS_YAML_INTEGRITY" && \
    rm -rf "$PM2_JS_YAML_DIR" && mkdir "$PM2_JS_YAML_DIR" && \
    tar -xzf "/tmp/${PM2_JS_YAML_TARBALL}" -C "$PM2_JS_YAML_DIR" --strip-components=1 && \
    rm "/tmp/${PM2_JS_YAML_TARBALL}" && \
    node -e 'const fs=require("fs"); const file=process.argv[1]; const version=process.argv[2]; const pkg=JSON.parse(fs.readFileSync(file,"utf8")); if(pkg.dependencies["js-yaml"]!=="4.3.1") process.exit(1); pkg.dependencies["js-yaml"]=version; fs.writeFileSync(file,`${JSON.stringify(pkg,null,2)}\n`)' \
      "$PM2_PACKAGE" "${PM2_JS_YAML_VERSION}" && \
    test "$(node -p 'require("/usr/local/lib/node_modules/pm2/node_modules/js-yaml/package.json").version')" = \
      "${PM2_JS_YAML_VERSION}" && \
    node -e 'const pkg=require(process.argv[1]); if(pkg.dependencies["js-yaml"]!==process.argv[2]) process.exit(1)' \
      "$PM2_PACKAGE" "${PM2_JS_YAML_VERSION}" && \
    (cd /usr/local/lib/node_modules/pm2 && npm ls js-yaml --all >/dev/null) && \
    node -e 'const yaml=require("/usr/local/lib/node_modules/pm2/node_modules/js-yaml"); const parsed=yaml.load("service:\n  enabled: true\n"); if(parsed.service.enabled!==true) process.exit(1)' && \
    PM2_APP=/tmp/holycode-build-pm2-app.js && \
    printf 'setInterval(() => {}, 60000);\n' > "$PM2_APP" && \
    PM2_HOME=/tmp/holycode-build-pm2 pm2 start "$PM2_APP" --name holycode-build-pm2 --no-autorestart >/dev/null && \
    PM2_HOME=/tmp/holycode-build-pm2 pm2 --version | grep -Fx "7.0.4" && \
    PM2_HOME=/tmp/holycode-build-pm2 pm2 stop holycode-build-pm2 >/dev/null && \
    PM2_HOME=/tmp/holycode-build-pm2 pm2 kill >/dev/null && \
    rm -rf /tmp/holycode-build-pm2 "$PM2_APP" && \
    rm -rf /root/.npm

# Wrangler 4.138.0 owns Miniflare 5.20260921.1-alpha and workerd 1.20260921.1;
# Miniflare owns the same workerd and the fixed Sharp release. Bind each owner.
RUN WRANGLER_SHARP_INTEGRITY="sha512-n++8XWcj+jCOr2IOl7h8LbKnGBDY4aPbmprMONBNFdn0ImXqpGVv5zliDs0V9HbmbCQLpbuo2ej9rAoOQTvMDA==" && \
    test "$(npm view "sharp@${WRANGLER_SHARP_VERSION}" dist.integrity)" = "$WRANGLER_SHARP_INTEGRITY" && \
    test "$(npm view "wrangler@${WRANGLER_VERSION}" dependencies.miniflare)" = "${WRANGLER_MINIFLARE_VERSION}" && \
    test "$(npm view "wrangler@${WRANGLER_VERSION}" dependencies.workerd)" = "1.20260921.1" && \
    test "$(npm view "miniflare@${WRANGLER_MINIFLARE_VERSION}" dependencies.sharp)" = "${WRANGLER_SHARP_VERSION}" && \
    test "$(npm view "miniflare@${WRANGLER_MINIFLARE_VERSION}" dependencies.workerd)" = "1.20260921.1" && \
    WRANGLER_PACKAGE=/usr/local/lib/node_modules/wrangler/package.json && \
    WRANGLER_NODE_MODULES=/usr/local/lib/node_modules/wrangler/node_modules && \
    WRANGLER_MINIFLARE_PACKAGE="$WRANGLER_NODE_MODULES/miniflare/package.json" && \
    WRANGLER_WORKERD_PACKAGE="$WRANGLER_NODE_MODULES/workerd/package.json" && \
    WRANGLER_SHARP_DIR="$WRANGLER_NODE_MODULES/sharp" && \
    test "$(node -p 'require(process.argv[1]).version' "$WRANGLER_PACKAGE")" = "${WRANGLER_VERSION}" && \
    node -e 'const pkg=require(process.argv[1]); if(pkg.dependencies.miniflare!==process.argv[2] || pkg.dependencies.workerd!=="1.20260921.1") process.exit(1)' \
      "$WRANGLER_PACKAGE" "${WRANGLER_MINIFLARE_VERSION}" && \
    node -e 'const pkg=require(process.argv[1]); if(pkg.version!==process.argv[2] || pkg.dependencies.sharp!==process.argv[3]) process.exit(1)' \
      "$WRANGLER_MINIFLARE_PACKAGE" "${WRANGLER_MINIFLARE_VERSION}" "${WRANGLER_SHARP_VERSION}" && \
    node -e 'const pkg=require(process.argv[1]); if(pkg.dependencies.workerd!=="1.20260921.1") process.exit(1)' \
      "$WRANGLER_MINIFLARE_PACKAGE" && \
    test "$(node -p 'require(process.argv[1]).version' "$WRANGLER_WORKERD_PACKAGE")" = \
      "1.20260921.1" && \
    test "$(node -p 'require(process.argv[1]).version' "$WRANGLER_SHARP_DIR/package.json")" = \
      "${WRANGLER_SHARP_VERSION}" && \
    case "${TARGETARCH}" in \
      amd64) WRANGLER_SHARP_ARCH=x64; \
        WRANGLER_SHARP_NATIVE_INTEGRITY="sha512-9qvvEAuk8k89TfWUoX2htWjbAMX8p+NxCppjpcg5k6xMsjhBQPTsoIh36h9Qde4WRuGpJeYnOjdosDn/cnv+OA=="; \
        WRANGLER_SHARP_LIBVIPS_INTEGRITY="sha512-4vKmvAst9nrowcqquKFAyZJUDolUaIp8uRiN0mWFguJ1IplC9/pitXtlnnlU4aa/eJw3J7i67V+pwUL+wZGdsA==";; \
      arm64) WRANGLER_SHARP_ARCH=arm64; \
        WRANGLER_SHARP_NATIVE_INTEGRITY="sha512-De4jpEnAU8Hd5oT0j1G3uL4ZvTuipVMn7YC6vPaJhy6/7EwEae0SVAoBrUMYQbkLGDm85taVWwuPc1a44LTzCQ=="; \
        WRANGLER_SHARP_LIBVIPS_INTEGRITY="sha512-0DaL0A6Xu6sQSQFwe4iVCrKWU2cCTItnRsYsCdxAMm9NF6twAA9BKnoqy4hqz4+azQ0JHuA26qiUKsf1XJ/v5A==";; \
      *) echo "unsupported Sharp target architecture: ${TARGETARCH}" >&2; exit 1;; \
    esac && \
    WRANGLER_SHARP_NATIVE_PACKAGE="@img/sharp-linux-${WRANGLER_SHARP_ARCH}" && \
    WRANGLER_SHARP_LIBVIPS_PACKAGE="@img/sharp-libvips-linux-${WRANGLER_SHARP_ARCH}" && \
    WRANGLER_SHARP_NATIVE_DIR="$WRANGLER_NODE_MODULES/@img/sharp-linux-${WRANGLER_SHARP_ARCH}" && \
    WRANGLER_SHARP_LIBVIPS_DIR="$WRANGLER_NODE_MODULES/@img/sharp-libvips-linux-${WRANGLER_SHARP_ARCH}" && \
    node -e 'const pkg=require(process.argv[1]); if(pkg.version!==process.argv[2] || pkg.optionalDependencies[process.argv[3]]!==process.argv[4]) process.exit(1)' \
      "$WRANGLER_SHARP_NATIVE_DIR/package.json" "${WRANGLER_SHARP_VERSION}" \
      "$WRANGLER_SHARP_LIBVIPS_PACKAGE" "${WRANGLER_SHARP_LIBVIPS_VERSION}" && \
    test "$(node -p 'require(process.argv[1]).version' "$WRANGLER_SHARP_LIBVIPS_DIR/package.json")" = \
      "${WRANGLER_SHARP_LIBVIPS_VERSION}" && \
    test "$(npm view "${WRANGLER_SHARP_NATIVE_PACKAGE}@${WRANGLER_SHARP_VERSION}" dist.integrity)" = \
      "$WRANGLER_SHARP_NATIVE_INTEGRITY" && \
    test "$(npm view "${WRANGLER_SHARP_LIBVIPS_PACKAGE}@${WRANGLER_SHARP_LIBVIPS_VERSION}" dist.integrity)" = \
      "$WRANGLER_SHARP_LIBVIPS_INTEGRITY" && \
    WRANGLER_SHARP_TARBALL=$(npm pack --silent --ignore-scripts --pack-destination /tmp \
      "sharp@${WRANGLER_SHARP_VERSION}") && \
    WRANGLER_SHARP_NATIVE_TARBALL=$(npm pack --silent --ignore-scripts --pack-destination /tmp \
      "${WRANGLER_SHARP_NATIVE_PACKAGE}@${WRANGLER_SHARP_VERSION}") && \
    WRANGLER_SHARP_LIBVIPS_TARBALL=$(npm pack --silent --ignore-scripts --pack-destination /tmp \
      "${WRANGLER_SHARP_LIBVIPS_PACKAGE}@${WRANGLER_SHARP_LIBVIPS_VERSION}") && \
    node -e 'const fs=require("fs"); const crypto=require("crypto"); const actual=`sha512-${crypto.createHash("sha512").update(fs.readFileSync(process.argv[1])).digest("base64")}`; if(actual!==process.argv[2]) process.exit(1)' \
      "/tmp/${WRANGLER_SHARP_TARBALL}" "$WRANGLER_SHARP_INTEGRITY" && \
    node -e 'const fs=require("fs"); const crypto=require("crypto"); const actual=`sha512-${crypto.createHash("sha512").update(fs.readFileSync(process.argv[1])).digest("base64")}`; if(actual!==process.argv[2]) process.exit(1)' \
      "/tmp/${WRANGLER_SHARP_NATIVE_TARBALL}" "$WRANGLER_SHARP_NATIVE_INTEGRITY" && \
    node -e 'const fs=require("fs"); const crypto=require("crypto"); const actual=`sha512-${crypto.createHash("sha512").update(fs.readFileSync(process.argv[1])).digest("base64")}`; if(actual!==process.argv[2]) process.exit(1)' \
      "/tmp/${WRANGLER_SHARP_LIBVIPS_TARBALL}" "$WRANGLER_SHARP_LIBVIPS_INTEGRITY" && \
    WRANGLER_SHARP_VERIFIED_DIR=/tmp/holycode-wrangler-sharp-verified && \
    WRANGLER_SHARP_NATIVE_VERIFIED_DIR=/tmp/holycode-wrangler-sharp-native-verified && \
    WRANGLER_SHARP_LIBVIPS_VERIFIED_DIR=/tmp/holycode-wrangler-sharp-libvips-verified && \
    mkdir "$WRANGLER_SHARP_VERIFIED_DIR" "$WRANGLER_SHARP_NATIVE_VERIFIED_DIR" \
      "$WRANGLER_SHARP_LIBVIPS_VERIFIED_DIR" && \
    tar -xzf "/tmp/${WRANGLER_SHARP_TARBALL}" -C "$WRANGLER_SHARP_VERIFIED_DIR" && \
    tar -xzf "/tmp/${WRANGLER_SHARP_NATIVE_TARBALL}" -C "$WRANGLER_SHARP_NATIVE_VERIFIED_DIR" && \
    tar -xzf "/tmp/${WRANGLER_SHARP_LIBVIPS_TARBALL}" -C "$WRANGLER_SHARP_LIBVIPS_VERIFIED_DIR" && \
    diff -qr --no-dereference "$WRANGLER_SHARP_VERIFIED_DIR/package" "$WRANGLER_SHARP_DIR" && \
    diff -qr --no-dereference "$WRANGLER_SHARP_NATIVE_VERIFIED_DIR/package" "$WRANGLER_SHARP_NATIVE_DIR" && \
    diff -qr --no-dereference "$WRANGLER_SHARP_LIBVIPS_VERIFIED_DIR/package" "$WRANGLER_SHARP_LIBVIPS_DIR" && \
    rm -rf "$WRANGLER_SHARP_VERIFIED_DIR" "$WRANGLER_SHARP_NATIVE_VERIFIED_DIR" \
      "$WRANGLER_SHARP_LIBVIPS_VERIFIED_DIR" && \
    rm "/tmp/${WRANGLER_SHARP_TARBALL}" "/tmp/${WRANGLER_SHARP_NATIVE_TARBALL}" \
      "/tmp/${WRANGLER_SHARP_LIBVIPS_TARBALL}" && \
    test "$(find /usr/local/lib/node_modules/wrangler -path '*/sharp/package.json' -type f | wc -l)" -eq 1 && \
    test "$(find /usr/local/lib/node_modules/wrangler -path "*/@img/sharp-linux-${WRANGLER_SHARP_ARCH}/package.json" -type f | wc -l)" -eq 1 && \
    test "$(find /usr/local/lib/node_modules/wrangler -path "*/@img/sharp-libvips-linux-${WRANGLER_SHARP_ARCH}/package.json" -type f | wc -l)" -eq 1 && \
    (cd /usr/local/lib/node_modules/wrangler && npm ls sharp --all >/dev/null) && \
    node -e 'const sharp=require(process.argv[1]); if(sharp.versions.sharp!==process.argv[2] || sharp.versions.heif!=="1.23.2") process.exit(1); sharp({create:{width:2,height:2,channels:4,background:{r:220,g:30,b:30,alpha:1}}}).avif().toBuffer().then(buffer=>sharp(buffer).raw().toBuffer({resolveWithObject:true})).then(({data,info})=>{if(info.width!==2 || info.height!==2 || info.channels!==4 || data.length!==16) process.exit(1)}).catch(error=>{console.error(error);process.exit(1)})' \
      "$WRANGLER_SHARP_DIR" "${WRANGLER_SHARP_VERSION}" && \
    ! command -v sharp && \
    rm -rf /root/.npm

# Package the supported Claude Auth plugin for network-free startup.
RUN test "$(npm view "opencode-claude-auth@${CLAUDE_AUTH_PLUGIN_VERSION}" dist.integrity)" = \
      "sha512-iEXMVh2J/l8ZlNiMNp7QmtGQtAwjXgaSgXvA2zZzJbUZEOBKvuoq9gKRtqSjYB3faDwOVwwiGAj+S2N/8sgolA==" && \
    CLAUDE_AUTH_TARBALL=$(npm pack --silent --pack-destination /tmp \
      "opencode-claude-auth@${CLAUDE_AUTH_PLUGIN_VERSION}") && \
    CLAUDE_AUTH_DIR=/usr/local/share/holycode/plugins/opencode-claude-auth && \
    mkdir -p "${CLAUDE_AUTH_DIR}" && \
    tar -xzf "/tmp/${CLAUDE_AUTH_TARBALL}" -C "${CLAUDE_AUTH_DIR}" --strip-components=1 && \
    rm "/tmp/${CLAUDE_AUTH_TARBALL}" && \
    test "$(node -p 'require(process.argv[1]).version' "${CLAUDE_AUTH_DIR}/package.json")" = \
      "${CLAUDE_AUTH_PLUGIN_VERSION}" && \
    rm -rf /root/.npm
# npm 12 blocks dependency lifecycle scripts unless they are explicitly reviewed.
# NOTE: npm lifecycle-script policy validation is disabled for now to keep the
# build moving; the OpenCode and Claude postinstall scripts below still run.
COPY config/npm-global-script-policy.json /usr/local/share/holycode/npm-global-script-policy.json
RUN (cd /usr/local/lib/node_modules/@opencode/cli && node ./postinstall.mjs) && \
    (cd /usr/local/lib/node_modules/@anthropic-ai/claude-code && node install.cjs) && \
    # OpenCode v2 prints "opencode v<version>"; match the version substring.
    opencode --version | grep -F "${OPENCODE_VERSION}" && \
    claude --version | grep -F "${CLAUDE_CODE_VERSION}" && \
    esbuild --version | grep -Fx "0.28.2" && \
    prisma --version >/dev/null && \
    wrangler --version | grep -F "${WRANGLER_VERSION}" && \
    ! command -v vercel && ! command -v sharp && ! command -v concurrently && \
    ! command -v lhci && ! command -v netlify && ! command -v serve && \
    WORKERD_BIN=$(find /usr/local/lib/node_modules/wrangler -path '*/workerd/bin/workerd' -type f -print -quit) && \
    test -n "${WORKERD_BIN}" && "${WORKERD_BIN}" --version >/dev/null && \
    rm -rf /root/.npm

RUN mkdir -p /usr/local/share/holycode/python-seed && \
    python3 -m pip download --no-deps --only-binary=:all: \
      --dest /usr/local/share/holycode/python-seed \
      --require-hashes -r /usr/local/share/holycode/python-seed-requirements.lock

RUN mkdir -p /usr/local/share/holycode && \
    rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' | sort > /usr/local/share/holycode/pkg-inventory.txt

# ---------- Copy config files ----------
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/bootstrap.sh /usr/local/bin/bootstrap.sh
COPY config/opencode.json /usr/local/share/holycode/opencode.json
COPY THIRD-PARTY-NOTICES /usr/local/share/holycode/THIRD-PARTY-NOTICES
RUN install -d -m 0755 /usr/local/share/holycode/skills \
    && chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/bootstrap.sh

# ---------- s6-overlay service: opencode web ----------
COPY s6-overlay/s6-rc.d/opencode/type /etc/s6-overlay/s6-rc.d/opencode/type
COPY s6-overlay/s6-rc.d/opencode/run /etc/s6-overlay/s6-rc.d/opencode/run
RUN chmod +x /etc/s6-overlay/s6-rc.d/opencode/run && \
    touch /etc/s6-overlay/user-bundles.d/user/contents.d/opencode

# ---------- s6-overlay service: xvfb ----------
COPY s6-overlay/s6-rc.d/xvfb/type /etc/s6-overlay/s6-rc.d/xvfb/type
COPY s6-overlay/s6-rc.d/xvfb/run /etc/s6-overlay/s6-rc.d/xvfb/run
RUN chmod +x /etc/s6-overlay/s6-rc.d/xvfb/run && \
    touch /etc/s6-overlay/user-bundles.d/user/contents.d/xvfb


# ---------- Working directory ----------
WORKDIR /home/agent1/Code
RUN chown agent1:agent1 /home/agent1/Code

# ---------- Expose web UI port ----------
EXPOSE 4096

# ---------- Health check ----------
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -sf http://localhost:4096/ || exit 1

# ---------- s6-overlay as PID 1 ----------
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
