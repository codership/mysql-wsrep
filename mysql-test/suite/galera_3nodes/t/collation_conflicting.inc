#
# Helper macro for collation tests. This macro executes two
# statements which are supposed to conflict. The caller is
# responsible for checking the final result.
#
# Parameters
#
# $collation_query_node_1 - Query which is run on node_1
# $collation_query_node_2 - Query which is run on node_2
#

--connection node_1
SET SESSION wsrep_sync_wait = 0;
SET SESSION wsrep_retry_autocommit = 0;

--connection node_1_ctrl
SET GLOBAL DEBUG = "+d,sync.wsrep_apply_cb";

--connection node_2
--eval $collation_query_node_2

--connection node_1_ctrl
SET DEBUG_SYNC = "now WAIT_FOR sync.wsrep_apply_cb_reached";

--connection node_1
--error ER_LOCK_DEADLOCK
--eval $collation_query_node_1

--connection node_1_ctrl
SET GLOBAL DEBUG = "-d,sync.wsrep_apply_cb";
SET DEBUG_SYNC = "now SIGNAL signal.wsrep_apply_cb";

--connection node_1
SET SESSION wsrep_retry_autocommit = DEFAULT;
SET SESSION wsrep_sync_wait = DEFAULT;
