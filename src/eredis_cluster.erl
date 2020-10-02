-module(eredis_cluster).
-behaviour(application).

%% Application
-export([start/0, stop/0]).
%% Application callback
-export([start/2, stop/1]).

%% Management
-export([connect/1, connect/2, disconnect/1]).

% Generic redis call
-export([q/1, qk/2, q_noreply/1, qp/1, qa/1, qa2/1, qw/2, qmn/1]).
-export([transaction/1, transaction/2]).

% Specific redis command implementation
-export([flushdb/0, load_script/1, scan/4]).

 % Helper functions
-export([update_key/2]).
-export([update_hash_field/3]).
-export([optimistic_locking_transaction/3]).
-export([eval/4]).
-export([get_pool_by_command/1, get_pool_by_key/1]).

-ifdef(TEST).
-export([get_key_slot/1]).
-endif.

-include("eredis_cluster.hrl").

%% @doc Start application.
-spec start() -> ok | {error, Reason::term()}.
start() ->
    application:start(?MODULE).

%% @doc Stop application.
-spec stop() -> ok | {error, Reason::term()}.
stop() ->
    application:stop(?MODULE).


%% @doc Application behaviour callback
-spec start(StartType::application:start_type(), StartArgs::term()) ->
    {ok, pid()}.
start(_Type, _Args) ->
    eredis_cluster_sup:start_link().

%% @doc Application behaviour callback
-spec stop(State::term()) -> ok.
stop(_State) ->
    ok.

%% =============================================================================
%% @doc Connect to a set of init nodes, useful if the cluster configuration is
%% not known at startup
%% @end
%% =============================================================================
-spec connect(InitServers::term()) -> Result::term().
connect(InitServers) ->
    connect(InitServers, []).

-spec connect(InitServers::term(), Options::options()) -> Result::term().
connect(InitServers, Options) ->
    eredis_cluster_monitor:connect(InitServers, Options).

%% =============================================================================
%% @doc Disconnect with a set of nodes.
%% @end
%% =============================================================================
-spec disconnect(PoolNodes::term()) -> Result::term().
disconnect(PoolNodes) ->
    eredis_cluster_monitor:disconnect(PoolNodes).

%% =============================================================================
%% @doc This function execute simple or pipelined command on a single redis node
%% the node will be automatically found according to the key used in the command
%% @end
%% =============================================================================
-spec q(Command::redis_command()) -> redis_result().
q(Command) ->
    query(Command).

-spec qk(Command::redis_command(), PoolKey::bitstring()) -> redis_result().
qk(Command, PoolKey) ->
    query(Command, PoolKey).

%% =============================================================================
%% @doc Execute simple or pipelined commands on a single Redis node, but
%% ignoring any response from Redis. (Fire and forget)
%% @end
%% =============================================================================
-spec q_noreply(Command::redis_command()) -> ok.
q_noreply(Command) ->
    PoolKey = get_key_from_command(Command),
    query_noreply(Command, PoolKey).

%% =============================================================================
%% @doc Wrapper function for command using pipelined commands
%% @end
%% =============================================================================
-spec qp(Commands::redis_pipeline_command()) -> redis_pipeline_result().
qp(Commands) -> q(Commands).

%% =============================================================================
%% @doc Perform a given query on all node of a redis cluster
%% When a query to a master fail refresh the mapping and try again.
%% @end
%% =============================================================================
-spec qa(Command::redis_command()) -> [redis_transaction_result()] | {error, no_connection}.
qa(Command) -> qa(Command, 0, []).

qa(_, ?REDIS_CLUSTER_REQUEST_TTL, Res) ->
    case Res of
        [] -> {error, no_connection};
        _  -> Res
    end;
qa(Command, Counter, Res) ->
    throttle_retries(Counter),

    State = eredis_cluster_monitor:get_state(),
    Version = eredis_cluster_monitor:get_state_version(State),
    Pools = eredis_cluster_monitor:get_all_pools(State),
    case Pools of
        [] ->
            eredis_cluster_monitor:refresh_mapping(Version),
            qa(Command, Counter + 1, Res);
        _ ->
            Transaction = fun(Worker) -> qw(Worker, Command) end,
            Results = [eredis_cluster_pool:transaction(Pool, Transaction) ||
                         Pool <- Pools],
            case handle_transaction_result(Results, Version)
            of
                retry  -> qa(Command, Counter + 1, Results);
                Result -> Result
            end
    end.

