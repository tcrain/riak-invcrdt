#!/bin/bash

USER_ROOT=$1
RIAK_ROOT=$USER_ROOT"riak/"
RIAK_CLIENT_ROOT=$USER_ROOT"riak-erlang-client/"
ERTS=$RIAK_ROOT"erts-5.10.3/bin/erl -pa "$RIAK_CLIENT_ROOT"ebin "$RIAK_CLIENT_ROOT"deps/*/ebin ."
ERLC=$RIAK_ROOT"erts-5.10.3/bin/erlc"

#compile worker and statistics module
$ERLC "client_stats.erl"
$ERLC "worker_sc.erl"

./script "10" "100" > output

