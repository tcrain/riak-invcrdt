%%%-------------------------------------------------------------------
%%% @author balegas
%%% @copyright (C) 2013, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 22. Nov 2013 21:49
%%%-------------------------------------------------------------------
-module(client_stats).
-author("balegas").

%% API
-export([stats/7, start/2]).

%% 5 second interval
-define(INTERVAL, 5000000).
-define(MILLIS, 1000).

start(Clients,InitValue) ->
  spawn(client_stats, stats, [orddict:new(),0,0,999999,now(),Clients,InitValue]).


stats(Bins,Success,Fail,MinValue,StartTime,Clients,InitValue) ->
receive
  {Value, Latency, Timestamp, Status} ->
    case Status of
      success ->
        NewBins = orddict:update(timer:now_diff(Timestamp,StartTime) div ?INTERVAL,
          fun({Sum,Count}) -> {Sum+Latency,Count+1} end, {0,0}, Bins),
        stats(NewBins,Success+1,Fail, min(Value,MinValue), StartTime,Clients,InitValue);
      fail -> stats(Bins,Success,Fail+1, min(Value,MinValue),StartTime,Clients,InitValue)
    end;
    finish-> io:format("T\tAVG_L\tCLIENTS:~p\tINIT_VALUE:~p~n",[Clients,InitValue]),
       orddict:fold(fun(K,{Sum,Count},any) ->
        io:format("~p\t~p~n",[K,Sum/Count/?MILLIS]),any end,any,Bins),
      io:format("Success:~p\tFail:~p\t~n",[Success,Fail]),
      io:format("START_TIME:~p\tEND_TIME:~p\t~n",[StartTime,now()])
end.
