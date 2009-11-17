%%%-------------------------------------------------------------------
%%% File    : mesh_util.erl
%%% Author  : Ari Lerner
%%% Description : 
%%%
%%% Created :  Tue Nov 17 14:55:32 PST 2009
%%%-------------------------------------------------------------------

-module (mesh_util).

-export([
         init_db_slave/1,
         get_random_pid/1
        ]).

init_db_slave(SeedNode) ->
    db:start(),
    mnesia:change_config(extra_db_nodes, [SeedNode]),
    mnesia:change_table_copy_type(schema, node(), disc_copies),
    Tabs = mnesia:system_info(tables) -- [schema],
    [mnesia:add_table_copy(Tab, node(), disc_copies) || Tab <- Tabs].

get_random_pid(Name) ->
  L = case pg2:get_members(Name) of
    {error, _} ->
      timer:sleep(100),
      pg2:get_members(Name);
    Other when is_list(Other) ->
      Other
    end,
    if 
      L == [] ->
        {error, {no_process, Name}};
        true ->
          {_,_,X} = erlang:now(),
          {ok, lists:nth((X rem length(L)) + 1, L)}
    end.
