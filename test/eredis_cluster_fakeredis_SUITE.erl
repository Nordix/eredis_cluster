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
        , t_pool_full/1
        , t_redis_crash/1
        , t_ask_redirect/1
        , t_pipeline_ask_redirect/1
        , t_moved_redirect/1
        , t_eval_failure_handling/1
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
    ok = eredis_cluster:connect([{"127.0.0.1", 20001}]),

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
    ok = eredis_cluster:connect([{"127.0.0.1", 20001}], Options),

    ct:print("Test access.."),
    ?assertEqual({ok, <<"OK">>}, eredis_cluster:q(["SET", "key", "value"])),
    ?assertEqual({ok, <<"value">>}, eredis_cluster:q(["GET", "key"])),
    ?assertEqual({ok, undefined}, eredis_cluster:q(["GET","nonexists"])),

    ?assertMatch(ok, eredis_cluster:stop()).

t_pool_full(Config) when is_list(Config) ->
    %% Pool size 1 with concurrent queries causes poolboy to return
    %% 'full' and the query is retried until the first workers are
    %% done.

    %% Poolboy's checkout timeout is 5000, so we make sure a worker is
    %% blocked for 6000ms. The time limit for gen_server calls used
    %% for performing a query is 5000 but it's OK to wait longer for
    %% the pool. Thus, we need two workers each taking 3000ms to
    %% block a 3rd worker for 6000ms.

    fakeredis_cluster:start_link([20001, 20002, 20003],
                                 [{delay, 3000}]),

    application:set_env(eredis_cluster, pool_size, 1),
    application:set_env(eredis_cluster, pool_max_overflow, 0),

    ct:print("Perform inital connect..."),
    ok = eredis_cluster:connect([{"127.0.0.1", 20001}]),

    ct:print("Test concurrent access..."),
    MainPid = self(),
    Fun = fun() ->
                  ct:print("Test access from process ~p...", [self()]),
                  ?assertEqual({ok, undefined},
                               eredis_cluster:q(["GET", "dummy"])),
                  ct:print("Access from process ~p is done.", [self()]),
                  MainPid ! done
          end,

    StartTime = erlang:system_time(millisecond),
    spawn(Fun),
    spawn(Fun),
    spawn(Fun),
    receive done -> ok after 10000 -> error(timeout) end,
    receive done -> ok after 10000 -> error(timeout) end,
    receive done -> ok after 10000 -> error(timeout) end,
    EndTime = erlang:system_time(millisecond),

    %% The whole sequence must have taken at least 9
    %% seconds. Otherwise, the delay mechanism in fakeredis doesn't
    %% work.
    ct:print("It took ~p milliseconds.", [EndTime - StartTime]),
    ?assert(EndTime - StartTime >= 9000),

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

t_ask_redirect(Config) when is_list(Config) ->
    Ports = [20001, 20002],
    fakeredis_cluster:start_link(Ports),
    ok = eredis_cluster:connect([{"127.0.0.1", 20001}]),
    {ok, <<"OK">>} = eredis_cluster:q(["SET", "foo", "bar"]),

    %% Now, set up an ASK redirect for foo to the other node.  First
    %% check which node has it already and move it to the other node.
    {moved, _Slot, Address, HomePort} =
        fakeredis_cluster:get_redirect_by_key(<<"foo">>),
    OtherPort = hd([P || P <- Ports, P =/= HomePort]),
    ok = fakeredis_cluster:set_ask_redirect(<<"foo">>, Address, OtherPort),

    %% Check that eredis_cluster can follow the redirect
    ?assertEqual({ok, <<"bar">>},
                 eredis_cluster:q(["GET", "foo"])),

    %% Check that no additional CLUSTER SLOTS or other unexpected
    %% connections or commands were performed.
    EventLog = fakeredis_cluster:get_event_log(),
    [
     %% Get initial slot mapping
     {InitNodeConn, connect, _},
     {InitNodeConn, command, [<<"CLUSTER">>, <<"SLOTS">>]},
     {InitNodeConn, reply, _SlotsMapping},
     {InitNodeConn, disconnect, normal},
     %% Start pools
     {_, connect, _},
     {_, connect, _},
     %% Client sets foo = bar using original slot mapping
     {Conn1, command, [<<"SET">>, <<"foo">>, <<"bar">>]},
     {Conn1, reply, ok},
     %% The ASK redirect is created here.
     {Conn1, command, [<<"GET">>, <<"foo">>]},
     {Conn1, reply, {error, <<"ASK ", _/binary>>}},
     %% The cluster client follows the redirect.
     {Conn2, command, [<<"ASKING">>]},
     {Conn2, reply, ok},
     {Conn2, command, [<<"GET">>, <<"foo">>]},
     {Conn2, reply, <<"bar">>}
    ] = EventLog,

    ?assertNotEqual(Conn1, Conn2),
    ok.

