-module(eredis_cluster_tls_tests).

-include_lib("eunit/include/eunit.hrl").

connect_test() ->
    application:set_env(eredis_cluster, init_nodes, []),
    ?assertMatch(ok, eredis_cluster:start()),
    Dir = filename:join([code:lib_dir(eredis_cluster), "test", "tls"]),
    Options = [{tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                      {certfile,   filename:join([Dir, "client.crt"])},
                      {keyfile,    filename:join([Dir, "client.key"])}]}],
    Res = eredis_cluster:connect([{"127.0.0.1", 31001},
                                  {"127.0.0.1", 31002}], Options),
    ?assertMatch(ok, Res),
    ?assertMatch(ok, eredis_cluster:stop()).

get_set_test() ->
    application:set_env(eredis_cluster, init_nodes, []),
    ?assertMatch(ok, eredis_cluster:start()),
    Dir = filename:join([code:lib_dir(eredis_cluster), "test", "tls"]),
    Options = [{tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                      {certfile,   filename:join([Dir, "client.crt"])},
                      {keyfile,    filename:join([Dir, "client.key"])}]}],
    Res = eredis_cluster:connect([{"127.0.0.1", 31001},
                                  {"127.0.0.1", 31002}], Options),
    ?assertMatch(ok, Res),

    ?assertEqual({ok, <<"OK">>}, eredis_cluster:q(["SET", "key", "value"])),
    ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET","key"])),
    ?assertEqual({ok, undefined}, eredis_cluster:q(["GET","nonexists"])),

    ?assertMatch(ok, eredis_cluster:stop()).
