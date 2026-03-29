# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# ==============================================================================
# Base Image — KERNEL_FLAVOR: "bazzite" (default) | "cachyos"
# ==============================================================================
ARG KERNEL_FLAVOR=bazzite

FROM ghcr.io/ublue-os/bazzite:stable

ARG KERNEL_FLAVOR=bazzite
ENV KERNEL_FLAVOR=${KERNEL_FLAVOR}

### MODIFICATIONS
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
RUN bootc container lint
