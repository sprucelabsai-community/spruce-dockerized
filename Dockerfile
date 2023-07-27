# Set the base image
FROM ubuntu:20.04

ARG GITHUB_KEY
ARG PHONE_NUMBER

# Avoid warnings by switching to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# Update the system and Install prerequisites
RUN apt-get update && apt-get install -y \
    apt-utils \
    curl \
    gnupg \
    git \
    wget \
    lsb-release \
    locales \
    python3 \
    python3-pip \
    build-essential \
    && locale-gen en_US.UTF-8

# Install NVM
ENV NVM_DIR /root/.nvm
ENV NODE_VERSION lts/*

# Install nvm with node and npm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default

# Confirm installation
RUN /bin/bash -c "source $NVM_DIR/nvm.sh && node -v && npm -v"

# Install Docker
RUN curl -fsSL https://get.docker.com -o get-docker.sh && \
    sh get-docker.sh && \
    rm get-docker.sh

# Install MongoDB
RUN wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add - && \
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list && \
    apt-get update && apt-get install -y mongodb-org && \
    mkdir -p /data/db

# Install Node.js
# RUN curl -sL https://deb.nodesource.com/setup_18.x | bash - && \
#    apt-get install -y nodejs 


# Install Yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list

RUN apt-get update && apt-get install -y yarn

#Install sprucebot
RUN /bin/bash -c "yarn global add -g @sprucelabs/sprucebot-cli"

# Revert back to the regular user
ENV DEBIAN_FRONTEND=dialog

# This line create a new file and write the value of the SSH_PRIVATE_KEY argument to it
RUN mkdir ~/.ssh/ \
    && echo "${GITHUB_KEY}" > ~/.ssh/id_rsa \
    && chmod 600 ~/.ssh/id_rsa \
    && ssh-keyscan github.com >> ~/.ssh/known_hosts

RUN service mongodb start && service docker start 

COPY install.sh /install.sh
RUN chmod +x /install.sh && /install.sh

CMD bin/bash