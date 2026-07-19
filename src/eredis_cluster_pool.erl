%% @private
-module(eredis_cluster_pool).
-behaviour(supervisor).

%% API.
-export([create/4, create/5]).
-export([get_existing_pool/2]).
-export([stop/2]).
-export([transaction/2]).

-ifdef(TEST).
-export([get_name/2, get_name/3]).
-endif.

%% Supervisor
-export([start_link/0]).
-export([init/1]).

-include("eredis_cluster.hrl").

-spec create(PoolSup::pid(), Host::string(), Port::integer(), options()) ->
    {ok, PoolName::atom()} | {error, PoolName::atom()}.
create(PoolSup, Host, Port, Options) ->
    create(PoolSup, Host, Port, Options, master).

%% @doc Create a connection pool for a node in the given role.
%%
%% `master' pools are named `Host#Port'; `replica' pools `Host#Port#r', so a
%% node that changes role gets a distinct, correctly-sized pool rather than
%% reusing the other role's. Replica pools take their size from
%% `replica_pool_size' / `replica_pool_max_overflow' (falling back to the
%% master `pool_size' / `pool_max_overflow' when unset). The size options are
%% applied here only; they are never stored on the node, so the slot-map reuse
%% diff stays role-agnostic.
-spec create(PoolSup::pid(), Host::string(), Port::integer(), options(),
             Role :: master | replica) ->
    {ok, PoolName::atom()} | {error, PoolName::atom()}.
create(PoolSup, Host, Port, Options, Role) ->
    PoolName = get_name(Host, Port, Role),

    case whereis(PoolName) of
        undefined ->
            EredisOptions = [{K, V} || {K, V} <- Options,
                                       K =/= pool_size,
                                       K =/= pool_max_overflow,
                                       K =/= replica_reads,
                                       K =/= replica_pool_size,
                                       K =/= replica_pool_max_overflow],
            WorkerArgs = [{host, Host}, {port, Port}] ++ EredisOptions,
            {Size, MaxOverflow} = pool_sizing(Options, Role),

            PoolArgs = [{name, {local, PoolName}},
                        {worker_module, eredis},
                        {size, Size},
                        {max_overflow, MaxOverflow}],

            ChildSpec = poolboy:child_spec(PoolName, PoolArgs, WorkerArgs),
            {Result, _} = supervisor:start_child(PoolSup, ChildSpec),
            {Result, PoolName};
        _ ->
            {ok, PoolName}
    end.

%% Pool size/overflow for a role. Replicas prefer the replica_* options and
%% fall back to the master values, which in turn default to 10/0.
pool_sizing(Options, master) ->
    {proplists:get_value(pool_size, Options, 10),
     proplists:get_value(pool_max_overflow, Options, 0)};
pool_sizing(Options, replica) ->
    Size = proplists:get_value(pool_size, Options, 10),
    Overflow = proplists:get_value(pool_max_overflow, Options, 0),
    {proplists:get_value(replica_pool_size, Options, Size),
     proplists:get_value(replica_pool_max_overflow, Options, Overflow)}.

-spec get_existing_pool(Host :: string() | binary(),
                        Port :: inet:port_number()) ->
          {ok, Pool :: atom()} | {error, no_pool}.
get_existing_pool(Host, Port) when is_binary(Host) ->
    get_existing_pool(binary_to_list(Host), Port);
get_existing_pool(Host, Port) when is_list(Host) ->
    Pool = get_name(Host, Port),
    case whereis(Pool) of
        Pid when is_pid(Pid) ->
            {ok, Pool};
        _NoPid ->
            {error, no_pool}
    end.

-spec transaction(PoolName::atom(), fun((Worker::pid()) -> redis_result())) ->
    redis_result().
transaction(PoolName, Transaction) ->
    try
        poolboy:transaction(PoolName, Transaction)
    catch
        exit:{timeout, _GenServerCall} ->
            %% Poolboy checkout timeout, but the pool is consistent.
            {error, pool_busy};
        exit:_ ->
            %% Pool doesn't exist? Refresh mapping solves this.
            {error, no_connection}
    end.

-spec stop(PoolSup :: pid(), PoolName :: atom()) -> ok.
stop(PoolSup, PoolName) ->
    supervisor:terminate_child(PoolSup, PoolName),
    supervisor:delete_child(PoolSup, PoolName),
    ok.

-spec get_name(Host::string(), Port::integer()) -> PoolName::atom().
get_name(Host, Port) ->
    get_name(Host, Port, master).

%% @doc Pool name for a node in a given role. Master pools keep the historical
%% `Host#Port' name (so redirect resolution via get_existing_pool/2 finds them);
%% replica pools get a `#r' suffix so the two roles never share a pool.
-spec get_name(Host::string(), Port::integer(), Role :: master | replica) ->
          PoolName::atom().
get_name(Host, Port, master) ->
    list_to_atom(Host ++ "#" ++ integer_to_list(Port));
get_name(Host, Port, replica) ->
    list_to_atom(Host ++ "#" ++ integer_to_list(Port) ++ "#r").

-spec start_link() -> {ok, pid()}.
start_link() ->
    supervisor:start_link(?MODULE, []).

-spec init([])
          -> {ok, {{supervisor:strategy(), 2, 5}, [supervisor:child_spec()]}}.
init([]) ->
    %% Intensity 2 (rather than 1): with replica reads enabled the pool count
    %% per cluster roughly doubles, so a single transient double-crash of
    %% poolboy workers should not take down the whole pool supervisor.
    {ok, {{one_for_one, 2, 5}, []}}.
