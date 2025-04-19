# --------------------------------------------
# Stage 1: Tool installations (Debian Slim)
# --------------------------------------------
FROM debian:bullseye-slim as tools

ARG TERRAFORM_VERSION=1.8.0
ARG VAULT_CLI_VERSION=1.19.1
ARG NODE_VERSION=20.11.1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip \
    && unzip -j terraform.zip -d /terraform-bin \
    && rm terraform.zip

# Install Vault
RUN curl -fsSL https://releases.hashicorp.com/vault/${VAULT_CLI_VERSION}/vault_${VAULT_CLI_VERSION}_linux_amd64.zip -o vault.zip \
    && unzip -j vault.zip -d /vault-bin \
    && rm vault.zip

# Install Node.js (minimal)
RUN curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz | \
    tar -xJ -C /node --strip-components=1 --exclude='CHANGELOG.md' --exclude='LICENSE' --exclude='README.md'

# --------------------------------------------
# Stage 2: Runner Build
# --------------------------------------------
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy AS build

ARG RUNNER_VERSION=2.323.0
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.7.0

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /actions-runner
RUN curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf runner.tar.gz && rm runner.tar.gz

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

# --------------------------------------------
# Final Stage: Optimized Production Runtime
# --------------------------------------------
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy

HEALTHCHECK --interval=30s --timeout=10s --start-period=1m --retries=3 \
    CMD ps aux | grep -q '[r]unner' || exit 1

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1 \
    ImageOS=ubuntu22 \
    PATH="/node/bin:${PATH}"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    sudo \
    git \
    jq \
    ca-certificates \
    gettext \
    wget \
    gpg \
    && apt-get clean \
    && rm -rf \
        /usr/share/doc/* \
        /usr/share/man/* \
        /var/lib/apt/lists/* \
        /tmp/*

RUN adduser --disabled-password --gecos "" --uid 1001 runner && \
    usermod -aG sudo runner && \
    echo "%sudo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner && \
    chmod 0440 /etc/sudoers.d/runner

COPY --from=tools /terraform-bin/* /usr/local/bin/
COPY --from=tools /vault-bin/* /usr/local/bin/
COPY --from=tools /node /node
COPY --chown=runner:runner --from=build /actions-runner /home/runner

WORKDIR /home/runner
USER runner
