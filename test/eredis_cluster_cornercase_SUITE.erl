-module(eredis_cluster_cornercase_SUITE).

-export([init_per_testcase/2, end_per_testcase/2,
         all/0]).

-export([update_key_some_retries_fail/1,
         update_key_all_retries_fail/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("eredis_cluster.hrl").

all() ->
    [update_key_all_retries_fail,
     update_key_some_retries_fail].

init_per_testcase(_Tc, Config) ->
    {ok, ListenSocket} = gen_tcp:listen(0, [binary, {active, false}]),
    {ok, {_, Port}} = inet:sockname(ListenSocket),
    ok = application:start(eredis_cluster),
    spawn_link(fun() ->
                       eredis_cluster:connect([{"127.0.0.1", Port}],
                                              [{pool_size, 1},
                                               {pool_max_overflow, 0}])
               end),
    handler_cluster_slots_connection(ListenSocket),
    {ok, Socket} = gen_tcp:accept(ListenSocket, 5000),
    [{socket, Socket}, {listen_socket, ListenSocket} | Config].

end_per_testcase(_Tc, Config) ->
    application:stop(eredis_cluster),
    gen_tcp:close(proplists:get_value(listen_socket, Config)),
    gen_tcp:close(proplists:get_value(socket, Config)).
    
update_key_some_retries_fail([{socket, Socket} | _Config]) ->
    %% Spawn server simulator
    spawn_link(fun () -> update_key_some_retries_fail_server(Socket) end),
    %% Client code
    Res = eredis_cluster:update_key("foo",
                                    fun(Bin) ->
                                            N = binary_to_integer(Bin),
                                            integer_to_binary(N + 1)
                                    end),
    ?assertEqual({ok, <<"5">>}, Res).

%% Server communication for TC update_key_some_retries_fail
update_key_some_retries_fail_server(Sock) ->
    handle_watch_get_multi_set_exec(Sock, <<"foo">>, <<"1">>, <<"2">>, fail),
    handle_watch_get_multi_set_exec(Sock, <<"foo">>, <<"2">>, <<"3">>, fail),
    handle_watch_get_multi_set_exec(Sock, <<"foo">>, <<"3">>, <<"4">>, fail),
    handle_watch_get_multi_set_exec(Sock, <<"foo">>, <<"4">>, <<"5">>, pass).

update_key_all_retries_fail([{socket, Socket} | _Config]) ->
    %% Spawn server simulator
    spawn_link(fun () -> update_key_all_retries_fail_server(Socket) end),
    %% Client code
    Res = eredis_cluster:update_key("foo",
                                    fun(Bin) ->
                                            N = binary_to_integer(Bin),
                                            integer_to_binary(N + 1)
                                    end),
    ?assertEqual({error, resource_busy}, Res),
    ok.

%% Server communication for TC update_key_all_retries_fail
update_key_all_retries_fail_server(Sock) ->
    lists:foreach(fun (N) ->
                          Get = integer_to_binary(N),
                          ExpectSet = integer_to_binary(N + 1),
                          handle_watch_get_multi_set_exec(Sock, <<"foo">>,
                                                          Get, ExpectSet, fail)
                  end,
                  lists:seq(1, ?OL_TRANSACTION_TTL + 1)).

handle_watch_get_multi_set_exec(Sock, Key, GetValue, ExpectSet, FailOrPass) ->
    {ok, WatchKey} = gen_tcp:recv(Sock, 0),
    ?assertEqual(enc([<<"WATCH">>, Key]), WatchKey),
    ok = gen_tcp:send(Sock, <<"+OK\r\n">>),
    {ok, Get} = gen_tcp:recv(Sock, 0),
    ?assertEqual(enc([<<"GET">>, Key]), Get),
    ok = gen_tcp:send(Sock, enc(GetValue)),
    Multi = enc([<<"MULTI">>]),
    {ok, Multi} = gen_tcp:recv(Sock, byte_size(Multi)),
    ok = gen_tcp:send(Sock, <<"+OK\r\n">>),
    Set = enc([<<"SET">>, <<"foo">>, ExpectSet]),
    {ok, Set} = gen_tcp:recv(Sock, byte_size(Set)),
    ok = gen_tcp:send(Sock, <<"+QUEUED\r\n">>),
    {ok, Exec} = gen_tcp:recv(Sock, 0),
    ?assertEqual(enc([<<"EXEC">>]), Exec),
    ExecResponse = case FailOrPass of
                       fail -> <<"$-1\r\n">>;
                       pass -> <<"*1\r\n+OK\r\n">>
                   end,
    ok = gen_tcp:send(Sock, ExecResponse).

%% Accepts a connection, handles CLUSTER SLOTS and waits for client to close.
handler_cluster_slots_connection(ListenSocket) ->
    {ok, ClientSocket} = gen_tcp:accept(ListenSocket, 5000),
    try
        handle_cluster_slots(ClientSocket),
        {error, closed} = gen_tcp:recv(ClientSocket, 0)
    after
        gen_tcp:close(ClientSocket)
    end.

%% Receives CLUSTER SLOTS and replies with mapping all slots to this node.
handle_cluster_slots(Sock) ->
    {ok, {_, Port}} = inet:sockname(Sock),
    {ok, ClusterSlotsCmd} = gen_tcp:recv(Sock, 0),
    ?assertEqual(enc([<<"CLUSTER">>, <<"SLOTS">>]), ClusterSlotsCmd),
    Slots = [[0, 16383, [<<"127.0.0.1">>, Port, <<"asdfijisdjf">>]]],
    ok = gen_tcp:send(Sock, enc(Slots)).

%% Minimalistic incomplete Redis encoder (array, bulk string, integer)
enc(Data) ->
    enc(Data, <<>>).

enc(Array, Acc) when is_list(Array) ->
    Acc1 = <<Acc/binary, "*", (integer_to_binary(length(Array)))/binary, "\r\n">>,
    lists:foldl(fun enc/2, Acc1, Array);
enc(Bulk, Acc) when is_binary(Bulk) ->
    <<Acc/binary, "$", (integer_to_binary(byte_size(Bulk)))/binary, "\r\n",
      Bulk/binary, "\r\n">>;
enc(Integer, Acc) when is_integer(Integer) ->
    <<Acc/binary, ":", (integer_to_binary(Integer))/binary, "\r\n">>.
