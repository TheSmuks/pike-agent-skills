# Lab: Pike 8.0 built with the modules Roxen requires, plus a real Roxen 6
# checkout. Used to verify the tools against an actual Roxen environment
# rather than against fixtures.
#
# Debian's pike8.0 packages are not sufficient. Roxen hard-exits without
# Regexp.PCRE, and that module is a compile-time option Debian does not build
# (it ships the docs for it, but not the module). So Pike is built from source
# here with libpcre and the MySQL headers present, which is what makes those
# modules appear.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG PIKE_VERSION=8.0.1116
ARG ROXEN_BRANCH=6.3

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        gcc g++ make bison \
        libgmp-dev nettle-dev zlib1g-dev \
        libpcre3-dev default-libmysqlclient-dev \
        curl ca-certificates git m4 \
    && rm -rf /var/lib/apt/lists/*

# Roxen's startup checks, and the dev package each one needs:
#   Sql.mysql      -> default-libmysqlclient-dev
#   Regexp.PCRE    -> libpcre3-dev
#   Crypto.*       -> nettle-dev
#   bignum support -> libgmp-dev
# Pike's configure picks these up automatically when the headers are present.
RUN cd /tmp \
    && curl -sL "https://pike.lysator.liu.se/pub/pike/all/${PIKE_VERSION}/Pike-v${PIKE_VERSION}.tar.gz" \
         -o pike.tar.gz \
    && tar xzf pike.tar.gz \
    && cd "Pike-v${PIKE_VERSION}" \
    && make CONFIGUREARGS="--without-debug" -j"$(nproc)" \
    && make install \
    && ln -sf "/usr/local/pike/${PIKE_VERSION}/bin/pike" /usr/local/bin/pike \
    && cd / && rm -rf /tmp/pike.tar.gz "/tmp/Pike-v${PIKE_VERSION}"

# Roxen expects a MySQL under server/mysql/ and refuses to start without one.
# Rather than bundling a build, point it at the distro's MariaDB using the
# documented server/mysql-location.txt indirection.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        mariadb-server mariadb-client \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch ${ROXEN_BRANCH} \
        https://github.com/pikelang/Roxen.git /opt/roxen

# Keys are read by roxenloader.pike:mysql_location(). Non-absolute paths would
# be taken relative to the server directory, so these are absolute.
RUN printf '%s\n' \
      '# Point Roxen at the distro MariaDB instead of a bundled build.' \
      'basedir = /usr' \
      'mysqld = /usr/sbin/mariadbd' \
      'mysqldump = /usr/bin/mariadb-dump' \
      'myisamchk = /usr/bin/myisamchk' \
      'mysqladmin = /usr/bin/mariadb-admin' \
      'mysql_upgrade = /usr/bin/mariadb-upgrade' \
      > /opt/roxen/server/mysql-location.txt

# Fail the build here if Pike lacks anything Roxen hard-requires, rather than
# letting it surface later as a silent _exit(0) during Roxen startup.
RUN for m in Sql.mysql Regexp.PCRE Crypto.SHA256 Crypto.AES.GCM Crypto.ECC.Curve; do \
      pike -e "if (undefinedp(master()->resolv(\"$m\"))) { werror(\"MISSING: $m\n\"); exit(1); }" \
        || exit 1; \
    done && echo "all Roxen-required Pike modules present"

WORKDIR /opt/roxen
