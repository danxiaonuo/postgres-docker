#############################
#     设置公共的变量         #
#############################
ARG BASE_IMAGE_TAG=22.04
FROM ubuntu:${BASE_IMAGE_TAG}

# 作者描述信息
MAINTAINER danxiaonuo
# 时区设置
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
# 语言设置
ARG LANG=zh_CN.UTF-8
ENV LANG=$LANG

# 镜像变量
ARG DOCKER_IMAGE=danxiaonuo/postgres
ENV DOCKER_IMAGE=$DOCKER_IMAGE
ARG DOCKER_IMAGE_OS=ubuntu
ENV DOCKER_IMAGE_OS=$DOCKER_IMAGE_OS
ARG DOCKER_IMAGE_TAG=22.04
ENV DOCKER_IMAGE_TAG=$DOCKER_IMAGE_TAG

# PG版本号
ARG PG_MAJOR=15
ENV MYSQL_MAJOR=$PG_MAJOR
ARG PG_VERSION=${PG_MAJOR}_15.1-1
ENV PG_VERSION=$PG_VERSION
ENV PATH $PATH:/usr/lib/postgresql/$PG_MAJOR/bin

# 工作目录
ARG PGHOME=/data/postgres
ENV PGHOME=$PGHOME

# 数据目录
ARG PGDATA=/data/postgres/data
ENV PGDATA=$PGDATA

# 环境设置
ARG DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND=$DEBIAN_FRONTEND

# 源文件下载路径
ARG DOWNLOAD_SRC=/tmp
ENV DOWNLOAD_SRC=$DOWNLOAD_SRC

# 安装依赖包
ARG PKG_DEPS="\
    zsh \
    bash \
    bash-completion \
    sudo \
    dnsutils \
    iproute2 \
    net-tools \
    ncat \
    git \
    vim \
    tzdata \
    curl \
    wget \
    axel \
    lsof \
    zip \
    unzip \
    rsync \
    iputils-ping \
    telnet \
    procps \
    libaio1 \
    numactl \
    xz-utils \
    zstd \
    libnss-wrapper \
    gnupg2 \
    psmisc \
    libmecab2 \
    debsums \
    locales \
    language-pack-zh-hans \
    lsb-release \
    libpq5 \
    ssl-cert \
    libdbd-pg-perl \
    libdbi-perl \
    perl-modules \
    ca-certificates"
ENV PKG_DEPS=$PKG_DEPS


# PPG依赖包
ARG PPG_DEPS="\
    percona-ppg-server-${PG_MAJOR} \
    percona-pgbackrest \
    percona-pgbouncer \
    percona-pgaudit${PG_MAJOR}-set-user \
    percona-pgbadger"
ENV PPG_DEPS=$PPG_DEPS

# ***** 安装依赖 *****
RUN set -eux && \
   # 更新源地址
   sed -i s@http://*.*ubuntu.com@https://mirrors.aliyun.com@g /etc/apt/sources.list && \
   sed -i 's?# deb-src?deb-src?g' /etc/apt/sources.list && \
   # 解决证书认证失败问题
   touch /etc/apt/apt.conf.d/99verify-peer.conf && echo >>/etc/apt/apt.conf.d/99verify-peer.conf "Acquire { https::Verify-Peer false }" && \
   # 更新系统软件
   DEBIAN_FRONTEND=noninteractive apt-get update -qqy && apt-get upgrade -qqy && \
   # 安装依赖包
   DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends $PKG_DEPS && \
   DEBIAN_FRONTEND=noninteractive apt-get -qqy --no-install-recommends autoremove --purge && \
   DEBIAN_FRONTEND=noninteractive apt-get -qqy --no-install-recommends autoclean && \
   rm -rf /var/lib/apt/lists/* && \
   # 更新时区
   ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
   # 更新时间
   echo ${TZ} > /etc/timezone && \
   # sudo权限
   sed -i 's/^Defaults.*.requiretty/#Defaults    requiretty/' /etc/sudoers && \
   sed -i '$a\postgres  ALL=(ALL)  NOPASSWD:/bin/mkdir,/bin/chmod,/bin/chown' /etc/sudoers && \
   # 更改为zsh
   sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true && \
   sed -i -e "s/bin\/ash/bin\/zsh/" /etc/passwd && \
   sed -i -e 's/mouse=/mouse-=/g' /usr/share/vim/vim*/defaults.vim && \
   locale-gen zh_CN.UTF-8 && localedef -f UTF-8 -i zh_CN zh_CN.UTF-8 && locale-gen && \
   localedef -i zh_CN -c -f UTF-8 -A /usr/share/locale/locale.alias zh_CN.UTF-8 && \
   /bin/zsh

# grab gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION 1.16
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates wget; \
	rm -rf /var/lib/apt/lists/*; \
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true

# ***** 拷贝文件 *****
COPY ["ps-entry.sh", "/docker-entrypoint.sh"]

# ***** 下载postgres *****
RUN set -eux && \
    # 设置postgres用户
    groupadd -r postgres --gid=999 && useradd -r -g postgres --uid=999 --home-dir=${PGHOME} --shell=/bin/zsh postgres && \
    # 下载postgres源
    wget --no-check-certificate https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb \
    -O ${DOWNLOAD_SRC}/percona-release_latest.$(lsb_release -sc)_all.deb && \
    # 安装percona-postgres
    dpkg -i ${DOWNLOAD_SRC}/*.deb && \
    percona-release setup ppg-${PG_MAJOR} && \
    # 安装依赖包
    DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends $PPG_DEPS && \
    # 删除临时文件
    rm -rf /var/lib/apt/lists/* ${DOWNLOAD_SRC}/*.deb && \
    # 安装postgresqltuner
    wget https://raw.githubusercontent.com/jfcoz/postgresqltuner/master/postgresqltuner.pl -O /bin/postgresqltuner.pl && \
    mkdir -p /docker-entrypoint-initdb.d && \
    chown -R postgres:postgres /docker-entrypoint-initdb.d /docker-entrypoint.sh /root /bin/postgresqltuner.pl && \
    chmod -R 775 /docker-entrypoint-initdb.d /docker-entrypoint.sh /root /bin/postgresqltuner.pl && \
    rm -rf /etc/postgresql/${PG_MAJOR}/main/*.conf /var/lib/postgresql /var/run/postgresql/ /var/log/postgresql && \
    mkdir -m u=rwx,g=rwx,o= -p $PGHOME/data $PGHOME/logs $PGHOME/run $PGHOME/archive /var/run/postgresql /var/log/postgresql && \
    chown -R postgres:postgres $PGHOME /var/run/postgresql /var/log/postgresql && \
    chmod -R 755 $PGHOME /var/run/postgresql /var/log/postgresql && \
    sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf && \
    sed -i "/listen_addresses/c listen_addresses ='*'" /usr/share/postgresql/${PG_MAJOR}/postgresql.conf.sample && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get purge -y --auto-remove

# ***** 拷贝文件 *****
COPY ["conf/postgres/postgresql.conf.sample", "/usr/share/postgresql/${PG_MAJOR}/postgresql.conf.sample"]

# ***** 容器信号处理 *****
STOPSIGNAL SIGQUIT

# ***** 工作目录 *****
WORKDIR ${PGHOME}

# ***** 挂载目录 *****
VOLUME ${PGHOME}

# ***** 监听端口 *****
EXPOSE 5432

# ***** 用户 *****
USER 999

# ***** 入口 *****
ENTRYPOINT ["/docker-entrypoint.sh"]
