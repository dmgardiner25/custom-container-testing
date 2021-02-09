#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
FROM mcr.microsoft.com/oryx/build:vso-focal-20201204.1 as kitchensink

ARG USERNAME=codespace
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Default to bash shell (other shells available at /usr/bin/fish and /usr/bin/zsh)
ENV SHELL=/bin/bash \
    ORYX_ENV_TYPE=vsonline-present \
    DOTNET_ROOT="/home/${USERNAME}/.dotnet" \ 
    NVM_SYMLINK_CURRENT=true \
    NVM_DIR="/home/${USERNAME}/.nvm" \
    NVS_HOME="/home/${USERNAME}/.nvs" \
    NPM_GLOBAL="/home/${USERNAME}/.npm-global" \
    PIPX_HOME="/usr/local/py-utils" \
    PIPX_BIN_DIR="/usr/local/py-utils/bin" \
    RVM_PATH="/usr/local/rvm" \
    GOROOT="/usr/local/go" \
    GOPATH="/go" \
    CARGO_HOME="/usr/local/cargo" \
    RUSTUP_HOME="/usr/local/rustup" \
    SDKMAN_DIR="/usr/local/sdkman"
ENV PATH="${ORIGINAL_PATH}:${NVM_DIR}/current/bin:${NPM_GLOBAL}/bin:${DOTNET_ROOT}:${DOTNET_ROOT}/tools:${SDKMAN_DIR}/bin:${SDKMAN_DIR}/candidates/gradle/current/bin:${SDKMAN_DIR}/java/current/bin:/opt/maven/lts:${CARGO_HOME}/bin:${GOROOT}/bin:${GOPATH}/bin:${PIPX_BIN_DIR}:/opt/conda/condabin:${ORYX_PATHS}"

# Install needed utilities and setup non-root user. Use a separate RUN statement to add your own dependencies.
COPY library-scripts/* setup-user.sh /tmp/scripts/
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    # Restore man command
    && yes | unminimize 2>&1 \ 
    # Run common script and setup user
    && bash /tmp/scripts/common-debian.sh "true" "${USERNAME}" "${USER_UID}" "${USER_GID}" "true" "true" \
    && bash /tmp/scripts/setup-user.sh "${USERNAME}" "${PATH}" \
    # Change owner of opt contents since Oryx can dynamically install and will run as "codespace"
    && chown codespace /opt/* \
    # Verify expected build and debug tools are present
    && apt-get -y install build-essential cmake cppcheck valgrind clang lldb llvm gdb \
    # Install tools and shells not in common script
    && apt-get install -yq vim vim-doc xtail software-properties-common libsecret-1-dev \
    # Install additional tools (useful for 'puppeteer' project)
    && apt-get install -y --no-install-recommends libnss3 libnspr4 libatk-bridge2.0-0 libatk1.0-0 libx11-6 libpangocairo-1.0-0 \
                                                  libx11-xcb1 libcups2 libxcomposite1 libxdamage1 libxfixes3 libpango-1.0-0 libgbm1 libgtk-3-0 \
    && bash /tmp/scripts/sshd-debian.sh \
    && bash /tmp/scripts/git-lfs-debian.sh \
    && apt-get install -yq git \
    && bash /tmp/scripts/azcli-debian.sh \
    && bash /tmp/scripts/kubectl-helm-debian.sh \
    # Install Moby CLI and Engine
    && bash /tmp/scripts/docker-in-docker-debian.sh "true" "${USERNAME}" "true" \
    # Clean up
    && apt-get autoremove -y && apt-get clean -y

# Install Python, PHP, Ruby utilities
RUN bash /tmp/scripts/python-debian.sh "none" "/opt/python/latest" "${PIPX_HOME}" "${USERNAME}" "true" \
    # Install rvm, rbenv, base gems
    && chown -R ${USERNAME} /opt/ruby/*/lib /opt/ruby/*/bin \
    && bash /tmp/scripts/ruby-debian.sh "none" "${USERNAME}" "true" "true" \
    # Install xdebug, link composer
    && yes | pecl install xdebug \
    && export PHP_LOCATION=$(dirname $(dirname $(which php))) \
    && echo "zend_extension=$(find ${PHP_LOCATION}/lib/php/extensions/ -name xdebug.so)" > ${PHP_LOCATION}/ini/conf.d/xdebug.ini \
    && echo "xdebug.mode = debug" >> ${PHP_LOCATION}/ini/conf.d/xdebug.ini \
    && echo "xdebug.start_with_request = yes" >> ${PHP_LOCATION}/ini/conf.d/xdebug.ini \
    && echo "xdebug.client_port = 9000" >> ${PHP_LOCATION}/ini/conf.d/xdebug.ini \
    && rm -rf /tmp/pear \
    && ln -s $(which composer.phar) /usr/local/bin/composer \
    && apt-get clean -y

# Mount for docker-in-docker 
VOLUME [ "/var/lib/docker" ]

# Fire Docker/Moby script if needed along with Oryx's benv
ENTRYPOINT [ "/usr/local/share/docker-init.sh", "/usr/local/share/ssh-init.sh", "benv" ]
CMD [ "sleep", "infinity" ]

# [Optional] Install debugger for development of Codespaces - Not in resulting image by default
ARG DeveloperBuild
RUN if [ -z $DeveloperBuild ]; then \
        echo "not including debugger" ; \
    else \
        curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l /vsdbg ; \
    fi

USER ${USERNAME}
