#
# Helper macro for collation tests. This macro executes two
# statements which are not supposed to conflict. The caller is
# responsible for checking the final result.
#
# Parameters
#
# $collation_query_node_1 - Query which is run on node_1
# $collation_query_node_2 - Query which is run on node_2
#

--connection node_1
SET SESSION wsrep_sync_wait = 0;

--connection node_1_ctrl
SET GLOBAL DEBUG = "+d,sync.wsrep_apply_cb";

--connection node_2
--eval $collation_query_node_2

--connection node_1_ctrl
SET DEBUG_SYNC = "now WAIT_FOR sync.wsrep_apply_cb_reached";

--let $galera_sync_point = commit_monitor_enter_sync
--source include/galera_set_sync_point.inc

--connection node_1
--send_eval $collation_query_node_1

--connection node_1_ctrl
--source include/galera_wait_sync_point.inc
--source include/galera_clear_sync_point.inc
--source include/galera_signal_sync_point.inc
SET GLOBAL DEBUG = "-d,sync.wsrep_apply_cb";
SET DEBUG_SYNC = "now SIGNAL signal.wsrep_apply_cb";

--connection node_1
--reap
SET SESSION wsrep_sync_wait = DEFAULT;
