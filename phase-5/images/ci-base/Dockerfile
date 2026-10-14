# ci-base — job image for `runs-on: ci` (README §4 step 5). Build on a trusted machine, push to the forge registry,
# pin the digest in site.env (CI_IMAGE). Rebuild monthly (L5).
#   ./build-images.sh <registry-host>/<org> <tag> [extra-ca.crt]
# Contents: Debian + Node 24 (JS actions run `node` INSIDE the job image) + git + Go + task + gitleaks + actionlint
# + docker CLI/buildx (jobs reach the lane's own dind via DOCKER_HOST). Language toolchains are per-stack: this
# one carries Go for the verification app; add pnpm/uv/etc. for your stacks.
ARG NODE_IMAGE=node:24-bookworm-slim
ARG GO_IMAGE=golang:1.27-bookworm
ARG DOCKER_CLI_IMAGE=docker:29-cli
FROM ${GO_IMAGE} AS go
FROM ${DOCKER_CLI_IMAGE} AS dockercli
FROM ${NODE_IMAGE}
ARG TASK_VERSION=3.54.0
ARG GITLEAKS_VERSION=8.30.1
ARG ACTIONLINT_VERSION=1.7.12
RUN apt-get update -q && apt-get install -y -q --no-install-recommends ca-certificates curl git jq zstd openssh-client \
 && rm -rf /var/lib/apt/lists/*
COPY --from=go /usr/local/go /usr/local/go
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx
ENV PATH=/usr/local/go/bin:/root/go/bin:$PATH GOTOOLCHAIN=local
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# release tarballs verified against the projects' published checksum files
RUN set -e; cd /tmp; \
    curl -fsSLO "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_amd64.tar.gz"; \
    curl -fsSL "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_checksums.txt" | grep ' task_linux_amd64.tar.gz$' | sha256sum -c -; \
    tar -xzf task_linux_amd64.tar.gz -C /usr/local/bin task; \
    f="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"; curl -fsSLO "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/$f"; \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt" | grep " $f\$" | sha256sum -c -; \
    tar -xzf "$f" -C /usr/local/bin gitleaks; \
    f="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"; curl -fsSLO "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/$f"; \
    curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_checksums.txt" | grep " $f\$" | sha256sum -c -; \
    tar -xzf "$f" -C /usr/local/bin actionlint; rm -f /tmp/*.tar.gz
# private CA (Caddy `tls internal`, README §4 step 2c): drop *.crt into ./ca/ before building (may be empty)
COPY ca/ /usr/local/share/ca-certificates/extra/
RUN update-ca-certificates
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
RUN node --version && go version && task --version && gitleaks version && actionlint --version | head -1 && docker --version