%% =============================================================================
%% @doc Perform a given query on all master nodes of a redis cluster and
%% return result with master node reference in result.
%% When a query to the master fail refresh the mapping and try again.
%% @end
%% =============================================================================
-spec qa2(Command::redis_command()) -> [{atom(), redis_result()}] | {error, no_connection}.
qa2(Command) -> qa2(Command, 0, []).

qa2(_, ?REDIS_CLUSTER_REQUEST_TTL, Res) ->
    case Res of
        [] -> {error, no_connection};
        _  -> Res
    end;
qa2(Command, Counter, Res) ->
    throttle_retries(Counter),

    State = eredis_cluster_monitor:get_state(),
    Version = eredis_cluster_monitor:get_state_version(State),
    Pools = eredis_cluster_monitor:get_all_pools(State),
    case Pools of
        [] ->
            eredis_cluster_monitor:refresh_mapping(Version),
            qa2(Command, Counter + 1, Res);
        _ ->
            Transaction = fun(Worker) -> qw(Worker, Command) end,
            Result = [{Pool, eredis_cluster_pool:transaction(Pool, Transaction)} ||
                         Pool <- Pools],
            Tmp = lists:foldl(
                    fun({_P, TR}, Acc) ->
                            case handle_transaction_result(TR, Version)
                            of
                                retry -> [retry|Acc];
                                _     -> Acc
                            end
                    end, [], Result),
            case lists:member(retry, Tmp) of
                true ->
                    qa2(Command, Counter + 1, Result);
                false ->
                    Result
            end
    end.

%% =============================================================================
%% @doc Wrapper function to be used for direct call to a pool worker in the
%% function passed to the transaction/2 method
%% @end
%% =============================================================================
-spec qw(Worker::pid(), redis_command()) -> redis_result().
qw(Worker, [[X|_]|_] = Commands) when is_list(X); is_binary(X) ->
    eredis:qp(Worker, Commands);

qw(Worker, Command) ->
    eredis:q(Worker, Command).

-spec qw_noreply(Worker::pid(), Command::redis_command()) -> ok.
qw_noreply(Worker, Command) ->
    eredis:q_noreply(Worker, Command).

%% =============================================================================
%% @doc Wrapper function to execute a pipeline command as a transaction Command
%% (it will add MULTI and EXEC command)
%% @end
%% =============================================================================
-spec transaction(Commands::redis_pipeline_command()) -> redis_transaction_result().
transaction(Commands) ->
    Result = q([["multi"]| Commands] ++ [["exec"]]),
    case is_list(Result) of
        true ->
            lists:last(Result);
        false ->
             Result %% Like {error, no_connection}
    end.

%% =============================================================================
%% @doc Multi node query. Each command in a list of commands is sent
%% to the Redis node responsible for the key affected by that
%% command. Only simple commands operating on a single key are supported.
%% @end
%% =============================================================================
-spec qmn(Commands::redis_pipeline_command()) -> redis_pipeline_result().
qmn(Commands) -> qmn(Commands, 0).

qmn(_, ?REDIS_CLUSTER_REQUEST_TTL) ->
    {error, no_connection};
qmn(Commands, Counter) ->
    throttle_retries(Counter),

    %% TODO: Implement ASK redirects for qmn.

    {CommandsByPools, MappingInfo, Version} = split_by_pools(Commands),
    case qmn2(CommandsByPools, MappingInfo, [], Version) of
        retry -> qmn(Commands, Counter + 1);
        Res -> Res
    end.

qmn2([{Pool, PoolCommands} | T1], [{Pool, Mapping} | T2], Acc, Version) ->
    Transaction = fun(Worker) -> qw(Worker, PoolCommands) end,
    Result = eredis_cluster_pool:transaction(Pool, Transaction),
    case handle_transaction_result(Result, Version) of
        retry -> retry;
        Res ->
            MappedRes = lists:zip(Mapping, Res),
            qmn2(T1, T2, MappedRes ++ Acc, Version)
    end;
