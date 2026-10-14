# deploy-base — job image for `runs-on: deploy` (README §4 step 5): docker CLI/buildx + Kamal 2 + ssh + jq + git
# + Node 24 (for JS actions such as actions/checkout, which run INSIDE the job image). Pin the digest as DEPLOY_IMAGE.
ARG RUBY_IMAGE=ruby:3.4-slim-bookworm
ARG NODE_IMAGE=node:24-bookworm-slim
ARG DOCKER_CLI_IMAGE=docker:29-cli
FROM ${NODE_IMAGE} AS node
FROM ${DOCKER_CLI_IMAGE} AS dockercli
FROM ${RUBY_IMAGE}
ARG KAMAL_VERSION=2.12.0
RUN apt-get update -q && apt-get install -y -q --no-install-recommends ca-certificates curl git jq openssh-client build-essential \
 && gem install --no-document kamal -v "${KAMAL_VERSION}" \
 && apt-get purge -y build-essential && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx
COPY ca/ /usr/local/share/ca-certificates/extra/
RUN update-ca-certificates
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
RUN node --version && kamal version && docker --version && ssh -V
