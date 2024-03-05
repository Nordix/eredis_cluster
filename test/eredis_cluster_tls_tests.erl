-module(eredis_cluster_tls_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("eredis_cluster/include/eredis_cluster.hrl").

connect_test() ->
    application:set_env(eredis_cluster, init_nodes, []),
    ?assertMatch(ok, eredis_cluster:start()),
    Dir = filename:join([code:priv_dir(eredis_cluster), "configs", "tls"]),
    Options = [{tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                      {certfile,   filename:join([Dir, "client.crt"])},
                      {keyfile,    filename:join([Dir, "client.key"])},
                      {verify,                 verify_peer},
                      {server_name_indication, "Server"}]}],
    ok = eredis_cluster:connect([{"127.0.0.1", 31001},
                                 {"127.0.0.1", 31002}], Options),
    ?assertMatch(ok, eredis_cluster:stop()).

get_set_test() ->
    start(),
    connect_tls(),

    ?assertEqual({ok, <<"OK">>}, eredis_cluster:q(["SET", "key", "value"])),
    ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET", "key"])),
    ?assertEqual({ok, undefined}, eredis_cluster:q(["GET","nonexists"])),

    ?assertMatch(ok, eredis_cluster:stop()).

options_override_test() ->
    start(),

    %% Application configs has a faulty cert
    application:set_env(eredis_cluster, tls, [{cacertfile, "faulty.crt"},
                                              {certfile,   "faulty.crt"},
                                              {keyfile,    "faulty.key"}]),

    %% Connect using a correct cert via connect/2
    Dir = filename:join([code:priv_dir(eredis_cluster), "configs", "tls"]),
    Options = [{tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                      {certfile,   filename:join([Dir, "client.crt"])},
                      {keyfile,    filename:join([Dir, "client.key"])}]}],
    ok = eredis_cluster:connect([{"127.0.0.1", 31001},
                                 {"127.0.0.1", 31002}], Options),

    Key = "Key123",
    ?assertEqual({ok, <<"OK">>}, eredis_cluster:q(["SET", Key, "value"])),
    ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET", Key])),

    ?assertMatch(ok, eredis_cluster:stop()).

options_changed_test() ->
    start(),
    connect_tls(),
    Key = "Key123",
    ?assertEqual({ok, <<"OK">>}, eredis_cluster:q(["SET", Key, "value"])),
    ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET", Key])),

    %% Change TLS options via setenv
    Dir = filename:join([code:priv_dir(eredis_cluster), "configs", "tls"]),
    application:set_env(eredis_cluster, tls, [{cacertfile, filename:join([Dir, "faulty.crt"])},
                                              {certfile,   filename:join([Dir, "faulty.crt"])},
                                              {keyfile,    filename:join([Dir, "faulty.key"])}]),

    State = eredis_cluster_monitor:get_state(?default_cluster),
    Version = eredis_cluster_monitor:get_state_version(State),
    eredis_cluster_monitor:refresh_mapping(?default_cluster, Version),

    %% Change back
    Dir = filename:join([code:priv_dir(eredis_cluster), "configs", "tls"]),
    application:set_env(eredis_cluster, tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                                              {certfile,   filename:join([Dir, "client.crt"])},
                                              {keyfile,    filename:join([Dir, "client.key"])}]),

    State = eredis_cluster_monitor:get_state(?default_cluster),
    Version = eredis_cluster_monitor:get_state_version(State),
    eredis_cluster_monitor:refresh_mapping(?default_cluster, Version),

    ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET", Key])),

    ?assertMatch(ok, eredis_cluster:stop()).

start() ->
    application:unset_env(eredis_cluster, init_nodes),
    application:unset_env(eredis_cluster, password),
    ?assertMatch(ok, eredis_cluster:start()).

connect_tls() ->
    Dir = filename:join([code:priv_dir(eredis_cluster), "configs", "tls"]),
    application:set_env(eredis_cluster, tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                                              {certfile,   filename:join([Dir, "client.crt"])},
                                              {keyfile,    filename:join([Dir, "client.key"])}]),
    ok = eredis_cluster:connect([{"127.0.0.1", 31001},
                                 {"127.0.0.1", 31002}]).