qmn2([], [], Acc, _) ->
    SortedAcc =
        lists:sort(
            fun({Index1, _}, {Index2, _}) ->
                Index1 < Index2
            end, Acc),
    [Res || {_, Res} <- SortedAcc].

%% =============================================================================
%% @doc Execute a function on a pool worker. This function should be use when
%% transaction method such as WATCH or DISCARD must be used. The pool used to
%% execute the transaction is specified by giving a key that this pool is
%% containing.
%% @end
%% =============================================================================
-spec transaction(Transaction::fun((Worker::pid()) -> redis_result()),
                  PoolKey::bitstring()) -> any().
transaction(Transaction, PoolKey) ->
    Slot = get_key_slot(PoolKey),
    transaction(Transaction, Slot, undefined, 0).

%% FIXME: There's no base case for the counter, so it may loop forever.
transaction(Transaction, Slot, undefined, _) ->
    transaction_retry_loop(Transaction, Slot, 0);
transaction(Transaction, Slot, ExpectedValue, Counter) ->
    case transaction_retry_loop(Transaction, Slot, 0) of
        ExpectedValue ->
            transaction(Transaction, Slot, ExpectedValue, Counter - 1);
        {ExpectedValue, _} ->
            transaction(Transaction, Slot, ExpectedValue, Counter - 1);
        Payload ->
            Payload
    end.

%% Helper for transaction/2,4 with retries and backoff like query/3.
-spec transaction_retry_loop(Transaction  :: fun((Worker :: pid() | atom()) -> redis_result()),
                             Slot         :: 0..16383,
                             RetryCounter :: 0..?REDIS_CLUSTER_REQUEST_TTL) ->
          redis_result().
transaction_retry_loop(_, _, ?REDIS_CLUSTER_REQUEST_TTL) ->
    {error, no_connection};
transaction_retry_loop(Transaction, Slot, Counter) ->
    throttle_retries(Counter),
    {Pool, Version} = eredis_cluster_monitor:get_pool_by_slot(Slot),
    Result = eredis_cluster_pool:transaction(Pool, Transaction),
    case handle_transaction_result(Result, Version) of
        retry -> transaction_retry_loop(Transaction, Slot, Counter + 1);
        Result -> Result
    end.

%% =============================================================================
%% @doc Perform flushdb command on each node of the redis cluster
%% @end
%% =============================================================================
-spec flushdb() -> ok | {error, Reason::bitstring()}.
flushdb() ->
    case qa(["FLUSHDB"]) of
        Result when is_list(Result) ->
            case proplists:lookup(error, Result) of
                none  -> ok;
                Error -> Error
            end;
        Result -> Result
    end.

%% =============================================================================
%% @doc Load LUA script to all master nodes in the Redis cluster.
%% @end
%% =============================================================================
-spec load_script(Script::string()) -> redis_result().
load_script(Script) ->
    Command = ["SCRIPT", "LOAD", Script],
    case qa(Command) of
        Result when is_list(Result) ->
            case proplists:lookup(error, Result) of
                none ->
                    [{ok, SHA1}|_] = Result,
                    {ok,  SHA1};
                Error ->
                    Error
            end;
        Result ->
            Result
    end.

%% =============================================================================
%% @doc Perform scan command on a specific node in the Redis cluster.
%% @end
%% =============================================================================
-spec scan(PoolName::atom(), Cursor::integer(), Pattern::string(), Count::integer())
          -> redis_result() | {error, Reason::bitstring()}.
scan(PoolName, Cursor, Pattern, Count) when is_list(Pattern) ->
    scan(PoolName, Cursor, Pattern, Count, 0).

scan(_, _, _, _, ?REDIS_CLUSTER_REQUEST_TTL) ->
    {error, no_connection};
