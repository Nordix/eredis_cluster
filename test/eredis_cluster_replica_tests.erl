%% @doc Tests for the read-replica support.
%%
%% The first sections are network-free unit tests for topology parsing, the
%% refresh pool diff, replica selection, pool naming and the qr/qrk result
%% classification. The final section runs against the live docker cluster
%% started by `make start' (3 masters on 30001-30003, 3 replicas on
%% 30004-30006), like the other *_tests modules.
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
%% Replica selection (select_pool)
%% =============================================================================

select_master_returns_master_pool_test() ->
    SM = tsm(tnode(30001, m1), [tnode(30004, r1)]),
    ?assertEqual({m1, 7, master},
                 eredis_cluster_monitor:select_pool(SM, 7, master)).

select_replica_preferred_picks_a_connected_replica_test() ->
    SM = tsm(tnode(30001, m1), [tnode(30004, r1), tnode(30005, r2)]),
    {Pool, 7, Role} = eredis_cluster_monitor:select_pool(SM, 7, replica_preferred),
    ?assertEqual(replica, Role),
    ?assert(lists:member(Pool, [r1, r2])).

select_replica_preferred_falls_back_to_master_when_no_replicas_test() ->
    SM = tsm(tnode(30001, m1), []),
    ?assertEqual({m1, 7, master},
                 eredis_cluster_monitor:select_pool(SM, 7, replica_preferred)).

select_replica_preferred_skips_unconnected_replicas_test() ->
    SM = tsm(tnode(30001, m1), [tnode(30004, undefined), tnode(30005, r2)]),
    ?assertEqual({r2, 7, replica},
                 eredis_cluster_monitor:select_pool(SM, 7, replica_preferred)).

select_replica_preferred_all_unconnected_falls_back_test() ->
    SM = tsm(tnode(30001, m1), [tnode(30004, undefined)]),
    ?assertEqual({m1, 7, master},
                 eredis_cluster_monitor:select_pool(SM, 7, replica_preferred)).

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

%% =============================================================================
%% READONLY prepend/strip and result classification (qr/qrk internals)
%% =============================================================================

prepend_readonly_simple_test() ->
    ?assertEqual([[<<"READONLY">>], ["GET", "k"]],
                 eredis_cluster:prepend_readonly(["GET", "k"])).

prepend_readonly_pipeline_test() ->
    ?assertEqual([[<<"READONLY">>], ["GET", "a"], ["GET", "b"]],
                 eredis_cluster:prepend_readonly([["GET", "a"], ["GET", "b"]])).

strip_readonly_simple_ok_test() ->
    ?assertEqual({ok, <<"v">>},
                 eredis_cluster:strip_readonly_result(
                     ["GET", "k"], [{ok, <<"OK">>}, {ok, <<"v">>}])).

strip_readonly_pipeline_ok_test() ->
    ?assertEqual([{ok, <<"a">>}, {ok, <<"b">>}],
                 eredis_cluster:strip_readonly_result(
                     [["GET", "a"], ["GET", "b"]],
                     [{ok, <<"OK">>}, {ok, <<"a">>}, {ok, <<"b">>}])).

strip_readonly_rejected_test() ->
    ?assertMatch({error, {readonly_rejected, _}},
                 eredis_cluster:strip_readonly_result(
                     ["GET", "k"],
                     [{error, <<"ERR unknown command 'READONLY'">>},
                      {ok, <<"v">>}])).

strip_readonly_transport_error_passthrough_test() ->
    ?assertEqual({error, no_connection},
                 eredis_cluster:strip_readonly_result(
                     ["GET", "k"], {error, no_connection})).

strip_readonly_empty_result_test() ->
    ?assertEqual({error, redirect_failed},
                 eredis_cluster:strip_readonly_result(["GET", "k"], [])).

strip_readonly_arity_mismatch_test() ->
    %% A simple command must yield exactly one result after the strip.
    ?assertEqual({error, redirect_failed},
                 eredis_cluster:strip_readonly_result(
                     ["GET", "k"],
                     [{ok, <<"OK">>}, {ok, <<"a">>}, {ok, <<"b">>}])).

outcome(Result) ->
    eredis_cluster:replica_outcome(Result).

replica_outcome_falls_back_test() ->
    ?assertEqual(fallback_master,
                 outcome({error, <<"MOVED 1234 127.0.0.1:30001">>})),
    ?assertEqual(fallback_master,
                 outcome({error, <<"ASK 1234 127.0.0.1:30001">>})),
    ?assertEqual(fallback_master,
                 outcome({error, <<"LOADING Redis is loading the dataset">>})),
    ?assertEqual(fallback_master,
                 outcome({error, <<"MASTERDOWN Link with MASTER is down">>})),
    ?assertEqual(fallback_master,
                 outcome({error, <<"CLUSTERDOWN The cluster is down">>})),
    ?assertEqual(fallback_master, outcome({error, {readonly_rejected, x}})),
    ?assertEqual(fallback_master, outcome({error, no_connection})),
    ?assertEqual(fallback_master, outcome({error, redirect_failed})),
    ?assertEqual(fallback_master, outcome({error, timeout})).

replica_outcome_retries_test() ->
    ?assertEqual(retry_replica,
                 outcome({error, <<"TRYAGAIN Multiple keys request">>})),
    ?assertEqual(retry_replica, outcome({error, tcp_closed})),
    ?assertEqual(retry_replica, outcome({error, pool_busy})).

replica_outcome_real_reply_is_ok_test() ->
    %% A genuine reply (success or a real Redis error) must reach the caller.
    ?assertEqual(ok, outcome({ok, <<"value">>})),
    ?assertEqual(ok, outcome({error, <<"WRONGTYPE some message">>})),
    ?assertEqual(ok, outcome([{ok, <<"a">>}, {ok, <<"b">>}])).

replica_outcome_pipeline_redirect_falls_back_test() ->
    %% A (partially) redirected pipeline must be re-run on the master, not
    %% leak MOVED/LOADING elements to the caller.
    Moved = {error, <<"MOVED 1234 127.0.0.1:30001">>},
    ?assertEqual(fallback_master, outcome([Moved, Moved])),
    ?assertEqual(fallback_master, outcome([{ok, <<"a">>}, Moved])),
    ?assertEqual(fallback_master,
                 outcome([{ok, <<"a">>},
                          {error, <<"LOADING Redis is loading the dataset">>}])).

replica_outcome_pipeline_precedence_test() ->
    Moved = {error, <<"MOVED 1234 127.0.0.1:30001">>},
    TryAgain = {error, <<"TRYAGAIN Multiple keys request">>},
    %% Fallback beats retry: the master path can serve both conditions.
    ?assertEqual(fallback_master, outcome([TryAgain, Moved])),
    ?assertEqual(retry_replica, outcome([{ok, <<"a">>}, TryAgain])),
    %% Genuine per-command errors are the real answer.
    ?assertEqual(ok, outcome([{ok, <<"a">>},
                              {error, <<"WRONGTYPE some message">>}])).

%% =============================================================================
%% Live cluster tests (needs `make start': masters 30001-30003, replicas
%% 30004-30006)
%% =============================================================================

