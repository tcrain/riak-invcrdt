%%%-------------------------------------------------------------------
%%% @author balegas
%%% @copyright (C) 2013, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 14. Nov 2013 15:37
%%%-------------------------------------------------------------------
-module(worker_sc).
-author("balegas").

%% API
-export([init/4, update_value/1, update_value_crdt/1, loop/5, start/5, start/6, reset/3, reset_crdt/5]).

-record(worker, {id :: term(), lnk:: term() , nkeys :: integer(), stats :: term(), bucket :: binary() | {binary(),binary()}}).

-define(KEY, <<"KEY">>).
-define(MAX_INT, 2147483648).
-define(MIN_INTERVAL, 100).
-define(MILLIS, 1000).
-define(DEFAULT_TIMEOUT, 3000).

-type worker() :: #worker{}. %% The record/type containing the entire Riak object.
-export_type([worker/0]).

init(Stats, Address, Bucket,Id) ->
  {ok, Pid} = riakc_pb_socket:start_link(Address, 8087),
  #worker{id = Id, lnk = Pid, stats = Stats, bucket = Bucket}.


% Update and reset functions for Strong consistency and Eventual consistency 
%	- maybe we do not need this after all, we can simply use the CRDT version.
reset(InitValue, Address, Bucket) ->
  Worker = init(nil, Address, Bucket, nil),
  Result = riakc_pb_socket:get(Worker#worker.lnk, Bucket, ?KEY,[],?DEFAULT_TIMEOUT),
  NewObj = case Result of
             {ok, Fetched} ->
               riakc_obj:update_value(Fetched, integer_to_binary(InitValue));
             {error,notfound} ->
               riakc_obj:new(Bucket,
                 ?KEY, integer_to_binary(InitValue))
           end,
  riakc_pb_socket:put(Worker#worker.lnk, NewObj,[],?DEFAULT_TIMEOUT),
  end_reset.

update_value(Worker) ->
  Result = riakc_pb_socket:get(Worker#worker.lnk,Worker#worker.bucket, ?KEY,[],?DEFAULT_TIMEOUT)  ,
  case Result of
    {ok, Fetched} ->
      Int = readIntegerValue(Fetched),
	  UpdObj = riakc_obj:update_value(Fetched, list_to_binary(integer_to_list(Int-1))),
      case Int > 0 of
        true -> StartOp = now(),
          PutResult = riakc_pb_socket:put(Worker#worker.lnk, UpdObj,[],?DEFAULT_TIMEOUT),
          Latency = timer:now_diff(now(),StartOp),
          case PutResult of
            ok ->
              Worker#worker.stats ! {Int, Latency, now(), success},
              DueTime=?MIN_INTERVAL-(Latency div ?MILLIS),
              case DueTime > 0 of
				  true -> timer:sleep(DueTime);
				  _ -> nothing
			  end,
              {ok,Int-1};
            {error, _} -> Worker#worker.stats ! {Int, Latency, now(), fail},fail;
            _ -> fail
          end;
        false -> {ok,Int}
      end
  end.


readIntegerValue(RiakObj) ->
  list_to_integer(binary_to_list(riakc_obj:get_value(RiakObj))).

% Update and reset function for CRDT version

reset_crdt(InitValue, Address, Bucket,Id, OtherIds) ->
    Worker = init(nil, Address, Bucket,Id),
    Result = riakc_pb_socket:get(Worker#worker.lnk, Bucket, ?KEY,[],?DEFAULT_TIMEOUT),
	Counter = nncounter:new(Id,InitValue),
	PartitionedCounter = lists:foldl(fun(OtherId,InCounter) -> 
		{ok, OutCounter} = nncounter:transfer(Id,OtherId,InitValue div length(OtherIds)+1,InCounter),
		OutCounter end, Counter, OtherIds),
    NewObj = case Result of
               {ok, Fetched} ->
                 riakc_obj:update_value(Fetched, nncounter:to_binary(PartitionedCounter));
               {error,notfound} ->
                 riakc_obj:new(Bucket, ?KEY, nncounter:to_binary(PartitionedCounter))
             end,
    riakc_pb_socket:put(Worker#worker.lnk, NewObj,[],?DEFAULT_TIMEOUT),
end_reset_crdt.

update_value_crdt(Worker) ->
  Result = riakc_pb_socket:get(Worker#worker.lnk,Worker#worker.bucket, ?KEY,[],?DEFAULT_TIMEOUT)  ,
  case Result of
    {ok, Fetched} ->
      CRDT = nncounter:from_binary(riakc_obj:get_value(Fetched)),
	  Int = nncounter:value(CRDT),
	  case Int > 0 of
		  true ->  
			  {ok,New_CRDT} = nncounter:decrement(Worker#worker.id,1,CRDT),
			  StartOp = now(),
			  PutResult = riakc_pb_socket:put(Worker#worker.lnk, riakc_obj:update_value(Fetched,nncounter:to_binary(New_CRDT)),[],?DEFAULT_TIMEOUT),
			  Latency = timer:now_diff(now(),StartOp),
			  case PutResult of
				  ok ->
					  Worker#worker.stats ! {Int, Latency, now(), success},
					  DueTime=?MIN_INTERVAL-(Latency div ?MILLIS),
					  case DueTime > 0 of
						  true -> timer:sleep(DueTime);
						  _ -> nothing
					  end,
					  {ok,Int-1};
				 {error, _} -> Worker#worker.stats ! {Int, Latency, now(), fail},fail;
				 _ -> fail
			  end;
		  false -> {ok,Int}
	  end
	end.


% The LOOP functions, that execute the workload

loop(_,_, _, Value, ParentPid) when Value =< 0 ->
  ParentPid ! end_loop;

loop(Worker,Successful, Retries, Value, ParentPid) ->
  case update_value_crdt(Worker) of
    {ok, UpdValue} -> loop(Worker,Successful+1,Retries,UpdValue,ParentPid);
    fail -> loop(Worker,Successful, Retries+1,Value,ParentPid)
  end.


% START and STOP nodes

start(_, 0, _, _, _) -> started;

start(Pid, N, Stats, Address, Bucket) ->
  Worker = init(Stats, Address, Bucket,noID),
  spawn(worker_sc,loop,[Worker,0,0,?MAX_INT,Pid]),
  start(Pid, N-1, Stats, Address, Bucket).

start(init,N,Finished, Stats, Address,Bucket) ->
	start(self(), N, Stats, Address,Bucket),
	start(wait_proc,N,Finished, Stats, Address,Bucket);

start(wait_proc,N, Finished, Stats, _, _) when Finished == N ->
	io:format("Sent Finish"),
	Stats ! finish,
	timer:sleep(2000);


start(wait_proc,N,Finished, Stats, Address,Bucket) ->	
	receive
		end_loop -> start(wait_proc, N, Finished +1, Stats, Address, Bucket)
	end.


