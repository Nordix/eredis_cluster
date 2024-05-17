

# Module eredis_cluster_monitor #
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)

This module manages the slot mapping.

__Behaviours:__ [`gen_server`](gen_server.md).

__See also:__ [eredis_cluster](eredis_cluster.md).

<a name="description"></a>

## Description ##

In a Redis cluster, each key
belongs to a slot and each slot belongs to a Redis master node.

This module is mainly internal, but some functions are documented and may be
useful for advanced scenarios.
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#get_cluster_nodes-0">get_cluster_nodes/0</a></td><td>Get cluster nodes information.</td></tr><tr><td valign="top"><a href="#get_cluster_nodes-1">get_cluster_nodes/1</a></td><td></td></tr><tr><td valign="top"><a href="#get_cluster_slots-0">get_cluster_slots/0</a></td><td>Get cluster slots information.</td></tr>
</table>


<a name="functions"></a>

## Function Details ##

<a name="get_cluster_nodes-0"></a>

### get_cluster_nodes/0 ###

<pre><code>
get_cluster_nodes() -&gt; [[binary()]]
</code>
</pre>


Get cluster nodes information.
Returns a list of node elements, each in the form:

```
[id, ip:port@cport, flags, master, ping-sent, pong-recv, config-epoch, link-state, Slot1, ..., SlotN]
```

See: https://redis.io/commands/cluster-nodes#serialization-format

<a name="get_cluster_nodes-1"></a>

### get_cluster_nodes/1 ###

<pre><code>
get_cluster_nodes(Cluster::atom()) -&gt; [[binary()]]
</code>
</pre>


<a name="get_cluster_slots-0"></a>

### get_cluster_slots/0 ###

<pre><code>
get_cluster_slots() -&gt; [[binary() | [binary()]]]
</code>
</pre>


Get cluster slots information.

