#
# This macro verifies that two statements conflict in certification
# and checks that the returned error code for the failed one is correct.
#
# The caller is responsible for setting control connection node_1_ctrl on
# the first node and checking the final result in the database contents.
#
# Parameters
#
# $certification_query_node_1 - Query which is run on node_1
# $certification_query_node_2 - Query which is run on node_2, is ordered first
#

--connection node_1
SET SESSION wsrep_sync_wait = 0;
SET SESSION wsrep_retry_autocommit = 0;

--connection node_1_ctrl
SET GLOBAL DEBUG = "+d,sync.wsrep_apply_cb";

--connection node_2
--eval $certification_query_node_2

--connection node_1_ctrl
SET DEBUG_SYNC = "now WAIT_FOR sync.wsrep_apply_cb_reached";

--connection node_1
--error ER_LOCK_DEADLOCK
--eval $certification_query_node_1

--connection node_1_ctrl
SET GLOBAL DEBUG = "-d,sync.wsrep_apply_cb";
SET DEBUG_SYNC = "now SIGNAL signal.wsrep_apply_cb";

--connection node_1
SET SESSION wsrep_retry_autocommit = DEFAULT;
SET SESSION wsrep_sync_wait = DEFAULT;
