# Use ubuntu image as a base
FROM ubuntu:24.04 AS base
ARG RUBY_VER=3.1.5
ARG BUNDLER_VER=2.4.18
ARG NVM_VER=0.38.0
ARG NODE_VER=18.20.4
ARG RVM_KEY1_SERVER=https://rvm.io/mpapis.asc
ARG RVM_KEY2_SERVER=https://rvm.io/pkuczynski.asc

# set environment variables
ENV RUBY_VER=$RUBY_VER \
    RAILS_ENV=$RAILS_ENV \
    NODE_VER=$NODE_VER \
    RVM_KEY1_SERVER=$RVM_KEY1_SERVER \
    RVM_KEY2_SERVER=$RVM_KEY2_SERVER \
    GEM_PATH=/usr/local/rvm/gems/ruby-$RUBY_VER:/usr/local/rvm/gems/ruby-$RUBY_VER@global \
    PATH=/home/new-user/.nvm/versions/node/v$NODE_VER/bin:/usr/local/rvm/gems/ruby-$RUBY_VER/bin:/usr/local/rvm/gems/ruby-$RUBY_VER@global/bin:$PATH

# Install dependencies
RUN apt-get -y update \
    && apt-get install -y git file which curl libaio-dev gpg curl patch autoconf automake bison bzip2 g++ libffi-dev libtool make patch libreadline-dev sqlite3 libsqlite3-dev zlib1g-dev libc6-dev libcurl4-openssl-dev libssl-dev libnsl-dev tzdata software-properties-common zip unzip libpcre3-dev libyaml-dev 

# Name a new build stage
FROM base AS ror

# Add the app user
RUN useradd -m -s /bin/bash new-user \
    && mkdir -p /app \
    && chown -R new-user:new-user /app

# Install rvm
RUN curl -sSL $RVM_KEY1_SERVER | gpg --import - \
    && curl -sSL $RVM_KEY2_SERVER | gpg --import - \
    && curl -L get.rvm.io | bash -s stable --auto 

# rvm require a restart of bash session
SHELL [ "/bin/bash", "-l", "-c" ]

# Install ruby and bundler
RUN . /etc/profile.d/rvm.sh \
     && rvm install --autolibs=read-only $RUBY_VER \
     && rvm --default use  $RUBY_VER \
     && gem install bundler:$BUNDLER_VER \
     && usermod -a -G rvm new-user \
     && chown -R new-user:new-user /usr/local/rvm

# Switch to app user to install nvm and node
USER new-user
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VER/install.sh | bash \
    && source $HOME/.nvm/nvm.sh \
    && nvm install $NODE_VER

# name a new build stage
FROM ror AS app
WORKDIR /app
# copy all files to the target path and change the ownership and read/write permissions
COPY --chown=new-user:new-user --chmod=755 . .

# bundle install gems
RUN git config --global --add safe.directory /app \
    && bundle lock --add-platform aarch64-linux \    
    && bundle config set frozen 'true' \
    && bundle config set path "${HOME}/bundler" \
    && bundle config build.nokogiri --use-system-libraries \
    && bundle package \
    && bundle install --local

# precompile assets for production
RUN bundle exec rails assets:precompile

# expose the port that the app runs on
EXPOSE 3000

# add a script to be executed every time the container starts
ENTRYPOINT ["/bin/bash"]
CMD ["/app/entrypoint_app.sh"]

# name a new build stage
FROM base AS solr
ARG SOLR_VER=9.6.1
ENV SOLR_VER=$SOLR_VER

# create solr-user
RUN useradd -m -s /bin/bash solr-user \
    && mkdir -p /solr \
    && chown -R solr-user:solr-user /solr

# Install Java
RUN apt install -y default-jre
WORKDIR /solr

# switch user and install solr
USER solr-user
RUN curl -L -O https://www.apache.org/dyn/closer.lua/solr/solr/$SOLR_VER/solr-$SOLR_VER.tgz?action=download
RUN tar zxf solr-$SOLR_VER.tgz -C /solr \
    && cp -R ./solr-$SOLR_VER/. ./ \
    && rm solr-$SOLR_VER.tgz

# copy solr config file to target path
COPY --chown=solr-user:solr-user --chmod=755 .  . 

# expose the port that the solr runs on
EXPOSE 8983

# add a script to be executed every time the container starts
ENTRYPOINT ["/bin/bash"]
CMD ["/solr/entrypoint_solr.sh"]


FROM eclipse-temurin:17-jre-jammy AS my-solr

ARG SOLR_VERSION="9.6.1"
ARG SOLR_DIST="-slim"
ARG SOLR_SHA512="78e6558551c7710134f2519e5f86a32c636e5963f8efadc8c0391dfb99f7554b3d86197272aa92fa7b28589602d87389530eea043dd3d299983a1c49e38f0dc3"
ARG SOLR_KEYS="50E3EE1C91C7E0CB4DFB007B369424FC98F3F6EC"

