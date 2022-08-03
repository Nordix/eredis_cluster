

# Module eredis_cluster #
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

.

__Behaviours:__ [`application`](application.md).

<a name="description"></a>

## Description ##

This module provides the API of `eredis_cluster`.

The `eredis_cluster` application is a Redis Cluster client. For each of the
nodes in a connected Redis cluster, a connection pool is maintained. In this
manual, the words "pool" and "node" are used interchangeably when referring
to the connection pool to a particular Redis node.

Some functions accept a Cluster parameter. For those which don't, they
operate on a default cluster. If you only need to connect to one cluster,
there is no need to use the functions with an explicit Cluster parameter.
<a name="types"></a>

## Data Types ##




<a name="type-anystring"></a>
### anystring() ###


<pre><code>
anystring() = string() | bitstring()
</code>
</pre>




<a name="type-optimistic_locking_error_result"></a>
### optimistic_locking_error_result() ###


<pre><code>
optimistic_locking_error_result() = {error, resource_busy} | {error, <a href="#type-redis_error_result">redis_error_result()</a>}
</code>
</pre>




<a name="type-optimistic_locking_result"></a>
### optimistic_locking_result() ###


<pre><code>
optimistic_locking_result() = <a href="#type-optimistic_locking_error_result">optimistic_locking_error_result()</a> | {{ok, undefined}, any()} | {{ok, <a href="#type-redis_success_result">redis_success_result()</a>}, any()} | {{ok, [<a href="#type-redis_success_result">redis_success_result()</a>]}, any()}
</code>
</pre>




<a name="type-options"></a>
### options() ###


<pre><code>
options() = [{term(), term()}]
</code>
</pre>




<a name="type-redis_command"></a>
### redis_command() ###


<pre><code>
redis_command() = <a href="#type-redis_simple_command">redis_simple_command()</a> | <a href="#type-redis_pipeline_command">redis_pipeline_command()</a>
</code>
</pre>




<a name="type-redis_error_result"></a>
### redis_error_result() ###


<pre><code>
redis_error_result() = bitstring() | no_connection | invalid_cluster_command | tcp_closed
</code>
</pre>




<a name="type-redis_pipeline_command"></a>
### redis_pipeline_command() ###


<pre><code>
redis_pipeline_command() = [<a href="#type-redis_simple_command">redis_simple_command()</a>]
</code>
</pre>




<a name="type-redis_pipeline_result"></a>
### redis_pipeline_result() ###


<pre><code>
redis_pipeline_result() = [<a href="#type-redis_simple_result">redis_simple_result()</a>]
</code>
</pre>




<a name="type-redis_result"></a>
### redis_result() ###


<pre><code>
redis_result() = <a href="#type-redis_simple_result">redis_simple_result()</a> | <a href="#type-redis_pipeline_result">redis_pipeline_result()</a> | <a href="#type-optimistic_locking_result">optimistic_locking_result()</a>
</code>
</pre>




<a name="type-redis_simple_command"></a>
### redis_simple_command() ###


<pre><code>
redis_simple_command() = [<a href="#type-anystring">anystring()</a> | integer()]
</code>
</pre>




<a name="type-redis_simple_result"></a>
### redis_simple_result() ###


<pre><code>
redis_simple_result() = {ok, <a href="#type-redis_success_result">redis_success_result()</a>} | {error, <a href="#type-redis_error_result">redis_error_result()</a>}
</code>
</pre>




<a name="type-redis_success_result"></a>
### redis_success_result() ###


<pre><code>
redis_success_result() = bitstring() | undefined
</code>
</pre>




<a name="type-redis_transaction_result"></a>
### redis_transaction_result() ###


