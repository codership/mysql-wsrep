-- Copyright (C) 2023 Codership Oy <info@galeracluster.com>
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
--
-- Helper script to print wsrep status, InnoDB lock information
-- and wsrep applier status.
--
-- When adding new diagnostics in this script, please place the queries
-- with more verbose output near bottom.
--

SET SESSION wsrep_sync_wait=0;

USE information_schema;

SELECT 'Wsrep status variables' AS '';
SELECT * FROM GLOBAL_STATUS WHERE VARIABLE_NAME LIKE 'wsrep_%';

SELECT 'Wsrep appliers and rollbacker thread status' AS '';
SELECT * FROM PROCESSLIST WHERE USER = 'system user'\G

SELECT 'Wsrep appliers active in InnoDB' AS '';
SELECT * FROM PROCESSLIST AS pl JOIN INNODB_TRX AS it
  ON pl.ID = it.trx_mysql_thread_id WHERE pl.USER = 'system user'\G

SELECT 'Wsrep appliers blocked by other transactions in InnoDB and all blocking transactions' AS '';
SELECT * FROM PROCESSLIST AS pl JOIN INNODB_TRX AS it
  ON pl.ID = it.trx_mysql_thread_id
  WHERE
    -- Blocked appliers
    (it.trx_id IN (SELECT requesting_trx_id FROM INNODB_LOCK_WAITS)
      AND pl.USER = 'system user')
    OR
    -- Blocking transactions
    (it.trx_id IN (SELECT blocking_trx_id FROM INNODB_LOCK_WAITS))\G

SELECT 'InnoDB lock waits' AS '';
SELECT * FROM INNODB_LOCK_WAITS\G

SELECT 'InnoDB locks - requested but not yet acquired, or blocking another transaction' AS '';
SELECT * FROM INNODB_LOCKS\G

SELECT 'All active InnoDB transactions' AS '';
SELECT * FROM INNODB_TRX\G

USE performance_schema;
SELECT 'Performance schema information' AS '';

SELECT 'Events_waits_current' AS '';
SELECT * FROM events_waits_current\G

SELECT 'Metadata locks' AS '';
SELECT * FROM metadata_locks\G

SELECT 'RWlock instances' AS '';
SELECT * FROM rwlock_instances WHERE WRITE_LOCKED_BY_THREAD_ID IS NOT NULL OR
  READ_LOCKED_BY_COUNT > 0\G

SELECT 'All processes' AS '';
SHOW PROCESSLIST\G

SET SESSION wsrep_sync_wait=DEFAULT;
