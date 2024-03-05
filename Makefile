.PHONY: all compile clean test ut ct xref dialyzer elvis cover coverview edoc publish
.PHONY: start status stop

REBAR ?= rebar3

# When supporting password and TLS; change to grokzen/redis-cluster:X.X.X
REDIS_CONTAINER ?= bjosv/redis-cluster:6.2.0

all: compile dialyzer xref elvis

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
	@$(REBAR) as test dialyzer

elvis:
	@elvis rock

cover:
	@$(REBAR) cover -v

coverview: cover
	xdg-open _build/test/cover/index.html

# Generate and patch documentation.
# The patching is needed to be able to generate documentation via Elixirs mix.
# Following changes are needed:
# - Handle link targets in headers, changes:
#     '### <a name="link">Header</a> ###' to
#     '<a name="link"></a> ### Header ###'
# - Newline needed for before following tags:
#     </table> </dd> </pre>
# - Removal of unneeded line breaks (visual only)
#
# Note: sed on macOS requires explicit in-place extensions (-i <extension>)
edoc:
	@$(REBAR) edoc
	@for file in doc/*.md ; do \
		sed -i.bak 's|### <a name="\(.*\)">\(.*\)</a> ###|<a name="\1"></a>\n### \2 ###|g' $${file} ; \
		sed -i.bak 's|</table>|\n</table>|g' $${file} ; \
		sed -i.bak 's|</dd>|\n</dd>|g' $${file} ; \
		sed -i.bak 's|</code></pre>|</code>\n</pre>|g' $${file} ; \
		sed -i.bak 's|<br />||g' $${file} ; \
		rm $${file}.bak ; \
	done

publish: edoc
	@touch doc/.build # Prohibit ex_doc to remove .md files
	@mix docs
	@if [ ! -z "$$(git status --untracked-file=no --porcelain)" ]; \
	then \
		echo "Error: Working directory is dirty. Please commit before publish!"; \
		exit 1; \
	fi
	mix hex.publish

start:
	priv/generate-test-certs.sh
	docker run --name redis-cluster -d -e IP=0.0.0.0 -e INITIAL_PORT=30001 \
	  -p 30001-30006:30001-30006 ${REDIS_CONTAINER}
	docker run --name redis-cluster-tls -d -e IP=0.0.0.0 -e INITIAL_PORT=31001 \
	  -p 31001-31006:31001-31006 -e TLS=true \
	  -v $(shell pwd)/priv/configs/tls/ca.crt:/redis-conf/ca.crt:ro \
	  -v $(shell pwd)/priv/configs/tls/ca.key:/redis-conf/ca.key:ro \
	  -v $(shell pwd)/priv/configs/tls/redis.crt:/redis-conf/redis.crt:ro \
	  -v $(shell pwd)/priv/configs/tls/redis.key:/redis-conf/redis.key:ro \
	  ${REDIS_CONTAINER}

status:
	docker exec redis-cluster /redis/src/redis-cli -c -p 30001 CLUSTER INFO
	docker exec redis-cluster-tls /redis/src/redis-cli -c -p 31001 --tls \
	  --cacert /redis-conf/ca.crt --cert /redis-conf/redis.crt --key /redis-conf/redis.key CLUSTER INFO

stop:
	-docker rm -f redis-cluster redis-cluster-tls
