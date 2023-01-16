
# Pull the prebuilt image
FROM docker.io/ubuntu:22.04

# Ensure that dpkg doesn't run any "nice" interactive installation front-ends
ENV DEBIAN_FRONTEND=noninteractive

# make sure some depenencies are installed
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get install -y --no-install-recommends \
    sudo \
    git \
    curl \
    locales \
    xz-utils \
    ca-certificates

# Explicitly configure the locale as English (US), and use of UTF-8 character encoding
RUN dpkg-reconfigure locales \
    && locale-gen en_US.UTF-8 \
    && update-locale LC ALL=en_US.UTF-8 LANG=en_US.UTF-8
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Define the default username and home directory as overrideable arguments
ARG SHELL_USER=developer
ARG SHELL_UID=1000
ARG SHELL_GID=1000
ENV HOME /home/${SHELL_USER}
ENV USER ${SHELL_USER}
RUN export uid=${SHELL_UID} gid=${SHELL_GID} && \
    mkdir -p /home/${SHELL_USER} && \
    echo "${SHELL_USER}:x:${uid}:${gid}:${SHELL_USER},,,:${HOME}:/bin/bash" >> /etc/passwd && \
    echo "${SHELL_USER}:x:${uid}:" >> /etc/group && \
    echo "${SHELL_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${SHELL_USER} && \
    chmod 0440 /etc/sudoers.d/${SHELL_USER} && \
    chown ${uid}:${gid} -R ${HOME}
RUN echo ${SHELL_USER}:aoeu | chpasswd

# Switch to the new user
USER ${SHELL_USER}

RUN mkdir -p ${HOME}/repos

# Go to user home
WORKDIR ${HOME}

# docker image entry point
CMD /bin/bash


