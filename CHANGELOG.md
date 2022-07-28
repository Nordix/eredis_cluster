Change log
==========

0.9.0
-----

* Update eredis to 1.7.0

0.8.0
-----

* Update eredis to 1.5.1

0.7.0
-----

* Support multiple clusters
* List runtime dependencies in .app.src

0.6.1
-----

* Let [Eredis](https://github.com/Nordix/eredis) version to be 1.4 to 2.0 on mix and 1.4.1 on rebar
* Update CI jobs and generate TLS test certs on the fly to avoid outdated test certs

0.6.0
-----

First release of the [Nordix fork](https://github.com/Nordix/eredis_cluster] in April, 2021.

* Support of TLS introduced in Redis 6
* Uses [Nordix/eredis](https://github.com/Nordix/eredis) (TLS, error handling fixes)
* Many Dialyzer corrections
* Elvis code formatting
* Optimizations
  * Refresh slot mapping reuses existing connection when
    possible and don't refresh mapping when not needed, e.g. when a pool is busy
  * Don't use an extra wrapper process around each eredis connection process
* Containerized testing
* Testing using [simulated Redis cluster](https://github.com/Nordix/fakeredis_cluster) for corner cases such as ASK redirects
* Added API functions:
  - `connect/2`:              Connect to init nodes, with options
  - `qa2/1`:                  Query all nodes with re-attempts, returns `[{Node, Result}, ...]`
  - `qn/2`:                   Query to specific Redis node
  - `q_noreply/1`:            Query a single Redis node but wont wait for its result
  - `load_script/1`:          Pre-load script to all Redis nodes
  - `scan/4`:                 Perform a scan command on given Redis nodes
  - `disconnect/1`:           Disconnect from given Redis node
  - `get_all_pools/0`:        Get all pools (one for each Redis node in cluster)
  - `get_pool_by_command/1`:  Get which Redis pool that handles a given command
  - `get_pool_by_key/1`:      Get which Redis pool that handles a given key
  - `eredis_cluster_monitor:get_cluster_nodes/0`: Get cluster nodes information
    list (CLUSTER NODES)
  - `eredis_cluster_monitor:get_cluster_slots/0`: Get cluster slots information
    (CLUSTER SLOTS)
* Changed behaviour:
  - `qa/1`:                   Query all nodes, now with re-attempts
  - `transaction/2`:          The second argument can be a Redis node (pool) or a key, instead of only a key

0.5.12
------

This release from 2019 and older are releases of the original [adrienmo/eredis_cluster](https://github.com/adrienmo/eredis_cluster).

The initial commit was made in 2015 by Adrien Moreau.