scan(PoolName, Cursor, Pattern, Count, RetryCounter) ->
    throttle_retries(RetryCounter),

    Command = ["scan", Cursor, "match", Pattern, "count", Count],
    Transaction = fun(Worker) -> qw(Worker, Command) end,
    Result = eredis_cluster_pool:transaction(PoolName, Transaction),

    State = eredis_cluster_monitor:get_state(),
    Version = eredis_cluster_monitor:get_state_version(State),
    case handle_transaction_result(Result, Version) of
        retry -> scan(PoolName, Cursor, Pattern, Count, RetryCounter + 1);
        Result -> Result
    end.

%% =============================================================================

%% Partition a list of commands by the node each command belongs to.
%%
%% Returns {CommandsByPools, MappingInfo, Version} where
%%
%%   CommandsByPools = [{Pool1, [Command1, Command2, ...]},
%%                      {Pool2, CommandsPool2}, ...]
%%   MappingInfo     = [{Pool1, [Command1Position, Command2Position, ...]},
%%                      {Pool2, CommandsPool2Positions}, ...]
split_by_pools(Commands) ->
    State = eredis_cluster_monitor:get_state(),
    split_by_pools(Commands, 1, [], [], State).

split_by_pools([Command | T], Index, CmdAcc, MapAcc, State) ->
    Key = get_key_from_command(Command),
    Slot = get_key_slot(Key),
    {Pool, _Version} = eredis_cluster_monitor:get_pool_by_slot(Slot, State),
    {NewAcc1, NewAcc2} =
        case lists:keyfind(Pool, 1, CmdAcc) of
            false ->
                {[{Pool, [Command]} | CmdAcc], [{Pool, [Index]} | MapAcc]};
            {Pool, CmdList} ->
                CmdList2 = [Command | CmdList],
                CmdAcc2  = lists:keydelete(Pool, 1, CmdAcc),
                {Pool, MapList} = lists:keyfind(Pool, 1, MapAcc),
                MapList2 = [Index | MapList],
                MapAcc2  = lists:keydelete(Pool, 1, MapAcc),
                {[{Pool, CmdList2} | CmdAcc2], [{Pool, MapList2} | MapAcc2]}
        end,
    split_by_pools(T, Index + 1, NewAcc1, NewAcc2, State);
split_by_pools([], _Index, CmdAcc, MapAcc, State) ->
    CmdAcc2 = [{Pool, lists:reverse(Commands)} || {Pool, Commands} <- CmdAcc],
    MapAcc2 = [{Pool, lists:reverse(Mapping)} || {Pool, Mapping} <- MapAcc],
    {CmdAcc2, MapAcc2, eredis_cluster_monitor:get_state_version(State)}.

query(Command) ->
    PoolKey = get_key_from_command(Command),
    query(Command, PoolKey).

query(_, undefined) ->
    {error, invalid_cluster_command};
query(Command, PoolKey) ->
    query(Command, PoolKey, 0).

query_noreply(_, undefined) ->
    {error, invalid_cluster_command};
query_noreply(Command, PoolKey) ->
    Slot = get_key_slot(PoolKey),
    Transaction = fun(Worker) -> qw_noreply(Worker, Command) end,
    {Pool, _Version} = eredis_cluster_monitor:get_pool_by_slot(Slot),
    eredis_cluster_pool:transaction(Pool, Transaction),
    %% TODO: Retry if pool is busy? Handle redirects?
    ok.

query(_, _, ?REDIS_CLUSTER_REQUEST_TTL) ->
    {error, no_connection};
query(Command, PoolKey, Counter) ->
    throttle_retries(Counter),
    Slot = get_key_slot(PoolKey),
    {Pool, Version} = eredis_cluster_monitor:get_pool_by_slot(Slot),
    Result0 = eredis_cluster_pool:transaction(Pool, fun(W) -> qw(W, Command) end),
    Result = handle_redirects(Command, Result0, Version),
    case handle_transaction_result(Result, Version) of
        retry  -> query(Command, PoolKey, Counter + 1);
        Result -> Result
    end.

%% Inspects a result for ASK and MOVED redirects and, if possible,
%% follows the redirect. If a MOVED redirect is followed, a refresh
%% mapping is started in the background. If no redirect is followed,
%% the original result is returned.
-spec handle_redirects(Command :: redis_simple_command() | redis_pipeline_command(),
                       Result  :: redis_simple_result() | redis_pipeline_result(),
                       Version :: integer()) ->
          redis_simple_result() | redis_pipeline_result().
