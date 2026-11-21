# The host of the mutation run over `xtask` and of the bounded checks of its scanners.
ARG KANI_VERSION=0.68.0
ARG NEXTEST_VERSION=0.9.152

FROM scratch AS bundle-amd64
ARG KANI_VERSION
ARG NEXTEST_VERSION
ADD --checksum=sha256:32e2b484d73ede0bbf64a2cf0879c4259422497d8aec4ee67d448de9ae7843d3 https://github.com/model-checking/kani/releases/download/kani-${KANI_VERSION}/kani-${KANI_VERSION}-x86_64-unknown-linux-gnu.tar.gz /kani.tar.gz
ADD --checksum=sha256:d039b43c3e0958441b6ad0a39c8884d018b3d2e8fb9928f209074b1100b5e17a https://github.com/nextest-rs/nextest/releases/download/cargo-nextest-${NEXTEST_VERSION}/cargo-nextest-${NEXTEST_VERSION}-x86_64-unknown-linux-gnu.tar.gz /nextest.tar.gz

FROM scratch AS bundle-arm64
ARG KANI_VERSION
ARG NEXTEST_VERSION
ADD --checksum=sha256:0042d2688bf1550270def4a79c96aaeea138631818cb4ab5480120f2d51a942c https://github.com/model-checking/kani/releases/download/kani-${KANI_VERSION}/kani-${KANI_VERSION}-aarch64-unknown-linux-gnu.tar.gz /kani.tar.gz
ADD --checksum=sha256:ca1f81a5b86533eb45ab97e0064aa88e925e53aab9a698ca6331a7cad1f85f07 https://github.com/nextest-rs/nextest/releases/download/cargo-nextest-${NEXTEST_VERSION}/cargo-nextest-${NEXTEST_VERSION}-aarch64-unknown-linux-gnu.tar.gz /nextest.tar.gz

# Kani's bundle needs glibc 2.39, so the base is Debian trixie.
FROM docker.io/library/rust:1.99.1-slim-trixie@sha256:d5928c68f8909c141df1bef47ac2c99c025fc9480d09870e08c3783b270eedec
ARG KANI_VERSION
ARG TARGETARCH
RUN cargo install --locked kani-verifier@${KANI_VERSION} cargo-mutants@27.1.0 \
  && rm -rf /usr/local/cargo/registry
RUN --mount=type=bind,from=bundle-amd64,source=/kani.tar.gz,target=/tmp/kani-amd64.tar.gz \
  --mount=type=bind,from=bundle-arm64,source=/kani.tar.gz,target=/tmp/kani-arm64.tar.gz \
  cargo kani setup --use-local-bundle /tmp/kani-${TARGETARCH}.tar.gz \
  && cargo kani --version \
  && cargo mutants --version
RUN --mount=type=bind,from=bundle-amd64,source=/nextest.tar.gz,target=/tmp/nextest-amd64.tar.gz \
  --mount=type=bind,from=bundle-arm64,source=/nextest.tar.gz,target=/tmp/nextest-arm64.tar.gz \
  tar -xzf /tmp/nextest-${TARGETARCH}.tar.gz -C /usr/local/cargo/bin cargo-nextest \
  && cargo nextest --version
