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

set -eu
set -x

error()
{
    echo "Error: $@"
    exit 1
}

BUILD_DIR=${BUILD_DIR:-"build_debug"}

export MTR_PARALLEL=8
export MTR_PORT_GROUP_SIZE=50

root_dir=$(cd $(dirname $0)/../../.. ; pwd -P)

cd "${BUILD_DIR}/mysql-test"
export MTR_BINDIR="${BUILD_DIR}"
export PATH="${PXB_PATH}:${PATH}"

# Verify that xtrabackup binaries can be found from the path
if ! which xtrabackup > /dev/null
then
    error "Could not find xtrabackup binary from path $PATH"
fi
if ! xtrabackup --version
then
    error "Xtrabackup is not executable"
fi

./mtr --mysqld=--plugin-dir="${BUILD_DIR}"/lib/plugin \
      --suites=galera,galera_3nodes,wsrep \
      --testcase-timeout=15 --big-test \
      --max-test-fail=0 --force --max-save-core=1 \
      --retry=3 --report-unstable-tests \
      --test-progress=1 \
      --xml-report=Galera.xml \
      $@
