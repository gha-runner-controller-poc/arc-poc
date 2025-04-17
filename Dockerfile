# --------------------------------------------
# Stage 1: Install Terraform
# --------------------------------------------
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy AS terraform-install
ARG TERRAFORM_VERSION=1.8.0
RUN apt update && apt install -y --no-install-recommends curl unzip ca-certificates \
    && curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip \
    && unzip terraform.zip -d /terraform-bin \
    && rm -rf terraform.zip /var/lib/apt/lists/*

# --------------------------------------------
# Stage 2: Install Vault CLI
# --------------------------------------------
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy AS vault-install
ARG VAULT_CLI_VERSION=1.19.1
RUN apt update && apt install -y --no-install-recommends curl unzip ca-certificates \
    && curl -fsSL https://releases.hashicorp.com/vault/${VAULT_CLI_VERSION}/vault_${VAULT_CLI_VERSION}_linux_amd64.zip -o vault.zip \
    && unzip vault.zip -d /vault-bin \
    && rm -rf vault.zip /var/lib/apt/lists/*

# --------------------------------------------
# Stage 3: Install Node.js
# --------------------------------------------
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy AS node-install
ARG NODE_MAJOR=23
RUN apt update && apt install -y --no-install-recommends curl ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt update && apt install -y --no-install-recommends nodejs \
    && mkdir -p /node-bin && cp /usr/bin/node /usr/bin/npm /node-bin/ \
    && rm -rf /var/lib/apt/lists/*

# --------------------------------------------
# Stage 4: Build GitHub Actions Runner
# --------------------------------------------
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy AS build
ARG TARGETOS="linux"
ARG TARGETARCH="amd64"
ARG RUNNER_VERSION=2.323.0
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.7.0

RUN apt update && apt install -y --no-install-recommends curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /actions-runner
RUN export RUNNER_ARCH=${TARGETARCH} \
    && [ "$RUNNER_ARCH" = "amd64" ] && RUNNER_ARCH=x64 || true \
    && curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${TARGETOS}-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf runner.tar.gz && rm runner.tar.gz

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

# --------------------------------------------
# Final Stage: Runtime Image
# --------------------------------------------
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ENV ImageOS=ubuntu22

# Install minimal runtime dependencies
RUN apt update && apt install -y --no-install-recommends \
    sudo curl jq unzip git wget gettext gpg ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add non-root user
RUN adduser --disabled-password --gecos "" --uid 1001 runner \
    && usermod -aG sudo runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
    && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers

# Copy tool binaries
COPY --from=terraform-install /terraform-bin/terraform /usr/local/bin/
COPY --from=vault-install /vault-bin/vault /usr/local/bin/
COPY --from=node-install /node-bin/node /usr/local/bin/
COPY --from=node-install /node-bin/npm /usr/local/bin/

# Copy GitHub Actions runner files
WORKDIR /home/runner
COPY --chown=runner:runner --from=build /actions-runner .

USER runner
