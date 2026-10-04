# ==========================================
# Stage 1: Build Ruby gems with native C extensions
# ==========================================
FROM ruby:3.3-slim AS gem-builder

# Install build tools only for compiling gems (discarded in final image)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock* ./
RUN bundle config set --local without 'development test' \
    && bundle install \
    && rm -rf /usr/local/bundle/cache/*.gem \
    && find /usr/local/bundle/gems/ -name "*.c" -delete \
    && find /usr/local/bundle/gems/ -name "*.o" -delete

# ==========================================
# Stage 2: Minimal runtime image
# ==========================================
FROM ruby:3.3-slim

# Install Chromium and Node.js 22 LTS (for Puppeteer / Grover PDF rendering)
# Purge curl after adding NodeSource repository to keep layers minimal
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    chromium \
    fonts-liberation \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get purge -y --auto-remove curl \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# Install Puppeteer without bundled Chromium, then strip npm cache
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV NODE_PATH=/usr/lib/node_modules

RUN npm install -g --omit=dev --no-audit --no-fund puppeteer \
    && npm cache clean --force \
    && rm -rf /root/.npm /root/.cache

WORKDIR /app

# Copy pre-compiled gems from builder stage
COPY --from=gem-builder /usr/local/bundle /usr/local/bundle

# Copy application code (respecting .dockerignore)
COPY . .

# Ensure tmp directory exists
RUN mkdir -p tmp

# Grover configuration for headless Chromium
ENV GROVER_NO_SANDBOX=true
ENV PORT=10000

EXPOSE 10000

CMD ["sh", "-c", "bundle exec puma config.ru -b tcp://0.0.0.0:${PORT:-10000} -e production"]