ARG SOLR_DOWNLOAD_SERVER="https://www.apache.org/dyn/closer.lua?action=download&filename=/solr/solr"

RUN set -ex; \
  apt-get update; \
  apt-get -y --no-install-recommends install wget gpg gnupg dirmngr; \
  rm -rf /var/lib/apt/lists/*; \
  export SOLR_BINARY="solr-$SOLR_VERSION$SOLR_DIST.tgz"; \
  MAX_REDIRECTS=3; \
  case "${SOLR_DOWNLOAD_SERVER}" in \
    (*"apache.org"*);; \
    (*) \
      # If a non-ASF URL is provided, allow more redirects and skip GPG step.
      MAX_REDIRECTS=4 && \
      SKIP_GPG_CHECK=true;; \
  esac; \
  export DOWNLOAD_URL="$SOLR_DOWNLOAD_SERVER/$SOLR_VERSION/$SOLR_BINARY"; \
  echo "downloading $DOWNLOAD_URL"; \
  if ! wget -t 10 --max-redirect $MAX_REDIRECTS --retry-connrefused -nv "$DOWNLOAD_URL" -O "/opt/$SOLR_BINARY"; then rm -f "/opt/$SOLR_BINARY"; fi; \
  if [ ! -f "/opt/$SOLR_BINARY" ]; then echo "failed download attempt for $SOLR_BINARY"; exit 1; fi; \
  echo "$SOLR_SHA512 */opt/$SOLR_BINARY" | sha512sum -c -; \
  tar -C /opt --extract --preserve-permissions --file "/opt/$SOLR_BINARY"; \
  rm "/opt/$SOLR_BINARY"*; \
  apt-get -y remove gpg dirmngr && apt-get -y autoremove;



LABEL org.opencontainers.image.title="Apache Solr"
LABEL org.opencontainers.image.description="Apache Solr is the popular, blazing-fast, open source search platform built on Apache Lucene."
LABEL org.opencontainers.image.authors="The Apache Solr Project"
LABEL org.opencontainers.image.url="https://solr.apache.org"
LABEL org.opencontainers.image.source="https://github.com/apache/solr"
LABEL org.opencontainers.image.documentation="https://solr.apache.org/guide/"
LABEL org.opencontainers.image.version="${SOLR_VERSION}"
LABEL org.opencontainers.image.licenses="Apache-2.0"

ENV SOLR_USER="solr" \
    SOLR_UID="8983" \
    SOLR_GROUP="solr" \
    SOLR_GID="8983" \
    PATH="/opt/solr/bin:/opt/solr/docker/scripts:/opt/solr/prometheus-exporter/bin:$PATH" \
    SOLR_INCLUDE=/etc/default/solr.in.sh \
    SOLR_HOME=/var/solr/data \
    SOLR_PID_DIR=/var/solr \
    SOLR_LOGS_DIR=/var/solr/logs \
    LOG4J_PROPS=/var/solr/log4j2.xml \
    SOLR_JETTY_HOST="0.0.0.0" \
    SOLR_ZK_EMBEDDED_HOST="0.0.0.0"

RUN set -ex; \
  groupadd -r --gid "$SOLR_GID" "$SOLR_GROUP"; \
  useradd -r --uid "$SOLR_UID" --gid "$SOLR_GID" "$SOLR_USER"

RUN set -ex; \
  (cd /opt; ln -s solr-*/ solr); \
  rm -Rf /opt/solr/docs /opt/solr/docker/Dockerfile;

RUN set -ex; \
  mkdir -p /opt/solr/server/solr/lib /docker-entrypoint-initdb.d; \
  cp /opt/solr/bin/solr.in.sh /etc/default/solr.in.sh; \
  mv /opt/solr/bin/solr.in.sh /opt/solr/bin/solr.in.sh.orig; \
  mv /opt/solr/bin/solr.in.cmd /opt/solr/bin/solr.in.cmd.orig; \
  chmod 0664 /etc/default/solr.in.sh; \
  mkdir -p -m0770 /var/solr; \
  chown -R "$SOLR_USER:0" /var/solr; \
  test ! -e /opt/solr/modules || ln -s /opt/solr/modules /opt/solr/contrib; \
  test ! -e /opt/solr/prometheus-exporter || ln -s /opt/solr/prometheus-exporter /opt/solr/modules/prometheus-exporter;

RUN set -ex; \
    apt-get update; \
    apt-get -y --no-install-recommends install acl lsof procps wget netcat gosu tini jattach; \
    rm -rf /var/lib/apt/lists/*;

VOLUME /var/solr
EXPOSE 8983
WORKDIR /opt/solr
USER $SOLR_UID

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["solr-foreground"]