<pre><code>
redis_transaction_result() = {ok, [<a href="#type-redis_success_result">redis_success_result()</a>]} | {ok, undefined} | {error, <a href="#type-redis_error_result">redis_error_result()</a>}
</code>
</pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#connect-1">connect/1</a></td><td>Connect to a Redis cluster using a set of init nodes.</td></tr><tr><td valign="top"><a href="#connect-2">connect/2</a></td><td>Connects to a Redis cluster using a set of init nodes, with options.</td></tr><tr><td valign="top"><a href="#connect-3">connect/3</a></td><td>Connects to a Redis cluster using a set of init nodes, with options and
cluster name.</td></tr><tr><td valign="top"><a href="#disconnect-1">disconnect/1</a></td><td>Disconnects a cluster by name or a set of nodes in the default cluster.</td></tr><tr><td valign="top"><a href="#eval-4">eval/4</a></td><td>Eval command helper, to optimize the query, it will try to execute the
script using its hashed value.</td></tr><tr><td valign="top"><a href="#flushdb-0">flushdb/0</a></td><td>Perform flushdb command on each node of the redis cluster.</td></tr><tr><td valign="top"><a href="#get_all_pools-0">get_all_pools/0</a></td><td>Returns the connection pools for all Redis nodes in the default cluster.</td></tr><tr><td valign="top"><a href="#get_all_pools-1">get_all_pools/1</a></td><td>Returns the connection pools for all Redis nodes in a named cluster.</td></tr><tr><td valign="top"><a href="#get_pool_by_command-1">get_pool_by_command/1</a></td><td>Returns the connection pool for the Redis node in the default cluster
where a command should be executed.</td></tr><tr><td valign="top"><a href="#get_pool_by_command-2">get_pool_by_command/2</a></td><td>Like get_pool_by_command/1 for a named cluster.</td></tr><tr><td valign="top"><a href="#get_pool_by_key-1">get_pool_by_key/1</a></td><td>Returns the connection pool for the Redis node responsible for the key
in the default cluster.</td></tr><tr><td valign="top"><a href="#get_pool_by_key-2">get_pool_by_key/2</a></td><td>Like get_pool_by_key/1 for a named cluster.</td></tr><tr><td valign="top"><a href="#load_script-1">load_script/1</a></td><td>Load LUA script to all master nodes in the Redis cluster.</td></tr><tr><td valign="top"><a href="#optimistic_locking_transaction-3">optimistic_locking_transaction/3</a></td><td>Optimistic locking transaction, based on Redis documentation:
https://redis.io/topics/transactions.</td></tr><tr><td valign="top"><a href="#q-1">q/1</a></td><td>This function executes simple or pipelined command on a single redis
node, which is selected according to the first key in the command.</td></tr><tr><td valign="top"><a href="#q-2">q/2</a></td><td>Simple or pipelined command on a named cluster.</td></tr><tr><td valign="top"><a href="#q_noreply-1">q_noreply/1</a></td><td>Executes a simple or pipeline of commands on a single Redis node, but
ignoring any response from Redis.</td></tr><tr><td valign="top"><a href="#qa-1">qa/1</a></td><td>Performs a query on all nodes in the default cluster.</td></tr><tr><td valign="top"><a href="#qa-2">qa/2</a></td><td>Performs a query on all nodes in a cluster.</td></tr><tr><td valign="top"><a href="#qa2-1">qa2/1</a></td><td>Perform a given query on all master nodes of a redis cluster and
return result with master node reference in result.</td></tr><tr><td valign="top"><a href="#qa2-2">qa2/2</a></td><td>Like qa2/1 but for a named cluster rather than the default cluster.</td></tr><tr><td valign="top"><a href="#qk-2">qk/2</a></td><td>Executes a simple or pipeline of command on the Redis node where the
provided key resides on the default cluster.</td></tr><tr><td valign="top"><a href="#qk-3">qk/3</a></td><td>Executes a simple or pipeline of command on the Redis node where the
provided key resides on a named cluster.</td></tr><tr><td valign="top"><a href="#qmn-1">qmn/1</a></td><td>Multi node query.</td></tr><tr><td valign="top"><a href="#qmn-2">qmn/2</a></td><td>Like qmn/1, but for a named cluster rather than the default cluster.</td></tr><tr><td valign="top"><a href="#qn-2">qn/2</a></td><td>
Execute a simple or pipelined command on a specific node.</td></tr><tr><td valign="top"><a href="#qp-1">qp/1</a></td><td>Executes a pipeline of commands.</td></tr><tr><td valign="top"><a href="#qw-2">qw/2</a></td><td>Function to be used for direct calls to an <code>eredis</code> connection instance
(a worker) in the function passed to the <code>transaction/2</code> function.</td></tr><tr><td valign="top"><a href="#scan-4">scan/4</a></td><td>Performs a SCAN on a specific node in the Redis cluster.</td></tr><tr><td valign="top"><a href="#start-0">start/0</a></td><td>Start application.</td></tr><tr><td valign="top"><a href="#stop-0">stop/0</a></td><td>Stop application.</td></tr><tr><td valign="top"><a href="#transaction-1">transaction/1</a></td><td>(<em>Deprecated</em>.) Function to execute a pipeline of commands as a transaction command, by
wrapping it in MULTI and EXEC.</td></tr><tr><td valign="top"><a href="#transaction-2">transaction/2</a></td><td>Execute a function on a single connection in the default cluster.</td></tr><tr><td valign="top"><a href="#transaction-3">transaction/3</a></td><td>Execute a function on a single connection in a named cluster.</td></tr><tr><td valign="top"><a href="#update_hash_field-3">update_hash_field/3</a></td><td>Update the value of a field stored in a hash by applying the function
passed in the argument.</td></tr><tr><td valign="top"><a href="#update_key-2">update_key/2</a></td><td>Update the value of a key by applying the function passed in the
argument.</td></tr>
</table>


