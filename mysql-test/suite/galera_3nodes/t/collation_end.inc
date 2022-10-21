#
# At this point it is guaranteed that both transactions are in flight
# and have not seen the effect of each other. The only way to detect
# the conflict is certification.
#
# Unblock certification
#
--connection node_1
--source include/galera_clear_sync_point.inc
--source include/galera_signal_sync_point.inc

--connection node_2
--source include/galera_clear_sync_point.inc
--source include/galera_signal_sync_point.inc

#--connection node_3
#--source include/galera_signal_sync_point.inc
#--source include/galera_clear_sync_point.inc

#
# Expect either success or ER_LOCK_DEADLOCK depending on the test setup
# Failure will be determined by the number of the resulting rows
#
--connection node_1a
--error 0, ER_LOCK_DEADLOCK
--reap

--connection node_2a
--error 0, ER_LOCK_DEADLOCK
--reap

#
# Wait for results and cleanup
#
--let $wait_condition = SELECT COUNT(*) = $expect_rows FROM tcoll;

--connection node_1
--source include/wait_condition.inc

--connection node_2
--source include/wait_condition.inc

--connection node_3
--source include/wait_condition.inc

DROP TABLE tcoll;
