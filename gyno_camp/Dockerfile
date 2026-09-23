# ==============================================================================
# GynoCamp Central Cloud Synchronization Server
# Multi-Stage Production Dockerfile
# ==============================================================================

# Stage 1: Compile native server executable
FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart compile exe bin/server.dart -o bin/gynocamp_server

# Stage 2: Ultra-lightweight deployment image
FROM debian:bookworm-slim

# Install SSL certificates for outbound HTTPS calls if needed
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/bin/gynocamp_server /app/bin/gynocamp_server

EXPOSE 8080
ENV PORT=8080

CMD ["/app/bin/gynocamp_server"]
