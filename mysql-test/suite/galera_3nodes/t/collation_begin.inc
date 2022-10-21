#
# Wait for table to be replicated to the rest of the nodes
#
--let $wait_condition = SELECT COUNT(*) = 1 FROM INFORMATION_SCHEMA.TABLES WHERE (TABLE_SCHEMA = 'test') AND (TABLE_NAME = 'tcoll');

--connection node_2
--source include/wait_condition.inc

--connection node_3
--source include/wait_condition.inc

#
# Block certification on all nodes
#
--let $galera_sync_point = local_monitor_enter_sync

--connection node_1
--source include/galera_set_sync_point.inc

--connection node_2
--source include/galera_set_sync_point.inc

#--connection node_3
#--source include/galera_set_sync_point.inc
