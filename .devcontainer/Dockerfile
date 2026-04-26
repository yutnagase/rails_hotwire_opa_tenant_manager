FROM ruby:3.4

# PostgreSQLクライアント + ビルドに必要なパッケージ
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      postgresql-client \
      libpq-dev \
      git \
      curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