-define(Setup, fun() -> eredis_cluster:start() end).
-define(Cleanup, fun(_) -> eredis_cluster:stop() end).

replica_reads_live_test_() ->
    {inorder,
        {setup, ?Setup, ?Cleanup,
        [
            { "opt-out default: no replica pools, qr behaves like q",
            {timeout, 30, fun() ->
                ?assertEqual([], eredis_cluster:get_all_replica_pools()),
                ?assertEqual(undefined, whereis('127.0.0.1#30004#r')),
                ?assertEqual({ok, <<"OK">>},
                             eredis_cluster:qr(["SET", "rr_optout", "v1"])),
                ?assertEqual({ok, <<"v1">>}, eredis_cluster:qr(["GET", "rr_optout"])),
                ?assertEqual(eredis_cluster:q(["GET", "rr_optout"]),
                             eredis_cluster:qr(["GET", "rr_optout"])),
                ?assertEqual({error, invalid_cluster_command},
                             eredis_cluster:qr(["XXX"]))
            end}
            },

            { "opt-in: a replica pool per replica node",
            {timeout, 60, fun() ->
                ok = eredis_cluster:connect(rr_cluster, [{"127.0.0.1", 30001}],
                                            [{replica_reads, true},
                                             {replica_pool_size, 2}]),
                %% A preceding test may have triggered failovers; a demoted
                %% master rejoins as a replica only after a few seconds, so
                %% poll with topology refreshes until all replicas are back.
                Pools = wait_for_replica_pools(3, 100),
                ?assertMatch([_, _, _], Pools),
                [?assert(lists:suffix("#r", atom_to_list(Pool))) || Pool <- Pools],
                %% Failovers can leave the replicas unevenly spread over the
                %% shards, so a shard may own more than one of them. What must
                %% hold is the narrowing: a non-empty subset of the pools above.
                ByKey = eredis_cluster:get_replica_pools_by_key(rr_cluster, "foo"),
                ?assertMatch([_ | _], ByKey),
                [?assert(lists:member(Pool, Pools)) || Pool <- ByKey]
            end}
            },

            { "reads are answered by a replica",
            {timeout, 30, fun() ->
                %% ROLE carries no key, so no redirect can occur: the answer
                %% comes from whichever node the connection reaches. Routed
                %% through qrk it must reach a replica (proving the READONLY
                %% round-trip and the replica routing on the wire). Replica
                %% pools connect asynchronously, so poll briefly.
                ?assertEqual(<<"slave">>, wait_for_replica_role(300))
            end}
            },

            { "a write through qr falls back to the master and succeeds",
            {timeout, 30, fun() ->
                ?assertEqual({ok, <<"OK">>},
                             eredis_cluster:qr(rr_cluster,
                                               ["SET", "rr_write", "v2"])),
                ?assertEqual({ok, <<"v2">>},
                             eredis_cluster:q(rr_cluster, ["GET", "rr_write"]))
            end}
            },

            { "a pipeline with writes through qr falls back to the master",
            {timeout, 30, fun() ->
                ?assertEqual([{ok, <<"OK">>}, {ok, <<"v3">>}],
                             eredis_cluster:qr(rr_cluster,
                                               [["SET", "rr_pipe", "v3"],
                                                ["GET", "rr_pipe"]]))
            end}
            },

            { "replica reads see written data",
            {timeout, 60, fun() ->
                ?assertEqual({ok, <<"OK">>},
                             eredis_cluster:q(rr_cluster,
                                              ["SET", "rr_read", "v4"])),
                %% Replication is asynchronous, and a preceding test may have
                %% triggered failovers that leave replicas mid-resync, so give
                %% the replica ample time to catch up.
                ?assertEqual({ok, <<"v4">>},
                             wait_for_value(["GET", "rr_read"], {ok, <<"v4">>},
                                            1000))
            end}
            }
        ]}
    }.

