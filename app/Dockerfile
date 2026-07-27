# TaleLah Flutter web — Railway service (root directory = app/).
# Stage 1: build the web bundle
FROM ghcr.io/cirruslabs/flutter:3.35.1 AS build

WORKDIR /src
COPY . .

# Railway passes service variables as build args when declared here.
# Set API_BASE_URL on the Railway web service once the backend URL is known.
ARG API_BASE_URL=http://localhost:8000/api/v1
RUN flutter pub get && \
    flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

# Stage 2: serve static files with Caddy
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /src/build/web /srv