t_pipeline_ask_redirect(Config) when is_list(Config) ->
    Ports = [20001, 20002],
    fakeredis_cluster:start_link(Ports),
    ok = eredis_cluster:connect([{"127.0.0.1", 20001}]),
    {ok, <<"OK">>} = eredis_cluster:q(["SET", "foo", "bar"]),

    %% Now, set up an ASK redirect for foo to the other node.  First
    %% check which node has it already and move it to the other node.
    {moved, _Slot, Address, HomePort} =
        fakeredis_cluster:get_redirect_by_key(<<"foo">>),
    OtherPort = hd([P || P <- Ports, P =/= HomePort]),
    ok = fakeredis_cluster:set_ask_redirect(<<"foo">>, Address, OtherPort),

    %% Check that eredis_cluster can follow the redirect
    ?assertEqual([{ok, <<"bar">>},
                  {ok, <<"OK">>},
                  {ok, <<"baz">>}],
                 eredis_cluster:qp([["GET", "foo"],
                                    ["SET", "foo", "baz"],
                                    ["GET", "foo"]])),

    %% Check that no additional CLUSTER SLOTS or other unexpected
    %% connections or commands were performed.
    EventLog = fakeredis_cluster:get_event_log(),
    [
     %% Inital slot mapping is fetched
     {Conn0, connect, _},
     {Conn0, command, [<<"CLUSTER">>, <<"SLOTS">>]},
     {Conn0, reply, _SlotsMapping},
     {Conn0, disconnect, normal},
     %% Connect pools
     {_, connect, _},
     {_, connect, _},
     {Conn1, command, [<<"SET">>, <<"foo">>, <<"bar">>]},
     {Conn1, reply, ok},
     %% Here, the ASK redirect is created.
     {Conn1, command, [<<"GET">>, <<"foo">>]},
     {Conn1, reply, {error, <<"ASK ", _/binary>>}},
     {Conn1, command, [<<"SET">>, <<"foo">>, <<"baz">>]},
     {Conn1, reply, {error, <<"ASK ", _/binary>>}},
     {Conn1, command, [<<"GET">>,<<"foo">>]},
     {Conn1, reply, {error, <<"ASK ", _/binary>>}},
     %% Now, the pipeline is sent to the other node.
     {Conn2, command, [<<"ASKING">>]},
     {Conn2, reply, ok},
     {Conn2, command, [<<"GET">>, <<"foo">>]},
     {Conn2, reply, <<"bar">>},
     {Conn2, command, [<<"ASKING">>]},
     {Conn2, reply, ok},
     {Conn2, command, [<<"SET">>, <<"foo">>, <<"baz">>]},
     {Conn2, reply, ok},
     {Conn2, command, [<<"ASKING">>]},
     {Conn2, reply, ok},
     {Conn2, command, [<<"GET">>,<<"foo">>]},
     {Conn2, reply, <<"baz">>}
    ] = EventLog,
    ?assertNotEqual(Conn1, Conn2),
    ok.

