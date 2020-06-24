-module(eredis_cluster_fakeredis_SUITE).

%% Test framework
-export([ init_per_testcase/2
        , end_per_testcase/2
        , all/0
        , suite/0
        ]).

%% Test cases
-export([ t_connect/1
        , t_connect_tls/1
        , t_redis_crash/1
        ]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

init_per_testcase(_Name, Config) ->
    {ok, _} = application:ensure_all_started(fakeredis_cluster),
    {ok, _} = application:ensure_all_started(eredis_cluster),
    Config.

end_per_testcase(_Name, _Config) ->
    application:stop(eredis_cluster),
    application:stop(fakeredis_cluster),
    ok.

all() -> [F || {F, _A} <- module_info(exports),
               case atom_to_list(F) of
                   "t_" ++ _ -> true;
                   _         -> false
               end].

suite() -> [{timetrap, {minutes, 5}}].

%% Test

t_connect(Config) when is_list(Config) ->
    fakeredis_cluster:start_link([20001, 20002, 20003]),

    ct:print("Perform inital connect..."),
    ?assertMatch(ok, eredis_cluster:connect([{"127.0.0.1", 20001}])),

    ct:print("Test access.."),
    ?assertEqual({ok, <<"OK">>}, eredis_cluster:q(["SET", "key", "value"])),
    ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET", "key"])),
    ?assertEqual({ok, undefined}, eredis_cluster:q(["GET","nonexists"])),

    ?assertMatch(ok, eredis_cluster:stop()).

t_connect_tls(Config) when is_list(Config) ->
    Dir = filename:join([code:priv_dir(eredis_cluster), "configs", "tls"]),
    ServerOptions = [{tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                            {certfile,   filename:join([Dir, "redis.crt"])},
                            {keyfile,    filename:join([Dir, "redis.key"])},
                            {verify,     verify_peer}]}],
    fakeredis_cluster:start_link([20001, 20002, 20003], ServerOptions),

    ct:print("Perform inital connect..."),
    Options = [{tls, [{cacertfile, filename:join([Dir, "ca.crt"])},
                      {certfile,   filename:join([Dir, "client.crt"])},
                      {keyfile,    filename:join([Dir, "client.key"])},
                      {verify,                 verify_peer},
                      {server_name_indication, "Server"}]}],
    ?assertMatch(ok, eredis_cluster:connect([{"127.0.0.1", 20001}], Options)),

    ct:print("Test access.."),
    ?assertEqual({ok, <<"OK">>}, eredis_cluster:q(["SET", "key", "value"])),
    ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET", "key"])),
    ?assertEqual({ok, undefined}, eredis_cluster:q(["GET","nonexists"])),

    ?assertMatch(ok, eredis_cluster:stop()).

t_redis_crash(Config) when is_list(Config) ->
    ok.
%%     fakeredis_cluster:start_link([20001, 20002, 20003]),

%%     ct:print("Perform inital connect..."),
%%     ?assertMatch(ok, eredis_cluster:connect([{"127.0.0.1", 20001}])),

%%     ct:print("Test access.."),
%%     ?assertEqual({ok, <<"OK">>}, eredis_cluster:q(["SET", "key", "value"])),
%%     ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET", "key"])),
%%     ?assertEqual({ok, undefined}, eredis_cluster:q(["GET","nonexists"])),

%%     %% Kill FakeRedis instance
%%     fakeredis_cluster:kill_instance(20003),

%%     ct:print("Test access.."),
%%     ?assertEqual({ok, <<"OK">>}, eredis_cluster:q(["SET", "key", "value"])),
%%     ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET", "key"])),
%%     ?assertEqual({ok, undefined}, eredis_cluster:q(["GET","nonexists"])),

%%     %% Restart FakeRedis instance
%%     fakeredis_cluster:start_instance(20003),

%%     ct:print("Test access.."),
%%     ?assertEqual({ok, <<"OK">>}, eredis_cluster:q(["SET", "key", "value"])),
%%     ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET", "key"])),
%%     ?assertEqual({ok, undefined}, eredis_cluster:q(["GET","nonexists"])),

%%     ?assertMatch(ok, eredis_cluster:stop()).
