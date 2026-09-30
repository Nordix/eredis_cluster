-module(eredis_cluster_multicluster_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("eredis_cluster/include/eredis_cluster.hrl").

tls_options() ->
    Dir = filename:join([code:priv_dir(eredis_cluster), "configs", "tls"]),
    [{tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
            {certfile, filename:join([Dir, "client.crt"])},
            {keyfile, filename:join([Dir, "client.key"])},
            {verify, verify_peer},
            {server_name_indication, "Server"}]}].

explicit_cluster_test() ->
    application:set_env(eredis_cluster, init_nodes, []),
    ?assertMatch(ok, eredis_cluster:start()),

    %% No implicitly started default cluster
    ?assertEqual([], supervisor:which_children(eredis_cluster_sup_sup)),

    ok = eredis_cluster:connect(mycluster,
                                [{"127.0.0.1", 31001},
                                 {"127.0.0.1", 31002}],
                                tls_options()),
    ?assertEqual({ok, <<"OK">>},
                 eredis_cluster:q(mycluster, ["SET", "foo", "bar"])),
    ?assertEqual({ok, <<"bar">>},
                 eredis_cluster:q(mycluster, ["GET", "foo"])),
    ok = eredis_cluster:disconnect(mycluster),
    ?assertMatch(ok, eredis_cluster:stop()).

explicit_and_default_cluster_test() ->
    application:set_env(eredis_cluster, init_nodes, [{"127.0.0.1", 30001},
                                                     {"127.0.0.1", 30002}]),
    ?assertMatch(ok, eredis_cluster:start()),
    ok = eredis_cluster:connect(mycluster,
                                [{"127.0.0.1", 31001},
                                 {"127.0.0.1", 31002}],
                                tls_options()),

    %% Both clusters are non-empty and no overlap
    Cluster1Nodes = eredis_cluster:get_all_pools(),
    Cluster2Nodes = eredis_cluster:get_all_pools(mycluster),
    ?assertMatch([_|_], Cluster1Nodes),
    ?assertMatch([_|_], Cluster2Nodes),
    ?assertEqual(Cluster1Nodes, Cluster1Nodes -- Cluster2Nodes),
    ?assertEqual(Cluster2Nodes, Cluster2Nodes -- Cluster1Nodes),

    %% Independent values in different clusters
    ?assertEqual({ok, <<"OK">>},
                 eredis_cluster:qk(["SET", "foo", "bar"], "foo")),
    ?assertEqual({ok, <<"OK">>},
                 eredis_cluster:qk(mycluster, ["SET", "foo", "baz"], "foo")),
    ?assertEqual({ok, <<"bar">>},
                 eredis_cluster:q(["GET", "foo"])),
    ?assertEqual({ok, <<"baz">>},
                 eredis_cluster:q(mycluster, ["GET", "foo"])),

    %% Disconnect explicit cluster doesn't affect default cluster
    ok = eredis_cluster:disconnect(mycluster),
    ?assertEqual({ok, <<"bar">>},
                 eredis_cluster:q(["GET", "foo"])),

    ?assertMatch(ok, eredis_cluster:stop()).

same_nodes_clusters_test() ->
    application:set_env(eredis_cluster, init_nodes, []),
    ?assertMatch(ok, eredis_cluster:start()),
    ok = eredis_cluster:connect(cluster_a, [{"127.0.0.1", 30001}], []),
    ok = eredis_cluster:connect(cluster_b, [{"127.0.0.1", 30001}], []),

    %% Clusters connected to the same nodes don't share pools
    ClusterAPools = eredis_cluster:get_all_pools(cluster_a),
    ClusterBPools = eredis_cluster:get_all_pools(cluster_b),
    ?assertMatch([_|_], ClusterAPools),
    ?assertMatch([_|_], ClusterBPools),
    ?assertEqual(ClusterAPools, ClusterAPools -- ClusterBPools),
    ?assertEqual(ClusterBPools, ClusterBPools -- ClusterAPools),

    ?assertEqual({ok, <<"OK">>},
                 eredis_cluster:q(cluster_a, ["SET", "foo", "bar"])),
    ?assertEqual({ok, <<"bar">>},
                 eredis_cluster:q(cluster_b, ["GET", "foo"])),

    %% Disconnecting a cluster doesn't affect the other one
    ok = eredis_cluster:disconnect(cluster_a),
    ?assertEqual({ok, <<"bar">>},
                 eredis_cluster:q(cluster_b, ["GET", "foo"])),

    ok = eredis_cluster:disconnect(cluster_b),
    ?assertMatch(ok, eredis_cluster:stop()).
