FROM ruby:3.3.5-slim

# Alpine is deliberately avoided: Gemfile.lock pins tailwindcss-ruby to a
# x86_64-linux-gnu build, which does not run against musl.

ARG UID=1000
ARG GID=1000

RUN apt-get update -qq \
    && apt-get install --no-install-recommends -y \
       build-essential \
       libpq-dev \
       postgresql-client \
       git \
    && rm -rf /var/lib/apt/lists/*

# Matching the host UID keeps files generated inside the container editable
# from the working copy on Linux, where bind mounts do not remap ownership.
RUN groupadd -g ${GID} app \
    && useradd -u ${UID} -g ${GID} -m app

# Gems live outside /app so the source bind mount cannot shadow them.
# RAILS_ENV is deliberately left unset: Rails defaults to development, and
# spec/rails_helper.rb only falls back to the test environment when the
# variable is absent.
ENV BUNDLE_PATH=/gems \
    BUNDLE_APP_CONFIG=/gems/.bundle

RUN mkdir -p /gems /app && chown ${UID}:${GID} /gems /app

USER app
WORKDIR /app

# Copied on their own so the bundle layer stays cached across source edits.
COPY --chown=${UID}:${GID} Gemfile Gemfile.lock ./
RUN bundle install

COPY --chown=${UID}:${GID} docker/entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
