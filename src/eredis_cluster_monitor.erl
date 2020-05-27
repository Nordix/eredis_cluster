-module(eredis_cluster_monitor).
-behaviour(gen_server).

%% API.
-export([start_link/0]).
-export([connect/2, disconnect/1]).
-export([refresh_mapping/1]).
-export([get_state/0, get_state_version/1]).
-export([get_pool_by_slot/1, get_pool_by_slot/2]).
-export([get_all_pools/0]).

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
    slots        = {} :: tuple(), %% whose elements are integer indexes into slots_maps
    slots_maps   = {} :: tuple(), %% whose elements are #slots_map{}
    node_options = [] :: options(),
    version      = 0  :: integer()
}).

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

%% =============================================================================
%% @doc Given a slot return the link (Redis instance) to the mapped
%% node.
%% @end
%% =============================================================================

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
-spec get_pool_by_slot(Slot::integer(), State::#state{}) ->
    {PoolName::atom() | undefined, Version::integer()}.
get_pool_by_slot(Slot, State) ->
    try
        Index = element(Slot + 1, State#state.slots),
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

-spec get_pool_by_slot(Slot::integer()) ->
    {PoolName::atom() | undefined, Version::integer()}.
get_pool_by_slot(Slot) ->
    State = get_state(),
    get_pool_by_slot(Slot, State).

-spec reload_slots_map(State::#state{}) -> NewState::#state{}.
reload_slots_map(State) ->
    [close_connection(SlotsMap)
        || SlotsMap <- tuple_to_list(State#state.slots_maps)],

    Password = application:get_env(eredis_cluster, password, ""),
    Options = State#state.node_options ++ [{password, Password}],

    ClusterSlots = get_cluster_slots(State#state.init_nodes, Options),

    SlotsMaps = parse_cluster_slots(ClusterSlots),
    ConnectedSlotsMaps = connect_all_slots(SlotsMaps, Options),
    Slots = create_slots_cache(ConnectedSlotsMaps),

    NewState = State#state{
        slots = list_to_tuple(Slots),
        slots_maps = list_to_tuple(ConnectedSlotsMaps),
        version = State#state.version + 1
    },

    true = ets:insert(?MODULE, [{cluster_state, NewState}]),

    NewState.

-spec get_cluster_slots([#node{}], options()) -> [[bitstring() | [bitstring()]]].
get_cluster_slots([], _Options) ->
    throw({error, cannot_connect_to_cluster});
get_cluster_slots([Node|T], Options) ->
    case safe_eredis_start_link(Node#node.address, Node#node.port, Options) of
        {ok, Connection} ->
          case eredis:q(Connection, ["CLUSTER", "SLOTS"]) of
            {error, <<"ERR unknown command 'CLUSTER'">>} ->
                get_cluster_slots_from_single_node(Node);
            {error, <<"ERR This instance has cluster support disabled">>} ->
                get_cluster_slots_from_single_node(Node);
            {ok, ClusterInfo} ->
                eredis:stop(Connection),
                ClusterInfo;
            _ ->
                eredis:stop(Connection),
                get_cluster_slots(T, Options)
        end;
        _ ->
            get_cluster_slots(T, Options)
  end.

-spec get_cluster_slots_from_single_node(#node{}) ->
    [[bitstring() | [bitstring()]]].
get_cluster_slots_from_single_node(Node) ->
    [[<<"0">>, integer_to_binary(?REDIS_CLUSTER_HASH_SLOTS-1),
    [list_to_binary(Node#node.address), integer_to_binary(Node#node.port)]]].

-spec parse_cluster_slots([[bitstring() | [bitstring()]]]) -> [#slots_map{}].
parse_cluster_slots(ClusterInfo) ->
    parse_cluster_slots(ClusterInfo, 1, []).

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

-spec connect_node(#node{}, options()) -> #node{} | undefined.
connect_node(Node, Options) ->
    case eredis_cluster_pool:create(Node#node.address, Node#node.port, Options) of
        {ok, Pool} ->
            Node#node{pool=Pool};
        _ ->
            undefined
    end.

safe_eredis_start_link(Address, Port, Options) ->
    process_flag(trap_exit, true),
    Payload = eredis:start_link(Address, Port, Options),
    process_flag(trap_exit, false),
    Payload.

-spec create_slots_cache([#slots_map{}]) -> [integer()].
create_slots_cache(SlotsMaps) ->
  SlotsCache = [[{Index, SlotsMap#slots_map.index}
        || Index <- lists:seq(SlotsMap#slots_map.start_slot,
            SlotsMap#slots_map.end_slot)]
        || SlotsMap <- SlotsMaps],
  SlotsCacheF = lists:flatten(SlotsCache),
  SortedSlotsCache = lists:sort(SlotsCacheF),
  [ Index || {_, Index} <- SortedSlotsCache].

-spec connect_all_slots([#slots_map{}], options()) -> [#slots_map{}].
connect_all_slots(SlotsMapList, Options) ->
    [SlotsMap#slots_map{node=connect_node(SlotsMap#slots_map.node, Options)}
        || SlotsMap <- SlotsMapList].

-spec connect_([{Address::string(), Port::integer()}], options()) -> #state{}.
connect_([], _Options) ->
    #state{};
connect_(InitNodes, Options) ->
    State = #state{
        init_nodes = [#node{address = A, port = P} || {A, P} <- InitNodes],
        node_options = Options
    },

    reload_slots_map(State).

-spec disconnect_([PoolNodes :: term()]) -> #state{}.
disconnect_([]) ->
    #state{};
disconnect_(PoolNodes) ->
    State = get_state(),
    SlotsMaps = tuple_to_list(State#state.slots_maps),

    Password = application:get_env(eredis_cluster, password, ""),
    Options = State#state.node_options ++ [{password, Password}],

    NewSlotsMaps = close_connection_with_nodes(SlotsMaps, PoolNodes),

    ConnectedSlotsMaps = connect_all_slots(NewSlotsMaps, Options),
    Slots = create_slots_cache(ConnectedSlotsMaps),

    NewState = State#state{
                 slots = list_to_tuple(Slots),
                 slots_maps = list_to_tuple(ConnectedSlotsMaps),
                 version = State#state.version + 1
                },
    true = ets:insert(?MODULE, [{cluster_state, NewState}]),
    NewState.

%% gen_server.

init(_Args) ->
    ets:new(?MODULE, [protected, set, named_table, {read_concurrency, true}]),
    InitNodes = application:get_env(eredis_cluster, init_nodes, []),
    Options = application:get_env(eredis_cluster, node_options, []),
    {ok, connect_(InitNodes, Options)}.

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
