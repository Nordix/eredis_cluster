.PHONY: all compile clean test ut ct xref dialyzer elvis cover coverview edoc help
.PHONY: start start-tcp start-tls status status-tcp status-tls stop travis-run

REBAR ?= rebar3
REDIS_VER ?= 6.0.4

DOCKER_CONF = --net=host -v $(shell pwd)/priv/configs/tls:/conf/tls:ro

# Redis cluster - common configs
REDIS_CONF = --cluster-enabled yes --cluster-node-timeout 5000 --appendonly yes

# TLS Redis cluster - common configs
REDIS_TLS_CONF = $(REDIS_CONF) --tls-cluster yes --port 0
REDIS_TLS_CONF += --tls-ca-cert-file /conf/tls/ca.crt
REDIS_TLS_CONF += --tls-cert-file /conf/tls/redis.crt
REDIS_TLS_CONF += --tls-key-file /conf/tls/redis.key

all: compile xref elvis

compile:
	@$(REBAR) compile

clean:
	@$(REBAR) clean
	@rm -rf _build

test: ut ct

ut:
	@ERL_FLAGS="-config test.config" $(REBAR) eunit -v --cover_export_name ut

ct:
	@$(REBAR) ct -v --cover_export_name ct

xref:
	@$(REBAR) xref

dialyzer:
	@$(REBAR) dialyzer

elvis:
	@elvis rock

cover:
	@$(REBAR) cover -v

coverview: cover
	xdg-open _build/test/cover/index.html


edoc:
	@$(REBAR) skip_deps=true doc

help:
	@echo "Please use 'make <target>' where <target> is one of"
	@echo "  start             starts a test redis cluster"
	@echo "  stop              stops all redis servers"
	@echo "  travis-run        starts the redis cluster and runs your tests"
	@echo "  travis-install    install redis from 'unstable' branch"

start: start-tcp start-tls

start-tcp:
	docker run --name redis-1 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_CONF) --port 30001
	docker run --name redis-2 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_CONF) --port 30002
	docker run --name redis-3 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_CONF) --port 30003
	docker run --name redis-4 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_CONF) --port 30004
	docker run --name redis-5 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_CONF) --port 30005
	docker run --name redis-6 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_CONF) --port 30006
	sleep 5
	echo 'yes' | docker run --name redis-cluster -i --rm $(DOCKER_CONF) redis:$(REDIS_VER) \
	redis-cli --cluster create \
	127.0.0.1:30001 127.0.0.1:30002 127.0.0.1:30003 127.0.0.1:30004 127.0.0.1:30005 127.0.0.1:30006 \
	--cluster-replicas 1

start-tls:
	docker run --name redis-tls-1 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_TLS_CONF) --tls-port 31001
	docker run --name redis-tls-2 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_TLS_CONF) --tls-port 31002
	docker run --name redis-tls-3 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_TLS_CONF) --tls-port 31003
	docker run --name redis-tls-4 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_TLS_CONF) --tls-port 31004
	docker run --name redis-tls-5 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_TLS_CONF) --tls-port 31005
	docker run --name redis-tls-6 -d $(DOCKER_CONF) redis:$(REDIS_VER) redis-server $(REDIS_TLS_CONF) --tls-port 31006
	sleep 7
	echo 'yes' | docker run --name redis-cluster -i --rm $(DOCKER_CONF) redis:$(REDIS_VER) \
	redis-cli --cluster create \
	--tls --cacert /conf/tls/ca.crt --cert /conf/tls/redis.crt --key /conf/tls/redis.key \
	127.0.0.1:31001 127.0.0.1:31002 127.0.0.1:31003 127.0.0.1:31004 127.0.0.1:31005 127.0.0.1:31006 \
	--cluster-replicas 1

status: status-tcp status-tls

status-tcp:
	docker run --name redis-cli -i --rm $(DOCKER_CONF) redis:$(REDIS_VER) \
	redis-cli -c -p 30001 CLUSTER INFO

status-tls:
	docker run --name redis-cli -i --rm $(DOCKER_CONF) redis:$(REDIS_VER) \
	redis-cli -c -p 31001 \
	--tls --cacert /conf/tls/ca.crt --cert /conf/tls/redis.crt --key /conf/tls/redis.key \
	CLUSTER INFO

stop:
	-docker rm -f redis-1 redis-2 redis-3 redis-4 redis-5 redis-6
	-docker rm -f redis-tls-1 redis-tls-2 redis-tls-3 redis-tls-4 redis-tls-5 redis-tls-6

travis-run:
	make start # Start and join clusters
	sleep 5
	make status

	make compile && make test

	make stop # Stop all cluster nodes