handle_redirects(Command, {error, <<"ASK ", RedirectInfo/binary>>} = Result, _Version) ->
    %% Simple command, simple result.
    case parse_redirect_info(RedirectInfo) of
        {ok, Pool} ->
            AskingPipeline = [[<<"ASKING">>], Command],
            AskingTransaction = fun(W) -> qw(W, AskingPipeline) end,
            case eredis_cluster_pool:transaction(Pool, AskingTransaction) of
                [{ok, <<"OK">>}, NewResult] ->
                    NewResult;
                _AskingFailed ->
                    Result
            end;
        {error, _NoExistingPool} ->
            Result
    end;
handle_redirects(Command, {error, <<"MOVED ", RedirectInfo/binary>>} = Result, Version) ->
    %% Simple command, simple result.
    case parse_redirect_info(RedirectInfo) of
        {ok, Pool} ->
            eredis_cluster_monitor:async_refresh_mapping(Version),
            eredis_cluster_pool:transaction(Pool, fun(W) -> qw(W, Command) end);
        {error, _NoExistingPool} ->
            Result
    end;
handle_redirects([[X|_]|_] = Command, Result, Version) when is_list(X) orelse is_binary(X),
                                                            is_list(Result) ->
    %% Pipeline command and pipeline result. If it contains redirects,
    %% follow them if they are all identical and there are no other
    %% errors in the result.
    {Redirects, OtherErrors} =
        lists:foldl(fun ({error, <<"MOVED ", _/binary>> = Redirect}, {RedirectAcc, OtherAcc}) ->
                            {[Redirect|RedirectAcc], OtherAcc};
                        ({error, <<"ASK ", _/binary>> = Redirect}, {RedirectAcc, OtherAcc}) ->
                            {[Redirect|RedirectAcc], OtherAcc};
                        ({error, Other}, {RedirectAcc, OtherAcc}) ->
                            {RedirectAcc, [Other|OtherAcc]};
                        (_, Acc) ->
                            Acc
                    end,
                    {[], []},
                    Result),
    case {OtherErrors, lists:usort(Redirects)} of
        {[], [Redirect]} ->
            %% All redirects are identical and there are no other errors.
            {RedirectType, RedirectInfo} =
                case Redirect of
                    <<"ASK ", AskInfo/binary>> -> {ask, AskInfo};
                    <<"MOVED ", MovedInfo/binary>> -> {moved, MovedInfo}
                end,
            case {parse_redirect_info(RedirectInfo), RedirectType} of
                {{ok, Pool}, ask} ->
                    AskingCommand = add_asking_to_pipeline_command(Command),
                    AskingTransaction = fun(W) -> qw(W, AskingCommand) end,
                    AskingResult = eredis_cluster_pool:transaction(Pool, AskingTransaction),
                    filter_out_asking_results(AskingCommand, AskingResult);
                {{ok, Pool}, moved} ->
                    eredis_cluster_monitor:async_refresh_mapping(Version),
                    eredis_cluster_pool:transaction(Pool, fun(W) -> qw(W, Command) end);
                _NoExistingPool ->
                    %% Don't redirect.
                    Result
            end;
        _OtherErrorsOrMultipleDifferentRedirects ->
            %% Don't redirect in this case.
            Result
    end;
handle_redirects(_Command, Result, _Version) ->
    %% E.g. error result
    Result.

%% If ASKING has been added to a pipeline command, remove the ASKING
%% results from the corresponding pipeline result list.
filter_out_asking_results(Commands, Results) when is_list(Results) ->
    filter_out_asking_results(Commands, Results, []);
filter_out_asking_results(_Commands, ErrorResult) when not is_list(ErrorResult) ->
    ErrorResult.

filter_out_asking_results([[<<"ASKING">>] | Commands], [{ok, <<"OK">>} | Results], Acc) ->
    filter_out_asking_results(Commands, Results, Acc);
filter_out_asking_results([_Command | Commands], [Result | Results], Acc) ->
    filter_out_asking_results(Commands, Results, [Result | Acc]);
