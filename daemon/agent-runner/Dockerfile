# Build stage — compile the static agent-runner binary
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /agent-runner .

# Runtime stage — node:22-bookworm-slim provides npm for claude CLI
FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install the Anthropic Claude Code CLI; tolerate failures if the package name
# changes in future npm releases (the binary path can be overridden at runtime).
# Global install requires root — run before dropping privileges.
RUN npm install -g @anthropic-ai/claude-code 2>/dev/null || true

COPY --from=build /agent-runner /usr/local/bin/agent-runner

# Drop to an unprivileged user. The agent binary and npm-installed CLIs under
# /usr/local are world-executable so no ownership change is needed there.
RUN groupadd -r lancer && useradd -r -g lancer -m lancer
USER lancer

ENTRYPOINT ["/usr/local/bin/agent-runner"]
