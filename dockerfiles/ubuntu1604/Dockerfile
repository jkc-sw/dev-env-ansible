
# Pull the prebuilt image
FROM geerlingguy/docker-ubuntu1604-ansible

# make sure some depenencies are installed
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    sudo

# set local
ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8

# Define the default username and home directory as overrideable arguments
ARG SHELL_USER=developer
ARG SHELL_UID=1000
ARG SHELL_GID=1000
ENV HOME /home/${SHELL_USER}
RUN export uid=${SHELL_UID} gid=${SHELL_GID} && \
    mkdir -p /home/${SHELL_USER} && \
    echo "${SHELL_USER}:x:${uid}:${gid}:${SHELL_USER},,,:${HOME}:/bin/bash" >> /etc/passwd && \
    echo "${SHELL_USER}:x:${uid}:" >> /etc/group && \
    echo "${SHELL_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${SHELL_USER} && \
    chmod 0440 /etc/sudoers.d/${SHELL_USER} && \
    chown ${uid}:${gid} -R ${HOME}
RUN echo ${SHELL_USER}:APASSWORD | chpasswd

# Switch to the new user
USER ${SHELL_USER}

# Go to user home
WORKDIR ${HOME}

# docker image entry point
CMD /bin/bash


