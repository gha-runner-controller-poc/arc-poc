# --------------------------------------------
# Stage 1: Unified tool installations
# --------------------------------------------
FROM debian:bullseye-slim as tools

ARG TERRAFORM_VERSION=1.8.0
ARG VAULT_CLI_VERSION=1.19.1
ARG NODE_VERSION=20.11.1

# Install base dependencies
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
RUN mkdir -p /node \
    && curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz -o node.tar.xz \
    && tar -xJf node.tar.xz --strip-components=1 -C /node \
    && rm node.tar.xz \
    && rm -rf /node/{CHANGELOG.md,README.md,LICENSE,.npm,include,share/doc}

# --------------------------------------------
# Stage 2: Runner build
# --------------------------------------------
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy AS build

ARG RUNNER_VERSION=2.323.0
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.7.0

# Install build dependencies
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
# Final Stage: Optimized runtime
# --------------------------------------------
FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1 \
    PATH="/node/bin:${PATH}"

# Install essential runtime dependencies
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
        /var/lib/apt/lists/* \
        /usr/share/doc/* \
        /usr/share/man/* \
        /tmp/*

# Create non-root user
RUN adduser --disabled-password --gecos "" --uid 1001 runner && \
    usermod -aG sudo runner && \
    echo "%sudo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner && \
    chmod 0440 /etc/sudoers.d/runner

# Copy only necessary artifacts
COPY --from=tools /terraform-bin/terraform /usr/local/bin/
COPY --from=tools /vault-bin/vault /usr/local/bin/
COPY --from=tools /node/bin/node /usr/local/bin/
COPY --from=tools /node/lib/node_modules/ /usr/local/lib/node_modules/
COPY --chown=runner:runner --from=build /actions-runner /home/runner

# Create symlinks for npm/npx
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

WORKDIR /home/runner
USER runner

# Verify installations
RUN terraform --version && vault --version && node --version
