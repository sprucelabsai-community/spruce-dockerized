# Set the base image
FROM ubuntu:20.04

# Avoid warnings by switching to noninteractive
ENV DEBIAN_FRONTEND=noninteractive
ENV SHOULD_USE_SKILLS_CONFIG=false
ARG DB_CONNECTION_STRING=mongodb://localhost:27017
ARG DATABASE_NAME=default
ARG SKILLS=default
ARG SHOULD_SERVE_HEARTWOOD=true
ARG SKILLS_ENV_CONFIG_PATH

# Update the system and Install prerequisites
RUN apt-get update && apt-get install -y \
    apt-utils \
    curl \
    gnupg \
    git \
    wget \
    lsb-release \
    screen \
    rsync \
    locales \
    python3 \
    python3-pip \
    pkg-config \
    libpixman-1-dev \
    build-essential \
    libcairo2-dev \
    libjpeg-dev \
    libpango1.0-dev \
    libgif-dev \
    build-essential g++ \
    redis \
    jq \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Install NVM
ENV NVM_DIR /root/.nvm
ENV NODE_VERSION 18.17.0

# Install nvm with node and npm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default

# Add node and npm to path so the commands are available
ENV NODE_PATH $NVM_DIR/v$NODE_VERSION/lib/node_modules
ENV PATH $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

# Confirm installation
RUN /bin/bash -c "source $NVM_DIR/nvm.sh && node -v && npm -v"

# Install MongoDB
RUN if [ "$DB_CONNECTION_STRING" = "mongodb://localhost:27017" ] ; then \
    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add - && \
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list && \
    apt-get update && apt-get install -y mongodb-org && \
    mkdir -p /data/db ; \
    fi


# Install yarn
RUN /bin/bash -c "npm install -g yarn"

# Install sprucebot
RUN /bin/bash -c "yarn global add @sprucelabs/spruce-cli"

COPY skills.txt /skills.txt
RUN if [ "$SKILLS" != "default" ]; then \
    echo $SKILLS | sed 's/,/\n/g' > /skills.txt; \
    fi

COPY build.sh /build.sh
RUN chmod +x /build.sh

COPY run.sh /run.sh
RUN chmod +x /run.sh

# optionally copy SKILLS_ENV_CONFIG_PATH
COPY $SKILLS_ENV_CONFIG_PATH skills_config.json

# Copy secrets, pull private repos, delete secrets
RUN --mount=type=secret,id=github_credentials \
    GITHUB_USERNAME=$(awk -F ':' '{print $1}' /run/secrets/github_credentials) && \
    GITHUB_TOKEN=$(awk -F ':' '{print $2}' /run/secrets/github_credentials) && \
    echo "machine github.com login $GITHUB_USERNAME password $GITHUB_TOKEN" > ~/.netrc && \
    git config --global url."https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/" && \
    /bin/bash -c "/build.sh --databaseConnectionString=$DB_CONNECTION_STRING --databaseName=$DATABASE_NAME --shouldServeHeartwood=$SHOULD_SERVE_HEARTWOOD --skillsEnvConfigPath=skills_config.json" && \
    rm ~/.netrc && \
    cd ..

EXPOSE 8081
EXPOSE 8080

# Run mongod and sprucebot at runtime
ENTRYPOINT ["/bin/bash", "-c", "mongod > /dev/null 2>&1 & /run.sh"]

