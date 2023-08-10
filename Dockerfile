# Set the base image
FROM ubuntu:20.04

# Avoid warnings by switching to noninteractive
ENV DEBIAN_FRONTEND=noninteractive
ARG DATABASE_URL=mongodb://localhost:27017

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
    build-essential \
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
RUN if [ "$DATABASE_URL" = "mongodb://localhost:27017" ] ; then \
    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add - && \
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list && \
    apt-get update && apt-get install -y mongodb-org && \
    mkdir -p /data/db ; \
    fi


# Install yarn
RUN /bin/bash -c "npm install -g yarn"

# Install sprucebot
RUN /bin/bash -c "yarn global add @sprucelabs/spruce-cli"

#Copy ober build script
COPY skills.txt /skills.txt
COPY build.sh /build.sh
RUN chmod +x /build.sh

# Copy secrets, pull private repos, delete secrets
RUN --mount=type=secret,id=github_credentials \
    GITHUB_USERNAME=$(awk -F ':' '{print $1}' /run/secrets/github_credentials) && \
    GITHUB_TOKEN=$(awk -F ':' '{print $2}' /run/secrets/github_credentials) && \
    echo "machine github.com login $GITHUB_USERNAME password $GITHUB_TOKEN" > ~/.netrc && \
    git config --global url."https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/" && \
    /bin/bash -c "/build.sh --databaseUrl=$DATABASE_URL" && \
    rm ~/.netrc && \
    cd ..

# Copy over run script
COPY run.sh /run.sh
RUN chmod +x /run.sh

# Run mongod and sprucebot at runtime
ENTRYPOINT ["/bin/bash", "-c", "mongod > /dev/null 2>&1 & /run.sh"]