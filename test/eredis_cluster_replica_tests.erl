%% @doc Tests for the read-replica support: topology parsing, the refresh
%% pool diff and pool naming.
-module(eredis_cluster_replica_tests).

-include_lib("eunit/include/eunit.hrl").
-include("eredis_cluster.hrl").

-import(eredis_cluster_topology_fixtures,
        [cluster_slots/1, slots_maps/1, slots_maps/2,
         node_entry/3, empty_endpoint_replica/1, unknown_endpoint_replica/1]).

%% =============================================================================
%% CLUSTER SLOTS parsing
%% =============================================================================

addrport(#node{address = A, port = P}) -> {A, P}.

replica_addrports(#slots_map{replicas = Replicas}) ->
    [addrport(R) || R <- Replicas].

no_replicas_test() ->
    [SM] = slots_maps([{0, 16383, 30001, []}]),
    ?assertEqual({"127.0.0.1", 30001}, addrport(SM#slots_map.node)),
    ?assertEqual([], SM#slots_map.replicas).

one_replica_test() ->
    [SM] = slots_maps([{0, 16383, 30001, [30004]}]),
    %% Master must still parse correctly when a replica is present (guards
    %% against transposing the master and first-replica bindings).
    ?assertEqual({"127.0.0.1", 30001}, addrport(SM#slots_map.node)),
    ?assertEqual([{"127.0.0.1", 30004}], replica_addrports(SM)).

two_replicas_test() ->
    [SM] = slots_maps([{0, 16383, 30001, [30004, 30005]}]),
    ?assertEqual({"127.0.0.1", 30001}, addrport(SM#slots_map.node)),
    ?assertEqual([{"127.0.0.1", 30004}, {"127.0.0.1", 30005}],
                 replica_addrports(SM)).

%% Redis 3 node entries are [Addr, Port]; Redis 7 entries carry a node id and
%% a metadata list. The extra elements must be ignored.
redis3_shape_test() ->
    [SM] = slots_maps([{0, 16383, 30001, [30004]}], redis3),
    ?assertEqual({"127.0.0.1", 30001}, addrport(SM#slots_map.node)),
    ?assertEqual([{"127.0.0.1", 30004}], replica_addrports(SM)).

redis7_shape_test() ->
    [SM] = slots_maps([{0, 16383, 30001, [30004]}], redis7),
    ?assertEqual({"127.0.0.1", 30001}, addrport(SM#slots_map.node)),
    ?assertEqual([{"127.0.0.1", 30004}], replica_addrports(SM)).

skip_empty_and_unknown_endpoints_test() ->
    Reply = [[<<"0">>, <<"16383">>,
              node_entry(<<"127.0.0.1">>, 30001, redis4),
              empty_endpoint_replica(30004),
              unknown_endpoint_replica(30005),
              node_entry(<<"127.0.0.1">>, 30006, redis4)]],
    [SM] = eredis_cluster_monitor:parse_cluster_slots(Reply, []),
    ?assertEqual([{"127.0.0.1", 30006}], replica_addrports(SM)).

malformed_replica_entries_are_skipped_test() ->
    %% Replica entries are best-effort: an unparsable port or an unexpected
    %% entry shape must not fail the whole topology refresh.
    Reply = [[<<"0">>, <<"16383">>,
              node_entry(<<"127.0.0.1">>, 30001, redis4),
              [<<"127.0.0.1">>, <<"not-a-port">>],
              <<"unexpected-shape">>,
              [<<"127.0.0.1">>],
              node_entry(<<"127.0.0.1">>, 30004, redis4)]],
    [SM] = eredis_cluster_monitor:parse_cluster_slots(Reply, []),
    ?assertEqual([{"127.0.0.1", 30004}], replica_addrports(SM)).

malformed_master_entry_still_fails_test() ->
    %% Master entries keep their strict, pre-replica behaviour.
    Reply = [[<<"0">>, <<"16383">>, [<<"127.0.0.1">>, <<"not-a-port">>]]],
    ?assertError(badarg, eredis_cluster_monitor:parse_cluster_slots(Reply, [])).

options_stamped_on_master_and_replicas_test() ->
    Options = [{password, "secret"}, {pool_size, 5}],
    Reply = cluster_slots([{0, 16383, 30001, [30004]}]),
    [SM] = eredis_cluster_monitor:parse_cluster_slots(Reply, Options),
    ?assertEqual(Options, (SM#slots_map.node)#node.options),
    ?assertEqual([Options], [R#node.options || R <- SM#slots_map.replicas]).

multiple_ranges_test() ->
    Maps = slots_maps([{0, 5460, 30001, [30004]},
                       {5461, 10922, 30002, [30005]},
                       {10923, 16383, 30003, [30006]}]),
    ?assertEqual(3, length(Maps)),
    ?assertEqual([{0, 5460}, {5461, 10922}, {10923, 16383}],
                 [{SM#slots_map.start_slot, SM#slots_map.end_slot} || SM <- Maps]),
    ?assertEqual([[{"127.0.0.1", 30004}],
                  [{"127.0.0.1", 30005}],
                  [{"127.0.0.1", 30006}]],
                 [replica_addrports(SM) || SM <- Maps]).

%% =============================================================================
%% Refresh diff (pools_to_close)
%% =============================================================================

tnode(Port, Pool) ->
    #node{address = "127.0.0.1", port = Port, options = [], pool = Pool}.

tsm(Master, Replicas) ->
    #slots_map{start_slot = 0, end_slot = 16383, index = 1,
               node = Master, replicas = Replicas}.

close_pools(Old, New, ReplicaReads) ->
    lists:sort([Pool || {_Id, Pool} <-
                    eredis_cluster_monitor:pools_to_close(Old, New, ReplicaReads)]).

node_identity_is_role_qualified_test() ->
    N = tnode(30001, undefined),
    ?assertNotEqual(eredis_cluster_monitor:node_identity(N, master),
                    eredis_cluster_monitor:node_identity(N, replica)).

stable_topology_closes_nothing_test() ->
    Old = [tsm(tnode(30001, m1), [tnode(30004, r1)])],
    New = [tsm(tnode(30001, undefined), [tnode(30004, undefined)])],
    ?assertEqual([], close_pools(Old, New, true)).

drops_only_removed_replica_test() ->
    Old = [tsm(tnode(30001, m1), [tnode(30004, r1), tnode(30005, r2)])],
    New = [tsm(tnode(30001, undefined), [tnode(30004, undefined)])],
    ?assertEqual([r2], close_pools(Old, New, true)).

demoted_master_pool_closed_with_replica_reads_off_test() ->
    %% 30001 was a master (pool m1); the new topology makes it a replica of
    %% 30002. With replica_reads off, the old master pool must still close.
    Old = [tsm(tnode(30001, m1), [])],
    New = [tsm(tnode(30002, undefined), [tnode(30001, undefined)])],
    ?assertEqual([m1], close_pools(Old, New, false)).

replica_reads_toggled_off_closes_replica_pools_test() ->
    Old = [tsm(tnode(30001, m1), [tnode(30004, r1)])],
    New = [tsm(tnode(30001, undefined), [tnode(30004, undefined)])],
    ?assertEqual([r1], close_pools(Old, New, false)).

promoted_replica_closes_old_replica_pool_test() ->
    %% 30004 was a replica (pool r1); it is promoted to master in the new map.
    %% Its old #r pool must close (a fresh master pool is created elsewhere).
    Old = [tsm(tnode(30001, m1), [tnode(30004, r1)])],
    New = [tsm(tnode(30004, undefined), [])],
    ?assertEqual([m1, r1], close_pools(Old, New, true)).

%% =============================================================================
%% Pool naming
%% =============================================================================

master_pool_name_is_unsuffixed_test() ->
    ?assertEqual('127.0.0.1#30001',
                 eredis_cluster_pool:get_name("127.0.0.1", 30001)),
    ?assertEqual('127.0.0.1#30001',
                 eredis_cluster_pool:get_name("127.0.0.1", 30001, master)).

replica_pool_name_is_r_suffixed_test() ->
    ?assertEqual('127.0.0.1#30001#r',
                 eredis_cluster_pool:get_name("127.0.0.1", 30001, replica)).
