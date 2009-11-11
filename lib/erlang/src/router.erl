%%%-------------------------------------------------------------------
%%% File    : router.erl
%%% Author  : Ari Lerner
%%% Description : 
%%%
%%% Created :  Thu Oct  8 18:29:29 PDT 2009
%%%-------------------------------------------------------------------

-module (router).
-include ("router.hrl").
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> router_sup:start_link([]).

stop(_State) -> ok.