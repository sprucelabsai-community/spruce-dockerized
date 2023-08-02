# Set the base image
FROM ubuntu:20.04

# Avoid warnings by switching to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# Input security credentials
ARG GITHUB_ID
ARG GITHUB_TOKEN

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
RUN wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add - && \
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list && \
    apt-get update && apt-get install -y mongodb-org && \
    mkdir -p /data/db

# Install yarn
RUN /bin/bash -c "npm install -g yarn"

# Install sprucebot
RUN /bin/bash -c "yarn global add @sprucelabs/spruce-cli"

# Set up credentials to git clone private repos
RUN --mount=type=secret,id=TOKEN \
    echo "machine github.com login x password $(head -n 1 /run/secrets/TOKEN)" > ~/.netrc && \
git config \
    --global \
    url."https://${GITHUB_ID}:${GITHUB_TOKEN}@github.com/".insteadOf \
    "https://github.com/"

# Build spruce skills
COPY build-spruce-skills.sh /build-spruce-skills.sh
RUN chmod +x /build-spruce-skills.sh && bin/bash /build-spruce-skills.sh

# Copy over run script
RUN cd ..
COPY run.sh /run.sh

# Run mongod and sprucebot at runtime
RUN chmod +x /run.sh
ENTRYPOINT ["/bin/bash", "-c", "mongod > /dev/null 2>&1 & /run.sh"]