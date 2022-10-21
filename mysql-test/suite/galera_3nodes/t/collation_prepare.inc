#
# This test checks the corect operation with respect to padding and non-padding
# string key collations
#

--source include/galera_cluster.inc
--source include/have_innodb.inc
--source suite/galera/include/galera_have_debug_sync.inc

--let $galera_connection_name = node_3
--let $galera_server_number = 3
--source include/galera_connect.inc

--connect node_1a, 127.0.0.1, root, , test, $NODE_MYPORT_1
--connect node_2a, 127.0.0.1, root, , test, $NODE_MYPORT_2
--connect node_3a, 127.0.0.1, root, , test, $NODE_MYPORT_3

#
# Disable autocommit retrying to reliably detect the conflicts
#
--connection node_1a
SET wsrep_retry_autocommit = 0;

--connection node_2a
SET wsrep_retry_autocommit = 0;