wait_for_replica_pools(N, Retries) ->
    Pools = eredis_cluster:get_all_replica_pools(rr_cluster),
    case length(Pools) of
        N ->
            Pools;
        _Missing when Retries =:= 0 ->
            {timeout, Pools};
        _Missing ->
            timer:sleep(100),
            State = eredis_cluster_monitor:get_state(rr_cluster),
            Version = eredis_cluster_monitor:get_state_version(State),
            ok = eredis_cluster_monitor:refresh_mapping(rr_cluster, Version),
            wait_for_replica_pools(N, Retries - 1)
    end.

%% A shard whose master has no connected replica answers reads on the master by
%% design, so the probe key must belong to a shard that has one. Replicas are
%% not guaranteed to sit one per shard, and the spread shifts while a cluster
%% settles, so re-pick the key on every attempt rather than hardcoding it.
wait_for_replica_role(0) ->
    timeout;
wait_for_replica_role(Retries) ->
    case key_on_shard_with_replica(64) of
        undefined ->
            retry_replica_role(Retries);
        Key ->
            case eredis_cluster:qrk(rr_cluster, ["ROLE"], Key) of
                {ok, [<<"slave">> | _]} ->
                    <<"slave">>;
                _NotServedByReplicaYet ->
                    retry_replica_role(Retries)
            end
    end.

retry_replica_role(Retries) ->
    timer:sleep(10),
    wait_for_replica_role(Retries - 1).

key_on_shard_with_replica(0) ->
    undefined;
key_on_shard_with_replica(Attempts) ->
    Key = "rr_role_probe_" ++ integer_to_list(Attempts),
    case eredis_cluster:get_replica_pools_by_key(rr_cluster, Key) of
        [_ | _] ->
            Key;
        [] ->
            key_on_shard_with_replica(Attempts - 1)
    end.

wait_for_value(Command, Expected, Retries) ->
    case eredis_cluster:qr(rr_cluster, Command) of
        Expected ->
            Expected;
        Other when Retries =:= 0 ->
            {timeout, Other};
        _Stale ->
            timer:sleep(20),
            wait_for_value(Command, Expected, Retries - 1)
    end.
