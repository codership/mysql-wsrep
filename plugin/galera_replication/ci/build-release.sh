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

root_dir="$(cd $(dirname $0)/../../.. ; pwd -P)"

GALERA_GIT_REPOSITORY=${GALERA_GIT_REPOSITORY:-"https://github.com/codership/galera.git"}
GALERA_BRANCH=${GALERA_BRANCH:-"3.x"}
SOURCE_DIR=${SOURCE_DIR:-"${root_dir}"}
BUILD_DIR=${BUILD_DIR:-"build_release"}

cd "${root_dir}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
cmake -DCMAKE_BUILD_TYPE=Release \
      -DPACKAGE_SUFFIX="-galera-${GALERA_BRANCH/\//_}-release" \
      -DCMAKE_COLOR_MAKEFILE:BOOL=OFF \
      -DCMAKE_C_COMPILER=/usr/lib/ccache/gcc \
      -DCMAKE_CXX_COMPILER=/usr/lib/ccache/g++ \
      -DWITH_BOOST=/var/tmp \
      -DDOWNLOAD_BOOST=1 \
      -DWITH_GALERA:BOOL=ON \
      -DGALERA_GIT_REPOSITORY="${GALERA_GIT_REPOSITORY}" \
      -DGALERA_BRANCH="${GALERA_BRANCH}" \
      "${SOURCE_DIR}"
make -j$(nproc --all)

if [ -z "${SKIP_PACKAGE:-}" ]; then
    make package
fi
