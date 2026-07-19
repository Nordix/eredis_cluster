%% @doc Test-only builders for replica-bearing `CLUSTER SLOTS' replies.
%%
%% Used by eredis_cluster_replica_tests to construct cluster topologies
%% (masters with N replicas, across the Redis 3/4/7 node-entry shapes,
%% including the empty/unknown replica endpoints that the monitor's parser
%% must skip) without a live Redis instance.
%%
%% A `CLUSTER SLOTS' reply is a list of ranges. Each range is
%% `[StartSlot, EndSlot, MasterEntry | ReplicaEntries]', and each node entry is
%% `[Address, Port | Rest]'. All values are binaries, as eredis returns them.
%%
%% Node IDs are derived deterministically from the port (tests must not depend
%% on randomness), so a given topology always produces the same reply.
-module(eredis_cluster_topology_fixtures).

-include("eredis_cluster.hrl").

-export([cluster_slots/1, cluster_slots/2]).
-export([slots_maps/1, slots_maps/2]).
-export([node_entry/3]).
-export([empty_endpoint_replica/1, unknown_endpoint_replica/1]).

-type port_number() :: 1..65535.
%% {StartSlot, EndSlot, MasterPort, [ReplicaPort]}; all nodes on 127.0.0.1.
-type shard() :: {non_neg_integer(), non_neg_integer(), port_number(), [port_number()]}.
-type shape() :: redis3 | redis4 | redis7.

-define(ADDR, <<"127.0.0.1">>).

%% @doc Build a CLUSTER SLOTS reply (Redis-4 node shape) for the given shards.
-spec cluster_slots([shard()]) -> [list()].
cluster_slots(Shards) ->
    cluster_slots(Shards, redis4).

%% @doc As cluster_slots/1 with an explicit node-entry shape.
-spec cluster_slots([shard()], shape()) -> [list()].
cluster_slots(Shards, Shape) ->
    [shard_range(Shard, Shape) || Shard <- Shards].

%% @doc The shards run through the real monitor parser, i.e. `[#slots_map{}]'.
-spec slots_maps([shard()]) -> [#slots_map{}].
slots_maps(Shards) ->
    slots_maps(Shards, redis4).

-spec slots_maps([shard()], shape()) -> [#slots_map{}].
slots_maps(Shards, Shape) ->
    eredis_cluster_monitor:parse_cluster_slots(cluster_slots(Shards, Shape), []).

shard_range({Start, End, MasterPort, ReplicaPorts}, Shape) ->
    [integer_to_binary(Start),
     integer_to_binary(End),
     node_entry(?ADDR, MasterPort, Shape)
     | [node_entry(?ADDR, RPort, Shape) || RPort <- ReplicaPorts]].

%% @doc A single node entry in the requested Redis-version shape.
-spec node_entry(binary(), port_number(), shape()) -> [binary() | [binary()]].
node_entry(Addr, Port, redis3) ->
    [Addr, integer_to_binary(Port)];
node_entry(Addr, Port, redis4) ->
    [Addr, integer_to_binary(Port), node_id(Port)];
node_entry(Addr, Port, redis7) ->
    [Addr, integer_to_binary(Port), node_id(Port),
     [<<"hostname">>, hostname(Port)]].

%% @doc A replica node entry with an empty endpoint (Redis 7 "use the address
%% you connected to"); the parser must skip it.
-spec empty_endpoint_replica(port_number()) -> [binary()].
empty_endpoint_replica(Port) ->
    [<<>>, integer_to_binary(Port), node_id(Port)].

%% @doc A replica node entry with an unknown endpoint (`<<"?">>'); skipped.
-spec unknown_endpoint_replica(port_number()) -> [binary()].
unknown_endpoint_replica(Port) ->
    [<<"?">>, integer_to_binary(Port), node_id(Port)].

%% Deterministic 40-char node id derived from the port (no randomness).
node_id(Port) ->
    Hex = io_lib:format("~4.16.0b", [Port]),
    iolist_to_binary(string:left(lists:flatten(["node", Hex]), 40, $0)).

hostname(Port) ->
    iolist_to_binary(io_lib:format("node-~b.example.com", [Port])).
