# Copyright (C) 2022 Codership Oy <info@galeracluster.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2.0,
# as published by the Free Software Foundation.
#
# This program is also distributed with certain software (including
# but not limited to OpenSSL) that is licensed under separate terms,
# as designated in a particular file or component or in included license
# documentation.  The authors of MySQL hereby grant you an additional
# permission to link the program and your derivative works with the
# separately licensed software that they have included with MySQL.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License, version 2.0, for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

FROM ubuntu:18.04
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update -y && apt-get upgrade -y

# General build tools
RUN apt-get install -y cmake make g++ ccache git curl
# OpenSSL
RUN curl -O -L \
  https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_1_1_1o.tar.gz &&\
  mkdir openssl && \
  tar xf OpenSSL_1_1_1o.tar.gz --strip-components=1 -C openssl && \
  (cd openssl && \
   ./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl && \
   make -j$(nproc --all) && \
   make install) && \
   rm -r openssl
# Galera build deps
RUN apt-get install -y check libboost-program-options-dev
# MySQL build deps
RUN apt-get install -y bison flex libncurses5-dev libssl-dev pkg-config
# MTR deps
RUN apt-get install -y lsof rsync socat stunnel libaio1 libnuma1 libeatmydata1 gdb ca-certificates unzip binutils perl libjson-perl iproute2 net-tools procps zip libxml-simple-perl