<a name="functions"></a>

## Function Details ##

<a name="connect-1"></a>

### connect/1 ###

<pre><code>
connect(InitServers) -&gt; ok
</code>
</pre>

<ul class="definitions"><li><code>InitServers = [{Address::string(), Port::<a href="https://www.erlang.org/doc/man/inet.html#type-port_number">inet:port_number()</a>}]</code></li></ul>

Connect to a Redis cluster using a set of init nodes.

This is useful if the cluster configuration is not known when the application
is started.

Not all Redis nodes need to be provided. The addresses and port of the nodes
in the cluster are retrieved from one of the init nodes.

<a name="connect-2"></a>

### connect/2 ###

<pre><code>
connect(InitServers, Options) -&gt; ok
</code>
</pre>

<ul class="definitions"><li><code>InitServers = [{Address::string(), Port::<a href="https://www.erlang.org/doc/man/inet.html#type-port_number">inet:port_number()</a>}]</code></li><li><code>Options = <a href="#type-options">options()</a></code></li></ul>

Connects to a Redis cluster using a set of init nodes, with options.

Useful if the cluster configuration is not known at startup. The options, if
provided, can be used to override options set using `application:set_env/3`.

<a name="connect-3"></a>

### connect/3 ###

<pre><code>
connect(Cluster, InitServers, Options) -&gt; ok
</code>
</pre>

<ul class="definitions"><li><code>Cluster = atom()</code></li><li><code>InitServers = [{Address::string(), Port::<a href="https://www.erlang.org/doc/man/inet.html#type-port_number">inet:port_number()</a>}]</code></li><li><code>Options = <a href="#type-options">options()</a></code></li></ul>

Connects to a Redis cluster using a set of init nodes, with options and
cluster name.

Failes with error badarg if the cluster name is already in use as a
registered name of some other process.

<a name="disconnect-1"></a>

### disconnect/1 ###

<pre><code>
disconnect(Nodes::(Nodes::[atom()]) | (Cluster::atom())) -&gt; ok
</code>
</pre>


Disconnects a cluster by name or a set of nodes in the default cluster.

Note: Unused nodes are disconnected automatically when the slot mapping is
updated.

<a name="eval-4"></a>

### eval/4 ###

<pre><code>
eval(Script, ScriptHash, Keys, Args) -&gt; <a href="#type-redis_result">redis_result()</a>
</code>
</pre>