filter_out_asking_results([], [], Acc) ->
    lists:reverse(Acc);
filter_out_asking_results(_Commands, _Results, _Acc) ->
    %% Length of commands and length of results mismatch
    {error, redirect_failed}.

%% Adds ASKING before every command, except inside a MULTI-command.
add_asking_to_pipeline_command([Command|Commands]) ->
    case string:uppercase(iolist_to_binary(Command)) of
        <<"MULTI">> ->
            {Transaction, AfterTransaction} = lists:splitwith(
                                                fun is_not_exec_or_discard/1,
                                                Commands),
            [[<<"ASKING">>], Command | Transaction] ++
                add_asking_to_pipeline_command(AfterTransaction);
        _NotMulti ->
            [[<<"ASKING">>], Command | add_asking_to_pipeline_command(Commands)]
    end;
add_asking_to_pipeline_command([]) ->
    [].

is_not_exec_or_discard([Command]) ->
    case string:uppercase(iolist_to_binary(Command)) of
        <<"EXEC">> -> false;
        <<"DISCARD">> -> false;
        _Other -> true
    end;
is_not_exec_or_discard(_Command) ->
    true.

%% Parses the Rest as in <<"ASK ", Rest/binary>> and returns an
%% existing pool if any or an error.
-spec parse_redirect_info(RedirectInfo :: binary()) ->
          {ok, ExistingPool :: atom()} | {error, any()}.
parse_redirect_info(RedirectInfo) ->
    try
        [_Slot, AddrPort] = binary:split(RedirectInfo, <<" ">>),
        [Addr0, PortBin] = binary:split(AddrPort, <<":">>),
        Port = binary_to_integer(PortBin),
        Addr = case Addr0 of
                   <<"[", IPv6:(byte_size(Addr0) - 2)/binary, "]">> ->
                       %% An IPv6 address wrapped in square brackets.
                       IPv6;
                   _ ->
                       Addr0
               end,
        eredis_cluster_pool:get_existing_pool(Addr, Port)
    of
        {ok, Pool} ->
            {ok, Pool};
        {error, _} = Error ->
            Error
    catch
        error:{badmatch, _} ->
            %% Couldn't parse using binary:split/2.
            {error, bad_redirect};
        error:badarg ->
            %% binary_to_integer/1 failed
            {error, bad_redirect}
    end.

handle_transaction_result(Results, Version) when is_list(Results) ->
    %% Consider all errors, to make sure slot mapping is updated if
    %% needed. (Multiple slot mapping updates have no effect if the
    %% Version is the same.)
    HandledResults = [handle_transaction_result(Result, Version)
                      || Result <- Results],
    case lists:member(retry, HandledResults) of
        true  -> retry;
        false -> Results
    end;
handle_transaction_result(Result, Version) ->
    case Result of
        %% If we detect a node went down, we should probably refresh
        %% the slot mapping.
        {error, no_connection} ->
            eredis_cluster_monitor:refresh_mapping(Version),
            retry;

        %% If the tcp connection is closed (connection timeout), the redis worker
        %% will try to reconnect, thus the connection should be recovered for
        %% the next request. We don't need to refresh the slot mapping in this
        %% case
        {error, tcp_closed} ->
            retry;

        %% Pool is busy
        {error, pool_busy} ->
            retry;

        %% Other TCP issues
        %% See reasons: https://erlang.org/doc/man/inet.html#type-posix
        {error, Reason} when is_atom(Reason) ->
            eredis_cluster_monitor:refresh_mapping(Version),
            retry;

        %% Redis explicitly say our slot mapping is incorrect,
        %% we need to refresh it
        {error, <<"MOVED ", _/binary>>} ->
            eredis_cluster_monitor:refresh_mapping(Version),
            retry;

        %% Migration ongoing
        {error, <<"ASK ", _/binary>>} ->
            retry;

        %% Resharding ongoing, only partial keys exists
        {error, <<"TRYAGAIN ", _/binary>>} ->
            retry;

        %% Hash not served, can be triggered temporary due to resharding
        {error, <<"CLUSTERDOWN ", _/binary>>} ->
            eredis_cluster_monitor:refresh_mapping(Version),
            retry;

        Payload ->
            Payload
    end.

