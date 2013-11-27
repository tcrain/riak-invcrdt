#!/bin/bash

#-c <ConsistencyLevel> -t <numClientsByRegion> -v <initialValue> <primaryAddress>

#ConsistencyLevel - Selects the appropriate bucket (Strong/Eventual)
#Address is written in the form "ID:ADDRESS"

USERNAME="ec2-user"
USER_ROOT="/Users/balegas/workspace/riak-invcrdt/"
RIAK_ROOT="/Users/balegas/workspace/riak/"
RIAK_CLIENT_ROOT=$USER_ROOT"riak-erlang-client/"
ERTS=$RIAK_ROOT"erts-5.10.3/bin/erl -pa "$RIAK_CLIENT_ROOT"ebin "$RIAK_CLIENT_ROOT"deps/*/ebin ."
ERLC=$RIAK_ROOT"erts-5.10.3/bin/erlc"

CLIENT_HOSTS="./CLIENTS"
USERNAME="ec2-user"

#compile worker modules
#$ERLC $USER_ROOT"replication_agent.erl"
#$ERLC $USER_ROOT"nncounter.erl"
#$ERLC $USER_ROOT"client_stats.erl"
#$ERLC $USER_ROOT"worker_sc.erl"

BUCKET_TYPE="NONE"
BUCKET="ITEMS"
THREADS="1"
INITIAL_VALUE="0"

declare -a CLIENTS=('id0:ec2-54-247-36-56.eu-west-1.compute.amazonaws.com', 'id1:ec2-50-19-186-18.compute-1.amazonaws.com')

#<LocalAddress> <numClientsByRegion> 
run_experiment(){
	# Exclude localAddress from the clients list
	declare -a other_clients=( ${CLIENTS[@]/$2*/} )
	cmd="./script "$2" "$1"0 "$USER_ROOT" "$BUCKET" "$BUCKET_TYPE" false "${other_clients[@]}
	echo $cmd
}

#<LocalAddress> <numClientsByRegion> 
reset_cluster(){
	# Exclude localAddress from the clients list
	declare -a other_clients=( ${CLIENTS[@]/$2*/} )
	cmd="./reset-script "$2" "$1"0 "$INITIAL_VALUE" "$USER_ROOT" "$BUCKET" "$BUCKET_TYPE" "${other_clients[@]}
	./$cmd
}


#Process options
while getopts "v:c:rt:" optname
  do
    case "$optname" in
      "v")
		  INITIAL_VALUE=$OPTARG
		  ;;
      "c")
	  case $OPTARG in
		  'strong') 
		  BUCKET_TYPE="STRONG"
	  esac
        ;;
      "r")
        echo "Get results from clients."
	copy_from_remote $CLIENT_HOSTS $USERNAME $REMOTE_DIR"/"$RESULTS_DIR $DEP_DIR
	exit
        ;;
      "t")
  		  THREADS=$OPTARG
  		  ;;
      "?")
        echo "Unknown option $OPTARG"
        ;;
      ":")
        echo "No argument value for option $OPTARG"
        ;;
      *)
      # Should not occur
        echo "Unknown error while processing options"
        ;;
    esac
  done
  
echo "Bucket: "$BUCKET_TYPE" "$BUCKET
echo "Threads per region: "$THREADS
echo "Initial value: "$INITIAL_VALUE

shift $(( ${OPTIND} - 1 )); echo "${*}"
reset_cluster $1 $THREADS
#run_experiment $PREFIX $1 $THREADS
echo "Finish"