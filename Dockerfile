FROM ubuntu:bionic as builder

ARG DEVELOPER
ARG STANDALONE
ENV STANDALONE=$STANDALONE

WORKDIR /app

RUN echo "LC_ALL=en_US.UTF-8" >> /etc/environment
RUN echo "LANG=en_US.UTF-8" >> /etc/environment
RUN echo "NODE_ENV=development" >> /etc/environment
RUN more "/etc/environment"
#RUN locale-gen en_US en_US.UTF-8
#RUN dpkg-reconfigure locales

RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get dist-upgrade -y
RUN apt-get install curl htop git zip nano ncdu build-essential chrpath libssl-dev libxft-dev pkg-config glib2.0-dev -y
RUN apt-get install libexpat1-dev gobject-introspection python-gi-dev apt-transport-https libgirepository1.0-dev -y
RUN apt-get install libtiff5-dev libjpeg-turbo8-dev libgsf-1-dev fail2ban nginx -y

# Install Node.js
RUN curl -sL https://deb.nodesource.com/setup_8.x | bash
RUN apt-get install --yes nodejs
RUN node -v
RUN npm -v
RUN npm i -g nodemon
RUN nodemon -v

# Cleanup
RUN apt-get update && apt-get upgrade -y && apt-get autoremove -y

# Install build acm-lightning for third-party packages (acm-lightning/Actiniumd)
RUN apt-get update && apt-get install -y --no-install-recommends git \
    $([ -n "$STANDALONE" ] || echo "autoconf automake build-essential libtool libgmp-dev \
                                     libsqlite3-dev python python3 wget zlib1g-dev")

ARG LIGHTNINGD_VERSION=f48f5b2b253203f6e64d941f722ec9d4cb2e0bfe

RUN [ -n "$STANDALONE" ] || ( \
    git clone https://github.com/Actinium-project/acm-lightning.git /opt/lightningd \
    && cd /opt/lightningd \
    && git checkout $LIGHTNINGD_VERSION \
    && DEVELOPER=$DEVELOPER ./configure \
    && make)

# prepare packages for Actinium wallet
RUN apt-get update \
&& apt-get -y upgrade \
&& export DEBIAN_FRONTEND=noninteractive \
&& apt-get -y install libboost-all-dev libdb4.8 libdb4.8++ libssl-dev unzip \
libevent-dev software-properties-common \
git build-essential libtool autotools-dev automake pkg-config bsdmainutils python3 \
libcap-dev libseccomp-dev zlib1g-dev wget libzmq3-dev libminiupnpc-dev \
&& add-apt-repository ppa:bitcoin/bitcoin \
&& apt-get update \
&& apt-get -y install libdb4.8-dev libdb4.8++-dev unzip \
&& apt-get -y install wget libzmq5 libminiupnpc10 libcap2
# prepare Actinium wallet git
ENV GIT_COIN_URL https://github.com/Actinium-project/Actinium-ng.git
ENV GIT_COIN_NAME actinium-ng
# clone & compile Actinium wallet
RUN [ -n "$STANDALONE" ] || ( \
git clone $GIT_COIN_URL $GIT_COIN_NAME \
&& cd $GIT_COIN_NAME \
&& git checkout master \
&& chmod +x autogen.sh \
&& chmod +x share/genbuild.sh \
&& chmod +x src/leveldb/build_detect_platform \
&& ./autogen.sh && ./configure --disable-shared --disable-tests --disable-bench --without-gui LIBS="-lcap -lseccomp" \
&& make \
&& make install \
&& cd /)
# move compiled binaries to /opt/bin
RUN mkdir /opt/bin && ([ -n "$STANDALONE" ] || \
    (mv /opt/lightningd/cli/lightning-cli /opt/bin/ \
    && mv /opt/lightningd/lightningd/lightning* /opt/bin/))
# npm doesn't normally like running as root, allow it since we're in docker
RUN npm config set unsafe-perm true

# Install Spark
WORKDIR /opt/spark/client
COPY client/package.json client/npm-shrinkwrap.json ./
COPY client/fonts ./fonts
RUN npm install

WORKDIR /opt/spark
COPY package.json npm-shrinkwrap.json ./
RUN npm install
COPY . .

# Build production NPM package
RUN npm run dist:npm \
 && npm prune --production \
 && find . -mindepth 1 -maxdepth 1 \
           ! -name '*.json' ! -name dist ! -name LICENSE ! -name node_modules ! -name scripts \
           -exec rm -r "{}" \;

# Prepare final image

WORKDIR /opt/spark

RUN ([ -n "$STANDALONE" ] || ( \
          apt-get update && apt-get install -y --no-install-recommends inotify-tools libgmp-dev libsqlite3-dev xz-utils)) \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /opt/spark/dist/cli.js /usr/bin/spark-wallet \
    && mkdir /data \
    && ln -s /data/lightning $HOME/.lightning

ENV CONFIG=/data/spark/config TLS_PATH=/data/spark/tls TOR_PATH=/data/spark/tor HOST=0.0.0.0

# link the hsv3 (Tor Hidden Service V3) node_modules installation directory
# inside /data/spark/tor/, to persist the Tor Bundle download in the user-mounted volume
RUN ln -s $TOR_PATH/tor-installation/node_modules dist/transport/hsv3-dep/node_modules

COPY scripts/gen_wallet_conf.sh /opt/bin
COPY scripts/gen_ln_conf.sh /opt/bin
COPY scripts/gen_banner.sh /opt/bin
RUN chmod +x /opt/bin/*.sh

VOLUME /data
ENTRYPOINT [ "scripts/docker-entrypoint.sh" ]

EXPOSE 9735 9737

#CMD ["bash"]