-spec throttle_retries(integer()) -> ok.
throttle_retries(0) -> ok;
throttle_retries(_) -> timer:sleep(?REDIS_RETRY_DELAY).

%% =============================================================================
%% @doc Update the value of a key by applying the function passed in the
%% argument. The operation is done atomically
%% @end
%% =============================================================================
-spec update_key(Key::anystring(), UpdateFunction::fun((any()) -> any())) ->
    redis_transaction_result().
update_key(Key, UpdateFunction) ->
    UpdateFunction2 = fun(GetResult) ->
        {ok, Var} = GetResult,
        UpdatedVar = UpdateFunction(Var),
        {[["SET", Key, UpdatedVar]], UpdatedVar}
    end,
    case optimistic_locking_transaction(Key, ["GET", Key], UpdateFunction2) of
        {ok, {_, NewValue}} ->
            {ok, NewValue};
        Error ->
            Error
    end.

%% =============================================================================
%% @doc Update the value of a field stored in a hash by applying the function
%% passed in the argument. The operation is done atomically
%% @end
%% =============================================================================
-spec update_hash_field(Key::anystring(), Field::anystring(),
    UpdateFunction::fun((any()) -> any())) ->
          {ok, {[any()], any()}} | {error, redis_error_result()}.
update_hash_field(Key, Field, UpdateFunction) ->
    UpdateFunction2 = fun(GetResult) ->
        {ok, Var} = GetResult,
        UpdatedVar = UpdateFunction(Var),
        {[["HSET", Key, Field, UpdatedVar]], UpdatedVar}
    end,
    case optimistic_locking_transaction(Key, ["HGET", Key, Field], UpdateFunction2) of
        {ok, {[FieldPresent], NewValue}} ->
            {ok, {FieldPresent, NewValue}};
        Error ->
            Error
    end.

%% =============================================================================
%% @doc Optimistic locking transaction helper, based on Redis documentation :
%% http://redis.io/topics/transactions
%% @end
%% =============================================================================
-spec optimistic_locking_transaction(WatchedKey :: anystring(),
                                     GetCommand :: redis_command(),
                                     UpdateFunction :: fun((redis_result()) -> redis_pipeline_command())) ->
          {ok, {redis_success_result(), any()}} | {ok, {[redis_success_result()], any()}}
          | optimistic_locking_error_result().
optimistic_locking_transaction(WatchedKey, GetCommand, UpdateFunction) ->
    Slot = get_key_slot(WatchedKey),
    Transaction = fun(Worker) ->
        %% Watch given key
        qw(Worker, ["WATCH", WatchedKey]),
        %% Get necessary information for the modifier function
        GetResult = qw(Worker, GetCommand),
        %% Execute the pipelined command as a redis transaction
        {UpdateCommand, Result} = case UpdateFunction(GetResult) of
            {Command, Var} ->
                {Command, Var};
            Command ->
                {Command, undefined}
        end,
        RedisResult = qw(Worker, [["MULTI"]] ++ UpdateCommand ++ [["EXEC"]]),
        {lists:last(RedisResult), Result}
    end,
    case transaction(Transaction, Slot, {ok, undefined}, ?OL_TRANSACTION_TTL) of
        {{ok, undefined}, _} ->  % The key was touched by other client
            {error, resource_busy};
        {{ok, TransactionResult}, UpdateResult} ->
            {ok, {TransactionResult, UpdateResult}};
        {Error, _} ->
            Error
    end.


%% =============================================================================
%% @doc Eval command helper, to optimize the query, it will try to execute the
%% script using its hashed value. If no script is found, it will load it and
%% try again.
%% @end
%% =============================================================================
-spec eval(Script :: bitstring(), ScriptHash :: bitstring(), Keys :: [bitstring()],
           Args :: [bitstring()]) -> redis_result().
