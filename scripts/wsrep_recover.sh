#!/usr/bin/env bash

# Copyright (c) 2016 MariaDB Corporation
# Copyright (c) 2023 Codership Oy
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1335  USA */


# This script is intended to be executed by systemd. It starts mysqld with
# --wsrep-recover to recover from a non-graceful shutdown, determines the
# last stored global transaction ID and echoes it in --wsrep-start-position=XX
# format. The output is then captured and used by systemd to start mysqld.

set -u

mysqld_path="@libexecdir@/mysqld"
mysqld_user="@MYSQLD_USER@"

usage()
{
    echo "Usage: sudo $(basename $0) [options]"
    echo 'Recover database to consistend state, find the last committed GTID and print'
    echo 'corresponding --wsrep-start-position option to standard output (to be used in'
    echo 'startup scripts)'
    echo ''
    echo 'Options for the most part will be passed through directly to mysqld.'
    echo 'Some options have a special meaning though (NOTE whitespace between the option '
    echo 'name and the value):'
    echo '  --basedir /x/y/z        will additionally set mysqld binary path to'
    echo '                          /x/y/z/bin/mysqld'
    echo '  --mysqld /x/y/z/mysqld  will override --basedir effect on mysqld binary path'
    echo ''
    echo 'For example to run in a totally non-standard setup:'
    echo ''
    echo "\$ sudo $(basename $0) --mysqld /path/to/mysqld --datadir /path/to/datadir --user some_user"
    echo ''
    echo "By default mysqld binary is expected to be found at '$mysqld_path' "
    echo "and will be run as '$mysqld_user' user using config from a standard location."
}

mysqld_options=""
log_file=$(mktemp /tmp/wsrep_recovery.XXXXXX)
start_pos_opt=""

log()
{
  local msg="$1"
  # Print all messages to stderr as we reserve stdout for printing
  # --wsrep-start-position=XXXX.
  echo "$msg" >&2
}

finish()
{
  rm -f "$log_file"
}

trap finish EXIT

wsrep_recover_position() {
  # Redirect server's error log to the log file.
  eval $mysqld_path $mysqld_options 2> "$log_file"
  local ret=$?
  if [ $ret -ne 0 ]; then
    # Something went wrong, let us also print the error log so that it
    # shows up in systemctl status output as a hint to the user.
    log "WSREP: Failed to start mysqld for wsrep recovery: '`cat $log_file`'"
    exit 1
  fi

  # Parse server's error log for recovered position. The server prints
  # "..skipping position recovery.." if started without wsrep.

  local recovered_pos="$(grep 'WSREP: Recovered position:' $log_file)"

  if [ -z "$recovered_pos" ]; then
    local skipped="$(grep WSREP $log_file | grep 'skipping position recovery')"
    if [ -z "$skipped" ]; then
      log "WSREP: Failed to recover position: '`cat $log_file`'"
      exit 1
    else
      log "WSREP: Position recovery skipped."
    fi
  else
    local start_pos="$(echo $recovered_pos | sed 's/.*WSREP\:\ Recovered\ position://' \
                     | sed 's/^[ \t]*//')"
    log "WSREP: Recovered position $start_pos"
    start_pos_opt="--wsrep_start_position=$start_pos"
  fi
}

path_given="N"
user_given="N"

while [ $# -gt 0 ]; do
case "$1" in
 "--mysqld")
     mysqld_path=${2}
     path_given="Y"
     shift
     ;;
 '--basedir')
     mysqld_options+=" $1 $2"
     [ "$path_given" = "N" ] && mysqld_path=${2}/bin/mysqld
     shift
     ;;
 '--user')
     mysqld_options+=" $1 $2"
     user_given="Y"
     shift
     ;;
 '--user='*)
     mysqld_options+=" $1"
     user_given="Y"
     ;;
 '--help')
     usage
     exit 0
     ;;
 *)
    # option solely for mysqld
    mysqld_options+=" $1"
    ;;
esac
shift
done

[ "$user_given" != "Y" ] && mysqld_options+=" --user $mysqld_user"
mysqld_options+=" --wsrep-recover --disable-log-error"

# Safety checks
if [ -n "$log_file" -a -f "$log_file" ]; then
  chmod 600 $log_file
else
  log "WSREP: mktemp failed"
fi

wsrep_recover_position

echo "$start_pos_opt"
