%%%-------------------------------------------------------------------
%%% @author balegas
%%% @copyright (C) 2013, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 14. Nov 2013 15:37
%%%-------------------------------------------------------------------

%% Periodically propagates the state of a 'key' in the 'origin' bucket to a list of 'remote' buckets.
%% Periodically checks if a new value has been stored in a 'buffer' bucket, solves concurrent accesses
%% and applies it to the 'origin' bucket.
%% -- 'remote' buckets should use eventual consistency and 'origin' use strong consistency.
%% -- Should also trasnfers permissions between replicas.


%% Needs to clear previous buffered values

-module(replication_agent).
-author("balegas").

%% API
-export([init/6, loop/6]).

-define(LOOP_TIME, 10000).

loop(Connection, Origin, Remote, Buffer, Key, Id) ->
	Result = riakc_pb_socket:get(Connection, Buffer, Key),	
	receive
		updateLocal -> 
			io:format("Update Local~n"),
			update_local(Connection, Origin, Result),
			%%What happens when delete is concurrent with other operations?
			%%riakc_pb_socket:delete(Connection, Buffer, Key),
			erlang:send_after(?LOOP_TIME, self(), updateLocal),
			loop(Connection, Origin, Remote, Buffer, Key, Id);
		updateRemote -> io:format("Update remote~n"),
			update_remote(Connection,Origin,Remote,Key),
   	 		erlang:send_after(?LOOP_TIME, self(), updateRemote),
			loop(Connection, Origin, Remote, Buffer, Key, Id)
	end.
	
update_local(Connection, Origin, Result) ->
	case Result of
		{ok, Fetched} ->
			CRDT = merge_values(nncounter:new(nil,0),
				lists:map(fun(O) -> nncounter:from_binary(O) end,
					riack_obj:get_values(Fetched))),
			io:format("UPDATE-LOCAL: Merged Values ~p~n",[CRDT]),
			UpdtObj = riakc_obj:update_value(Fetched, nncounter:to_binary(CRDT)),
			store(Connection,Origin,UpdtObj);
		{error,notfound} -> ok
	end.
	
update_remote(Connection, Origin, Remote, Key) ->
	LocalObject = riakc_pb_socket:get(Connection, Origin, Key),	
	RemoteObject = case riakc_pb_socket:get(Connection, Remote, Key) of 
		{ok, Fetched} ->
			CRDT = merge_values(nncounter:new(nil,0),
				lists:map(fun(O) -> nncounter:from_binary(O) end,
					riack_obj:get_values(Fetched))),
			io:format("UPDATE-REMOTE: Merged Values ~p~n",[CRDT]),
			riakc_obj:update_value(Fetched, nncounter:to_binary(CRDT));
		{error,notfound} -> riakc_obj:new(Remote, Key, 
			nncounter:to_binary(nncounter:new(nil,0)))
	end,
	LocalCRDT = riack_obj:get_values(LocalObject),
	RemoteCRDT = riack_obj:get_values(RemoteObject), 
	UpdtRemoteObject=riakc_obj:update_value(RemoteObject, nncounter:to_binary(merge_values(LocalCRDT,RemoteCRDT))),
	store(Connection,Remote,UpdtRemoteObject).
	
init(Address, Origin, Remote, Buffer, Key, Id) ->
	  {ok, Connection} = riakc_pb_socket:start_link(Address, 8087),
	  Pid = spawn(replication_agent,loop,[Connection, Origin, Remote, Buffer, Key,Id]),
	  erlang:send_after(?LOOP_TIME, Pid, updateLocal),
	  erlang:send_after(?LOOP_TIME, Pid, updateRemote).

merge_values(Local,RemoteList) ->
	lists:foldl(fun(O,L) -> nncounter:merge(L,O) end, Local, RemoteList).

%% Repeats the operation until successful
store(Connection,Destination,Object) -> 
	  case riakc_pb_socket:put(Connection, Object) of
		  {ok, _ } -> ok;
		  {error, _ } -> store(Connection,Destination,Object)
	  end.