eval(Script, ScriptHash, Keys, Args) ->
    KeyNb = length(Keys),
    EvalShaCommand = ["EVALSHA", ScriptHash, integer_to_binary(KeyNb)] ++ Keys ++ Args,
    Key = if
        KeyNb == 0 -> "A"; %Random key
        true -> hd(Keys)
    end,

    case qk(EvalShaCommand, Key) of
        {error, <<"NOSCRIPT", _/binary>>} ->
            LoadCommand = ["SCRIPT", "LOAD", Script],
            [_, Result] = qk([LoadCommand, EvalShaCommand], Key),
            Result;
        Result ->
            Result
    end.

%% =============================================================================
%% @doc Returns the pool for a command.
%% @end
%% =============================================================================
-spec get_pool_by_command(Command::redis_command()) -> atom() | undefined.
get_pool_by_command(Command) ->
    Key = get_key_from_command(Command),
    get_pool_by_key(Key).

%% =============================================================================
%% @doc Returns the pool for a key.
%% @end
%% =============================================================================
-spec get_pool_by_key(Key::anystring()) -> atom() | undefined.
get_pool_by_key(Key) ->
    Slot = get_key_slot(Key),
    {Pool, _Version} = eredis_cluster_monitor:get_pool_by_slot(Slot),
    Pool.

%% =============================================================================
%% @doc Return the hash slot from the key
%% @end
%% =============================================================================
-spec get_key_slot(Key::anystring()) -> Slot::integer().
get_key_slot(Key) when is_bitstring(Key) ->
    get_key_slot(bitstring_to_list(Key));
get_key_slot(Key) ->
    KeyToBeHashed = case string:chr(Key, ${) of
        0 ->
            Key;
        Start ->
            case string:chr(string:substr(Key, Start + 1), $}) of
                0 ->
                    Key;
                Length ->
                    if
                        Length =:= 1 ->
                            Key;
                        true ->
                            string:substr(Key, Start + 1, Length-1)
                    end
            end
    end,
    eredis_cluster_hash:hash(KeyToBeHashed).

%% =============================================================================
%% @doc Return the first key in the command arguments.
%% In a normal query, the second term will be returned
%%
%% If it is a pipeline query we will use the second term of the first term, we
%% will assume that all keys are in the same server and the query can be
%% performed
%%
%% If the pipeline query starts with multi (transaction), we will look at the
%% second term of the second command
%%
%% For eval and evalsha command we will look at the fourth term.
%%
%% For commands that don't make sense in the context of cluster
%% return value will be undefined.
%% @end
%% =============================================================================
-spec get_key_from_command(redis_command()) -> string() | undefined.
get_key_from_command([[X|Y]|Z]) when is_bitstring(X) ->
    get_key_from_command([[bitstring_to_list(X)|Y]|Z]);
get_key_from_command([[X|Y]|Z]) when is_list(X) ->
    case string:to_lower(X) of
        "multi" ->
            get_key_from_command(Z);
        _ ->
            get_key_from_command([X|Y])
    end;
get_key_from_command([Term1, Term2|Rest]) when is_bitstring(Term1) ->
    get_key_from_command([bitstring_to_list(Term1), Term2|Rest]);
get_key_from_command([Term1, Term2|Rest]) when is_bitstring(Term2) ->
    get_key_from_command([Term1, bitstring_to_list(Term2)|Rest]);
get_key_from_command([Term1, Term2|Rest]) ->
    case string:to_lower(Term1) of
        "info" ->
            undefined;
        "config" ->
            undefined;
        "shutdown" ->
            undefined;
        "slaveof" ->
            undefined;
        "eval" ->
            get_key_from_rest(Rest);
        "evalsha" ->
            get_key_from_rest(Rest);
        _ ->
            Term2
    end;
get_key_from_command(_) ->
    undefined.

%% =============================================================================
%% @doc Get key for command where the key is in th 4th position (eval and
%% evalsha commands)
%% @end
%% =============================================================================
-spec get_key_from_rest([anystring()]) -> string() | undefined.
get_key_from_rest([_, KeyName|_]) when is_bitstring(KeyName) ->
    bitstring_to_list(KeyName);
get_key_from_rest([_, KeyName|_]) when is_list(KeyName) ->
    KeyName;
get_key_from_rest(_) ->
    undefined.