t_moved_redirect(Config) when is_list(Config) ->
    Ports = [20001, 20002],
    %% Make CLUSTER SLOTS a bit slower than other commands
    Options = [{delay, #{<<"CLUSTER">> => 200}}],
    fakeredis_cluster:start_link(Ports, Options),
    ok = eredis_cluster:connect([{"127.0.0.1", 20001}]),
    {ok, <<"OK">>} = eredis_cluster:q(["SET", "foo", "bar"]),

    %% Now, move "foo" to the other node.
    fakeredis_cluster:move_all_slots(),

    %% Check that eredis_cluster can follow the redirect in a pipeline
    ?assertEqual([{ok, <<"bar">>},
                  {ok, <<"OK">>},
                  {ok, <<"baz">>}],
                 eredis_cluster:qp([["GET", "foo"],
                                    ["SET", "foo", "baz"],
                                    ["GET", "foo"]])),

    %% Wait for the slow asyncronous CLUSTER SLOTS to complete.
    timer:sleep(300),

    EventLog = fakeredis_cluster:get_event_log(),
    [
     %% Inital slot mapping is fetched
     {Conn0, connect, _},
     {Conn0, command, [<<"CLUSTER">>, <<"SLOTS">>]},
     {Conn0, reply, _SlotsMapping},
     {Conn0, disconnect, normal},
     %% Connect pools
     {_, connect, _},
     {_, connect, _},
     {Conn1, command, [<<"SET">>, <<"foo">>, <<"bar">>]},
     {Conn1, reply, ok},
     %% Here, the slot is moved.
     {Conn1, command, [<<"GET">>, <<"foo">>]},
     {Conn1, reply, {error, <<"MOVED ", _/binary>>}},
     {Conn1, command, [<<"SET">>, <<"foo">>, <<"baz">>]},
     {Conn1, reply, {error, <<"MOVED ", _/binary>>}},
     {Conn1, command, [<<"GET">>,<<"foo">>]},
     {Conn1, reply, {error, <<"MOVED ", _/binary>>}},
     %% Now, the pipeline is sent to the other node.
     {Conn2, command, [<<"GET">>, <<"foo">>]},
     {Conn2, reply, <<"bar">>},
     {Conn2, command, [<<"SET">>, <<"foo">>, <<"baz">>]},
     {Conn2, reply, ok},
     {Conn2, command, [<<"GET">>,<<"foo">>]},
     {Conn2, reply, <<"baz">>},
     %% The slot mapping is refreshed asynchronously, using an
     %% existing connection. Since we have added a delay for CLUSTER
     %% commands, it appears after all the GET and SET commands, i.e.
     %% the redirects were followed without waiting for the slot
     %% mappings to be refreshed.
     {_, command, [<<"CLUSTER">>, <<"SLOTS">>]},
     {_, reply, _UpdatedSlotsMapping}
    ] = EventLog,
    ?assertNotEqual(Conn1, Conn2),
    ok.

t_eval_failure_handling(Config) when is_list(Config) ->
    %% eval consists of two steps, first an EVALSHA that tries to run an already loaded script, if that
    %% fails it loads the script via SCRIPT LOAD.
    %% This testcase triggers a socket disconnection right before the script loading.
    Port = 20011,
    fakeredis_cluster:start_link([Port]),
    ok = eredis_cluster:connect([{"127.0.0.1", Port}]),

    Script = <<"return redis.call('SET', KEYS[1], ARGV[1]);">>,
    ScriptHash = << << if N >= 10 -> N -10 + $a; true -> N + $0 end >> || <<N:4>> <= crypto:hash(sha, Script) >>,
    Key = "evalkey",

    Slot = fakeredis_hash:hash(Key),
    {_, Port} = fakeredis_cluster:get_node_by_slot(Slot),
    fakeredis_cluster:kill_node_on_command(Port, <<"SCRIPT">>),
    ?assertMatch({error, no_connection}, eredis_cluster:eval(Script, ScriptHash, [Key], ["value"])),
    ok.
