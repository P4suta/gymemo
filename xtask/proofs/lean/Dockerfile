# The offline host of the Lean proofs, which `just proofs` runs without a network.
ARG LEAN_VERSION=4.34.1

# The release names its x86-64 archive `linux` and its arm64 archive `linux_aarch64`.
FROM scratch AS archive-amd64
ARG LEAN_VERSION
ADD --checksum=sha256:47bf4bbd78f70c2e9670598ab7124d92b6efb7330ff33e5fbb4030f6fd72e4e4 https://github.com/leanprover/lean4/releases/download/v${LEAN_VERSION}/lean-${LEAN_VERSION}-linux.tar.zst /lean.tar.zst

FROM scratch AS archive-arm64
ARG LEAN_VERSION
ADD --checksum=sha256:fdb974c2cdb4627e090d5d4007b913e09d13c4868720fb5594e22808b3de9e37 https://github.com/leanprover/lean4/releases/download/v${LEAN_VERSION}/lean-${LEAN_VERSION}-linux_aarch64.tar.zst /lean.tar.zst

FROM docker.io/library/debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587 AS unpacked
ARG TARGETARCH
RUN apt-get update \
  && apt-get install --yes --no-install-recommends zstd=1.5.4+dfsg2-5 \
  && rm -rf /var/lib/apt/lists/*
RUN --mount=type=bind,from=archive-amd64,source=/lean.tar.zst,target=/tmp/lean-amd64.tar.zst \
  --mount=type=bind,from=archive-arm64,source=/lean.tar.zst,target=/tmp/lean-arm64.tar.zst \
  mkdir -p /opt/lean \
  && tar --zstd -xf /tmp/lean-${TARGETARCH}.tar.zst -C /opt/lean --strip-components=1

FROM docker.io/library/debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
COPY --from=unpacked /opt/lean /opt/lean
ENV PATH=/opt/lean/bin:$PATH
RUN lean --version
