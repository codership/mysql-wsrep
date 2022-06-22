#!/usr/bin/env bash
#
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

set -eux

GALERA_GIT_REPOSITORY=${GALERA_GIT_REPOSITORY:-"https://github.com/codership/galera.git"}
GALERA_BRANCH=${GALERA_BRANCH:-"3.x"}

CC=${CC:-/usr/lib/ccache/gcc}
CXX=${CXX:-/usr/lib/ccache/g++}
COMMON_CMAKE_OPTIONS="-DCMAKE_COLOR_MAKEFILE:BOOL=OFF
                      -DCMAKE_C_COMPILER=${CC}
                      -DCMAKE_CXX_COMPILER=${CXX}
                      -DWITH_BOOST=/var/tmp
                      -DDOWNLOAD_BOOST=1
                      -DWITH_SSL=/usr/local/openssl
                      -DWITH_GALERA:BOOL=ON
                      -DGALERA_GIT_REPOSITORY=${GALERA_GIT_REPOSITORY}
                      -DGALERA_BRANCH=${GALERA_BRANCH}
                      -DINSTALL_LAYOUT=STANDALONE
                      -DWITH_ZLIB=bundled
                      -DWITH_LIBEVENT=bundled
                      -DWITH_EDLITLINE=bundled
                      -DWITH_EXTRA_CHARSETS=all"