<ul class="definitions"><li><code>Script = <a href="#type-anystring">anystring()</a></code></li><li><code>ScriptHash = <a href="#type-anystring">anystring()</a></code></li><li><code>Keys = [<a href="#type-anystring">anystring()</a>]</code></li><li><code>Args = [<a href="#type-anystring">anystring()</a>]</code></li></ul>

Eval command helper, to optimize the query, it will try to execute the
script using its hashed value. If no script is found, it will load it and
try again.

The `ScriptHash` is provided by `load_script/1`, which can be used to
pre-load the script on all nodes.

The first key in `Keys` is used for selecting the Redis node where the script
is executed. If `Keys` is an empty list, the script is executed on an arbitrary
Redis node.

__See also:__ [load_script/1](#load_script-1).

<a name="flushdb-0"></a>

### flushdb/0 ###

<pre><code>
flushdb() -&gt; ok | {error, Reason::bitstring()}
</code>
</pre>


Perform flushdb command on each node of the redis cluster

This is equivalent to calling `qa(["FLUSHDB"])` except for the return value.

<a name="get_all_pools-0"></a>

### get_all_pools/0 ###

<pre><code>
get_all_pools() -&gt; [atom()]
</code>
</pre>


Returns the connection pools for all Redis nodes in the default cluster.

This is usedful for commands to a specific node using `qn/2` and
`transaction/2`.

__See also:__ [qn/2](#qn-2), [transaction/2](#transaction-2).

<a name="get_all_pools-1"></a>

### get_all_pools/1 ###

<pre><code>
get_all_pools(Cluster::atom()) -&gt; [atom()]
</code>
</pre>


Returns the connection pools for all Redis nodes in a named cluster.

<a name="get_pool_by_command-1"></a>

### get_pool_by_command/1 ###

<pre><code>
get_pool_by_command(Command::<a href="#type-redis_command">redis_command()</a>) -&gt; atom() | undefined
</code>
</pre>


Returns the connection pool for the Redis node in the default cluster
where a command should be executed.

The node is selected based on the first key in the command.

__See also:__ [get_pool_by_key/1](#get_pool_by_key-1).

<a name="get_pool_by_command-2"></a>

### get_pool_by_command/2 ###

<pre><code>
get_pool_by_command(Cluster::atom(), Command::<a href="#type-redis_command">redis_command()</a>) -&gt; atom() | undefined
</code>
</pre>


Like get_pool_by_command/1 for a named cluster.

<a name="get_pool_by_key-1"></a>

### get_pool_by_key/1 ###

<pre><code>
get_pool_by_key(Key::<a href="#type-anystring">anystring()</a>) -&gt; atom() | undefined
</code>
</pre>


Returns the connection pool for the Redis node responsible for the key
in the default cluster.

<a name="get_pool_by_key-2"></a>

### get_pool_by_key/2 ###

<pre><code>
get_pool_by_key(Cluster::atom(), Key::<a href="#type-anystring">anystring()</a>) -&gt; atom() | undefined
</code>
</pre>


Like get_pool_by_key/1 for a named cluster.

<a name="load_script-1"></a>

### load_script/1 ###

<pre><code>
load_script(Script::string()) -&gt; <a href="#type-redis_result">redis_result()</a>
</code>
</pre>


Load LUA script to all master nodes in the Redis cluster.

Returns `{ok, SHA1}` on success and an error otherwise.

This is equivalent to calling `qa(["SCRIPT", "LOAD", Script])` except for the
return value.

A script loaded in this way can be executed using eval/4.

__See also:__ [eval/4](#eval-4).

<a name="optimistic_locking_transaction-3"></a>

### optimistic_locking_transaction/3 ###

<pre><code>
optimistic_locking_transaction(WatchedKey, GetCommand, UpdateFunction) -&gt; Result
</code>
</pre>

<ul class="definitions"><li><code>WatchedKey = <a href="#type-anystring">anystring()</a></code></li><li><code>GetCommand = <a href="#type-redis_command">redis_command()</a></code></li><li><code>UpdateFunction = fun((<a href="#type-redis_result">redis_result()</a>) -&gt; <a href="#type-redis_pipeline_command">redis_pipeline_command()</a>)</code></li><li><code>Result = {ok, {<a href="#type-redis_success_result">redis_success_result()</a>, any()}} | {ok, {[<a href="#type-redis_success_result">redis_success_result()</a>], any()}} | <a href="#type-optimistic_locking_error_result">optimistic_locking_error_result()</a></code></li></ul>

Optimistic locking transaction, based on Redis documentation:
https://redis.io/topics/transactions

The function operates like the following pseudo-code:

```

  WATCH WatchedKey
  value = GetCommand
  MULTI
  UpdateFunction(value)
  EXEC
```

If the value associated with WatchedKey has changed between GetCommand and
EXEC, the sequence is retried.

<a name="q-1"></a>

### q/1 ###

<pre><code>
q(Command::<a href="#type-redis_command">redis_command()</a>) -&gt; <a href="#type-redis_result">redis_result()</a>
</code>
</pre>


This function executes simple or pipelined command on a single redis
node, which is selected according to the first key in the command.

<a name="q-2"></a>

### q/2 ###

<pre><code>
q(Cluster::atom(), Command::<a href="#type-redis_command">redis_command()</a>) -&gt; <a href="#type-redis_result">redis_result()</a>
</code>
</pre>


Simple or pipelined command on a named cluster.

<a name="q_noreply-1"></a>

### q_noreply/1 ###

<pre><code>
q_noreply(Command::<a href="#type-redis_command">redis_command()</a>) -&gt; ok
</code>
</pre>


Executes a simple or pipeline of commands on a single Redis node, but
ignoring any response from Redis. (Fire and forget)

Errors are ignored and there are no automatic retries.

<a name="qa-1"></a>

### qa/1 ###

<pre><code>
qa(Command) -&gt; Result
</code>
</pre>

<ul class="definitions"><li><code>Command = <a href="#type-redis_command">redis_command()</a></code></li><li><code>Result = [<a href="#type-redis_transaction_result">redis_transaction_result()</a>] | {error, no_connection}</code></li></ul>

Performs a query on all nodes in the default cluster. When a query to a
master fails, the mapping is refreshed and the query is retried.

<a name="qa-2"></a>

### qa/2 ###

<pre><code>
qa(Cluster, Command) -&gt; Result
</code>
</pre>

<ul class="definitions"><li><code>Cluster = atom()</code></li><li><code>Command = <a href="#type-redis_command">redis_command()</a></code></li><li><code>Result = [<a href="#type-redis_transaction_result">redis_transaction_result()</a>] | {error, no_connection}</code></li></ul>

Performs a query on all nodes in a cluster. When a query to a master
fails, the mapping is refreshed and the query is retried.

<a name="qa2-1"></a>

### qa2/1 ###

<pre><code>
qa2(Command) -&gt; Result
</code>
</pre>

<ul class="definitions"><li><code>Command = <a href="#type-redis_command">redis_command()</a></code></li><li><code>Result = [{Node::atom(), <a href="#type-redis_result">redis_result()</a>}] | {error, no_connection}</code></li></ul>

Perform a given query on all master nodes of a redis cluster and
return result with master node reference in result.
When a query to the master fail refresh the mapping and try again.

<a name="qa2-2"></a>

### qa2/2 ###

<pre><code>
qa2(Cluster, Command) -&gt; Result
</code>
</pre>

<ul class="definitions"><li><code>Cluster = atom()</code></li><li><code>Command = <a href="#type-redis_command">redis_command()</a></code></li><li><code>Result = [{Node::atom(), <a href="#type-redis_result">redis_result()</a>}] | {error, no_connection}</code></li></ul>

Like qa2/1 but for a named cluster rather than the default cluster.

<a name="qk-2"></a>

### qk/2 ###

<pre><code>
qk(Command::<a href="#type-redis_command">redis_command()</a>, Key::<a href="#type-anystring">anystring()</a>) -&gt; <a href="#type-redis_result">redis_result()</a>
</code>
</pre>


Executes a simple or pipeline of command on the Redis node where the
provided key resides on the default cluster.

<a name="qk-3"></a>

### qk/3 ###

<pre><code>
qk(Cluster::atom(), Command::<a href="#type-redis_command">redis_command()</a>, Key::<a href="#type-anystring">anystring()</a>) -&gt; <a href="#type-redis_result">redis_result()</a>
</code>
</pre>


Executes a simple or pipeline of command on the Redis node where the
provided key resides on a named cluster.

<a name="qmn-1"></a>

### qmn/1 ###

<pre><code>
qmn(Commands::<a href="#type-redis_pipeline_command">redis_pipeline_command()</a>) -&gt; <a href="#type-redis_pipeline_result">redis_pipeline_result()</a>
</code>
</pre>


Multi node query. Each command in a list of commands is sent
to the Redis node responsible for the key affected by that
command. Only simple commands operating on a single key are supported.

<a name="qmn-2"></a>

### qmn/2 ###

<pre><code>
qmn(Cluster::atom(), Commands::<a href="#type-redis_pipeline_command">redis_pipeline_command()</a>) -&gt; <a href="#type-redis_pipeline_result">redis_pipeline_result()</a>
</code>
</pre>


Like qmn/1, but for a named cluster rather than the default cluster.

<a name="qn-2"></a>

### qn/2 ###

<pre><code>
qn(Command, Node) -&gt; <a href="#type-redis_result">redis_result()</a>
</code>
</pre>

<ul class="definitions"><li><code>Command = <a href="#type-redis_command">redis_command()</a></code></li><li><code>Node = atom()</code></li></ul>

Execute a simple or pipelined command on a specific node.

The node is identified by the name of the connection pool for the node.

__See also:__ [get_all_pools/0](#get_all_pools-0), [qk/2](#qk-2).

<a name="qp-1"></a>

### qp/1 ###

<pre><code>
qp(Commands::<a href="#type-redis_pipeline_command">redis_pipeline_command()</a>) -&gt; <a href="#type-redis_pipeline_result">redis_pipeline_result()</a>
</code>
</pre>


Executes a pipeline of commands.

This function is identical to `q(Commands)`.

__See also:__ [q/1](#q-1).

<a name="qw-2"></a>

### qw/2 ###

<pre><code>
qw(Connection::pid(), Commands::<a href="#type-redis_command">redis_command()</a>) -&gt; <a href="#type-redis_result">redis_result()</a>
</code>
</pre>


Function to be used for direct calls to an `eredis` connection instance
(a worker) in the function passed to the `transaction/2` function.

This function calls `eredis:qp/2` for pipelines of commands and `eredis:q/1`
for single commands. It is also possible to use `eredis` directly.

__See also:__ [transaction/2](#transaction-2).

<a name="scan-4"></a>

### scan/4 ###

<pre><code>
scan(Node, Cursor, Pattern, Count) -&gt; Result
</code>
</pre>

<ul class="definitions"><li><code>Node = atom()</code></li><li><code>Cursor = integer()</code></li><li><code>Pattern = <a href="#type-anystring">anystring()</a></code></li><li><code>Count = integer()</code></li><li><code>Result = <a href="#type-redis_result">redis_result()</a> | {error, Reason::binary() | atom()}</code></li></ul>

Performs a SCAN on a specific node in the Redis cluster.

This is equivalent to calling `qn(["SCAN", Cursor, "MATCH", Pattern, "COUNT",
Count], Node)`.

__See also:__ [get_all_pools/0](#get_all_pools-0), [qn/1](#qn-1).

<a name="start-0"></a>

### start/0 ###

<pre><code>
start() -&gt; ok | {error, Reason::term()}
</code>
</pre>


Start application.

If `eredis_cluster` is configured with init nodes using the application
environment, using a config file or by explicitly by calling
`application:set_env(eredis_cluster, init_nodes, InitNodes)`, the cluster is
connected when the application is started. Otherwise, it can be connected
later using `connect/1,2`.

<a name="stop-0"></a>

### stop/0 ###

<pre><code>
stop() -&gt; ok | {error, Reason::term()}
</code>
</pre>


Stop application.

The same as `application:stop(eredis_cluster)`.

<a name="transaction-1"></a>

### transaction/1 ###

<pre><code>
transaction(Commands::<a href="#type-redis_pipeline_command">redis_pipeline_command()</a>) -&gt; <a href="#type-redis_transaction_result">redis_transaction_result()</a>
</code>
</pre>


__This function is deprecated:__ This function can be confused with [`transaction/2`](#transaction-2) which
works in a very different way. Please use [`q/1`](#q-1) instead.

Function to execute a pipeline of commands as a transaction command, by
wrapping it in MULTI and EXEC. Returns the result of EXEC, which is the list
of responses for each of the commands.

`transaction(Commands)` is equivalent to calling `q([["MULTI"]] ++ Commands
++ [["EXEC"]])` and taking the last element in the resulting list.

<a name="transaction-2"></a>

### transaction/2 ###

<pre><code>
transaction(Transaction, KeyOrPool::Key | Pool) -&gt; <a href="#type-redis_result">redis_result()</a>
</code>
</pre>

<ul class="definitions"><li><code>Key = <a href="#type-anystring">anystring()</a></code></li><li><code>Pool = atom()</code></li><li><code>Transaction = fun((Connection::pid()) -&gt; <a href="#type-redis_result">redis_result()</a>)</code></li></ul>

Execute a function on a single connection in the default cluster.

This should be used when a transaction command such
as WATCH or DISCARD must be used. The node is selected by giving a key that
this node is containing or by giving the node directly. Note that this
function does not add MULTI or EXEC, so it can be used also for sequences of
commands which are not Redis transactions.

The `Transaction` fun shall use `qw/2` to execute commands on the selected
connection pid passed to it.

A transaction can be retried automatically, so the `Transaction` fun should
not have side effects.

__See also:__ [qw/2](#qw-2).

<a name="transaction-3"></a>

### transaction/3 ###

<pre><code>
transaction(Transaction, Cluster, Key::Key | Pool) -&gt; <a href="#type-redis_result">redis_result()</a>
</code>
</pre>

<ul class="definitions"><li><code>Transaction = fun((Connection::pid()) -&gt; <a href="#type-redis_result">redis_result()</a>)</code></li><li><code>Cluster = atom()</code></li><li><code>Key = <a href="#type-anystring">anystring()</a></code></li><li><code>Pool = atom()</code></li></ul>

Execute a function on a single connection in a named cluster.

__See also:__ [transaction/2](#transaction-2).

<a name="update_hash_field-3"></a>

### update_hash_field/3 ###

<pre><code>
update_hash_field(Key, Field, UpdateFunction) -&gt; Result
</code>
</pre>

<ul class="definitions"><li><code>Key = <a href="#type-anystring">anystring()</a></code></li><li><code>Field = <a href="#type-anystring">anystring()</a></code></li><li><code>UpdateFunction = fun((any()) -&gt; any())</code></li><li><code>Result = {ok, {[any()], any()}} | {error, <a href="#type-redis_error_result">redis_error_result()</a>}</code></li></ul>

Update the value of a field stored in a hash by applying the function
passed in the argument. The operation is done atomically using an optimistic
locking transaction.

__See also:__ [optimistic_locking_transaction/3](#optimistic_locking_transaction-3).

<a name="update_key-2"></a>

### update_key/2 ###

<pre><code>
update_key(Key, UpdateFunction) -&gt; Result
</code>
</pre>

<ul class="definitions"><li><code>Key = <a href="#type-anystring">anystring()</a></code></li><li><code>UpdateFunction = fun((any()) -&gt; any())</code></li><li><code>Result = <a href="#type-redis_transaction_result">redis_transaction_result()</a></code></li></ul>

Update the value of a key by applying the function passed in the
argument. The operation is done atomically, using an optimistic locking
transaction.

__See also:__ [optimistic_locking_transaction/3](#optimistic_locking_transaction-3).

