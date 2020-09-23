-module(eredis_cluster_monitor).
-behaviour(gen_server).

%% API.
-export([start_link/0]).
-export([connect/2, disconnect/1]).
-export([refresh_mapping/1]).
-export([get_state/0, get_state_version/1]).
-export([get_pool_by_slot/1, get_pool_by_slot/2]).
-export([get_all_pools/0]).
-export([get_cluster_slots/0, get_cluster_nodes/0]).

%% gen_server.
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

%% Type definition.
-include("eredis_cluster.hrl").

-record(state, {
    init_nodes   = [] :: [#node{}],
    slots_maps   = {} :: tuple(), %% whose elements are #slots_map{}
    node_options = [] :: options(),
    version      = 0  :: integer()
}).

-define(SLOTS, eredis_cluster_monitor_slots).

%% API.
-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

connect(InitServers, Options) ->
    gen_server:call(?MODULE, {connect, InitServers, Options}).

disconnect(PoolNodes) ->
    gen_server:call(?MODULE, {disconnect, PoolNodes}).

refresh_mapping(Version) ->
    gen_server:call(?MODULE, {reload_slots_map, Version}).

-spec get_state() -> #state{}.
get_state() ->
    case ets:lookup(?MODULE, cluster_state) of
        [{cluster_state, State}] ->
            State;
        [] ->
            #state{}
    end.

get_state_version(State) ->
    State#state.version.

-spec get_all_pools() -> [atom()].
get_all_pools() ->
    State = get_state(),
    SlotsMapList = tuple_to_list(State#state.slots_maps),
    lists:usort([SlotsMap#slots_map.node#node.pool || SlotsMap <- SlotsMapList,
                    SlotsMap#slots_map.node =/= undefined]).

%% =============================================================================
%% @doc Get cluster pool by slot. Optionally, a memoized State can be provided
%% to prevent from querying ets inside loops.
%% @end
%% =============================================================================
-spec get_pool_by_slot(Slot::integer()) ->
    {PoolName::atom() | undefined, Version::integer()}.
get_pool_by_slot(Slot) ->
    State = get_state(),
    get_pool_by_slot(Slot, State).

-spec get_pool_by_slot(Slot::integer(), State::#state{}) ->
    {PoolName::atom() | undefined, Version::integer()}.
get_pool_by_slot(Slot, State) ->
    try
        [{_, Index}] = ets:lookup(?SLOTS, Slot),
        Cluster = element(Index, State#state.slots_maps),
        if
            Cluster#slots_map.node =/= undefined ->
                {Cluster#slots_map.node#node.pool, State#state.version};
            true ->
                {undefined, State#state.version}
        end
    catch
        _:_ ->
            {undefined, State#state.version}
    end.

%% =============================================================================
%% @doc Connect to a init node and get the slot distribution of nodes.
%% @end
%% =============================================================================
-spec reload_slots_map(State::#state{}) -> NewState::#state{}.
reload_slots_map(State) ->
    OldSlotsMaps = tuple_to_list(State#state.slots_maps),

    Options = get_current_options(State),
    ClusterSlots = get_cluster_slots(State#state.init_nodes, Options),
    NewSlotsMaps = parse_cluster_slots(ClusterSlots, Options),
    %% Find old slots_maps with nodes still in use.
    CommonInOldMap = lists:flatmap(
                       fun(#slots_map{node = Node} = OldElem) ->
                               [OldElem || Elem <- NewSlotsMaps,
                                           Elem#slots_map.node#node.address == Node#node.address,
                                           Elem#slots_map.node#node.port    == Node#node.port,
                                           Elem#slots_map.node#node.options == Node#node.options]
                       end, OldSlotsMaps),

    %% Disconnect non-used nodes
    RemovedFromOldMap = remove_list_elements(OldSlotsMaps, CommonInOldMap),
    [close_connection(SlotsMap) || SlotsMap <- RemovedFromOldMap],

    %% Connect to new nodes
    ConnectedSlotsMaps = connect_all_slots(NewSlotsMaps),
    create_slots_cache(ConnectedSlotsMaps),
    NewState = State#state{
        slots_maps = list_to_tuple(ConnectedSlotsMaps),
        version = State#state.version + 1
    },

    true = ets:insert(?MODULE, [{cluster_state, NewState}]),

    NewState.

%% =============================================================================
%% @doc Removes all elements (including duplicates) of Ys from Xs.
%% Xs and Ys can be unordered and contain duplicates.
%% @end
%% =============================================================================
-spec remove_list_elements(Xs::[term()], Ys::[term()]) -> [term()].
remove_list_elements(Xs, Ys) ->
    Set = gb_sets:from_list(Ys),
    [E || E <- Xs, not gb_sets:is_element(E, Set)].

%% =============================================================================
%% @doc Get cluster slots information.
%% @end
%% =============================================================================
-spec get_cluster_slots() -> [[bitstring() | [bitstring()]]].
get_cluster_slots() ->
    State = get_state(),
    Options = get_current_options(State),
    get_cluster_slots(State#state.init_nodes, Options).

get_cluster_slots(InitNodes, Options) ->
    Query = ["CLUSTER", "SLOTS"],
    FailFn = fun(Node) -> get_cluster_slots_from_single_node(Node) end,
    get_cluster_info(InitNodes, Options, Query, FailFn, []).

%% =============================================================================
%% @doc Get cluster nodes information.
%% Returns a list of node elements, each in the form:
%% [id, ip:port@cport, flags, master, ping-sent, pong-recv, config-epoch, link-state, <slot>, ...<slot>]
%%
%% See: https://redis.io/commands/cluster-nodes#serialization-format
%% @end
%% =============================================================================
-spec get_cluster_nodes() -> [[bitstring()]].
get_cluster_nodes() ->
    State = get_state(),
    Options = get_current_options(State),
    get_cluster_nodes(State#state.init_nodes, Options).

-spec get_cluster_nodes([#node{}], options()) -> [[bitstring()]].
get_cluster_nodes(InitNodes, Options) ->
    Query = ["CLUSTER", "NODES"],
    FailFn = fun(_Node) -> "" end, %% No default data to use when query fails
    ClusterNodes = get_cluster_info(InitNodes, Options, Query, FailFn, []),
    %% Parse result into list of element lists
    NodesInfoList = binary:split(ClusterNodes, <<"\n">>, [global, trim]),
    lists:foldl(fun(Node, Acc) ->
                        Acc ++ [binary:split(Node, <<" ">>, [global, trim])]
                end, [], NodesInfoList).

%% =============================================================================
%% @doc Generic function to do cluster information requests to a init node
%% @end
%% =============================================================================
get_cluster_info([], _Options, _Query, _FailFn, ErrorList) ->
    throw({reply, {error, {cannot_connect_to_cluster, ErrorList}}, #state{}});
get_cluster_info([Node|T], Options, Query, FailFn, ErrorList) ->
    case safe_eredis_start_link(Node#node.address, Node#node.port, Options) of
        {ok, Connection} ->
            try eredis:q(Connection, Query) of
                {error, <<"ERR unknown command 'CLUSTER'">>} ->
                    FailFn(Node);
                {error, <<"ERR This instance has cluster support disabled">>} ->
                    FailFn(Node);
                {ok, ClusterInfo} ->
                    ClusterInfo;
                Reason ->
                    get_cluster_info(T, Options, Query, FailFn, [{Node, Reason} | ErrorList])
            catch
                exit:{timeout, {gen_server, call, _}} ->
                    get_cluster_info(T, Options, Query, FailFn, [{Node, timeout} | ErrorList])
            after
                eredis:stop(Connection)
            end;
        Reason ->
            get_cluster_info(T, Options, Query, FailFn, [{Node, Reason} | ErrorList])
    end.

-spec get_cluster_slots_from_single_node(#node{}) ->
    [[bitstring() | [bitstring()]]].
get_cluster_slots_from_single_node(Node) ->
    [[<<"0">>, integer_to_binary(?REDIS_CLUSTER_HASH_SLOTS-1),
    [list_to_binary(Node#node.address), integer_to_binary(Node#node.port)]]].

-spec parse_cluster_slots(ClusterInfo::[[bitstring() | [bitstring()]]],
                          Options::options()) -> [#slots_map{}].
parse_cluster_slots(ClusterInfo, Options) ->
    SlotsMaps = parse_cluster_slots(ClusterInfo, 1, []),
    %% Save current options in each new SlotsMaps
    [SlotsMap#slots_map{node=SlotsMap#slots_map.node#node{options = Options}} ||
                       SlotsMap <- SlotsMaps].

parse_cluster_slots([[StartSlot, EndSlot | [[Address, Port | _] | _]] | T], Index, Acc) ->
    SlotsMap =
        #slots_map{
            index = Index,
            start_slot = binary_to_integer(StartSlot),
            end_slot = binary_to_integer(EndSlot),
            node = #node{
                address = binary_to_list(Address),
                port = binary_to_integer(Port)
            }
        },
    parse_cluster_slots(T, Index + 1, [SlotsMap | Acc]);
parse_cluster_slots([], _Index, Acc) ->
    lists:reverse(Acc).

%% =============================================================================
%% @doc Collect options set via application configs or in connect/2
%% @end
%% =============================================================================
-spec get_current_options(State::#state{}) -> options().
get_current_options(State) ->
    PasswordEntry = case application:get_env(eredis_cluster, password) of
                        {ok, Password} -> [{password, Password}];
                        _ -> []
                    end,
    TlsEntry = case application:get_env(eredis_cluster, tls) of
                   {ok, TlsConf} -> [{tls, TlsConf}];
                   _ -> []
               end,
    SockOptsEntry = case application:get_env(eredis_cluster, socket_options) of
                        {ok, SockOptsConf} -> [{socket_options, SockOptsConf}];
                        _ -> []
                    end,
    lists:usort(State#state.node_options ++ PasswordEntry ++ TlsEntry ++ SockOptsEntry).

%%%------------------------------------------------------------
-spec close_connection_with_nodes(SlotsMaps::[#slots_map{}],
                                  Pools::[atom()]) -> [#slots_map{}].
%%%
%%% Close the connection related to specified Pool node.
%%%------------------------------------------------------------
close_connection_with_nodes(SlotsMaps, Pools) ->
    lists:foldl(fun(Map, AccMap) ->
                        case lists:member(Map#slots_map.node#node.pool,
                                          Pools) of
                            true ->
                                close_connection(Map),
                                AccMap;
                            false ->
                                [Map|AccMap]
                        end
                end, [], SlotsMaps).

-spec close_connection(#slots_map{}) -> ok.
close_connection(SlotsMap) ->
    Node = SlotsMap#slots_map.node,
    if
        Node =/= undefined ->
            try eredis_cluster_pool:stop(Node#node.pool) of
                _ ->
                    ok
            catch
                _ ->
                    ok
            end;
        true ->
            ok
    end.

-spec connect_node(#node{}) -> #node{} | undefined.
connect_node(Node) ->
    case eredis_cluster_pool:create(Node#node.address,
                                    Node#node.port,
                                    Node#node.options) of
        {ok, Pool} ->
            Node#node{pool=Pool};
        _ ->
            undefined
    end.

safe_eredis_start_link(Address, Port, Options) ->
    process_flag(trap_exit, true),
    Result = eredis:start_link(Address, Port, Options),
    process_flag(trap_exit, false),
    Result.

-spec create_slots_cache([#slots_map{}]) -> true.
create_slots_cache(SlotsMaps) ->
  SlotsCache = [[{Index, SlotsMap#slots_map.index}
        || Index <- lists:seq(SlotsMap#slots_map.start_slot,
            SlotsMap#slots_map.end_slot)]
        || SlotsMap <- SlotsMaps],
  SlotsCacheF = lists:flatten(SlotsCache),
  ets:insert(?SLOTS, SlotsCacheF).

-spec connect_all_slots([#slots_map{}]) -> [#slots_map{}].
connect_all_slots(SlotsMapList) ->
    [SlotsMap#slots_map{node=connect_node(SlotsMap#slots_map.node)} ||
        SlotsMap <- SlotsMapList].

-spec connect_([{Address::string(), Port::integer()}], options()) -> #state{}.
connect_([], _Options) ->
    #state{};
connect_(InitNodes, Options) ->
    State = get_state(),
    NewState = State#state{
        init_nodes = [#node{address = A, port = P} || {A, P} <- InitNodes],
        node_options = Options
    },

    reload_slots_map(NewState).

-spec disconnect_([PoolNodes :: term()]) -> #state{}.
disconnect_([]) ->
    #state{};
disconnect_(PoolNodes) ->
    State = get_state(),
    SlotsMaps = tuple_to_list(State#state.slots_maps),

    NewSlotsMaps = close_connection_with_nodes(SlotsMaps, PoolNodes),

    ConnectedSlotsMaps = connect_all_slots(NewSlotsMaps),
    create_slots_cache(ConnectedSlotsMaps),

    NewState = State#state{
                 slots_maps = list_to_tuple(ConnectedSlotsMaps),
                 version = State#state.version + 1
                },
    true = ets:insert(?MODULE, [{cluster_state, NewState}]),
    NewState.

%% gen_server.

init(_Args) ->
    ets:new(?MODULE, [protected, set, named_table, {read_concurrency, true}]),
    ets:new(?SLOTS, [protected, set, named_table, {read_concurrency, true}]),
    InitNodes = application:get_env(eredis_cluster, init_nodes, []),
    {ok, connect_(InitNodes, [])}. %% get_env options read later in callstack

handle_call({reload_slots_map, Version}, _From, #state{version=Version} = State) ->
    {reply, ok, reload_slots_map(State)};
handle_call({reload_slots_map, _}, _From, State) ->
    {reply, ok, State};
handle_call({connect, InitServers, Options}, _From, _State) ->
    {reply, ok, connect_(InitServers, Options)};
handle_call({disconnect, PoolNodes}, _From, _State) ->
    {reply, ok, disconnect_(PoolNodes)};
handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
