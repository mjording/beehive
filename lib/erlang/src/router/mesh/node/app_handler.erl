%%%-------------------------------------------------------------------
%%% File    : app_handler.erl
%%% Author  : Ari Lerner
%%% Description : 
%%%
%%% Created :  Thu Nov 19 12:45:16 PST 2009
%%%-------------------------------------------------------------------

-module (app_handler).
-include ("router.hrl").
-include ("common.hrl").
-behaviour(gen_server).

%% API
-export([
  start_link/0,
  stop/0,
  start_new_instance/2,
  stop_instance/3,
  can_deploy_new_app/0
]).


%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
  max_backends,             % maximum number of backends on this host
  available_ports,          % available ports on this node
  current_backends  = []    % backends hosted on this app_handler
}).
-define(SERVER, ?MODULE).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(?SERVER, {stop}).
  
can_deploy_new_app() ->
  gen_server:call(?SERVER, {can_deploy_new_app}).
  
start_new_instance(App, From) ->
  gen_server:call(?SERVER, {start_new_instance, App, From}).

stop_instance(Backend, App, From) ->
  gen_server:call(?SERVER, {stop_instance, Backend, App, From}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([]) ->
  process_flag(trap_exit, true),
  
  Opts = [named_table, set],
  ets:new(?MODULE, Opts),
  
  MaxBackends     = ?MAX_BACKENDS_PER_HOST,
  AvailablePorts  = lists:seq(?STARTING_PORT, ?STARTING_PORT + MaxBackends),
  
  {ok, #state{
    max_backends = MaxBackends,
    available_ports = AvailablePorts
  }}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%-------------------------------------------------------------------- 
handle_call({start_new_instance, App, From}, _From, #state{current_backends = CurrBackends, available_ports = AvailablePorts} = State) ->
  Port = hd(AvailablePorts),
  ?LOG(info, "internal_start_new_instance(~p, ~p, ~p)", [App, Port, From]),
  Backend = internal_start_new_instance(App, Port, From),
  NewAvailablePorts = lists:delete(Port, AvailablePorts),
  {reply, ok, State#state{current_backends = [Backend|CurrBackends], available_ports = NewAvailablePorts}};
  
handle_call({stop_instance, Backend, App, From}, _From, #state{current_backends = CurrBackends, available_ports = AvailablePorts} = State) ->
  Port = Backend#backend.port,
  internal_stop_instance(Backend, App, From),
  NewBackends = lists:keydelete(Backend#backend.id, 1, CurrBackends),
  NewAvailablePorts = [Port|AvailablePorts],
  {reply, ok, State#state{current_backends = NewBackends, available_ports = NewAvailablePorts}};
  
handle_call({can_deploy_new_app}, _From, #state{current_backends = Curr, max_backends = Max} = State) ->
  Reply = (length(Curr) =< Max),
  {reply, Reply, State};
handle_call(_Request, _From, State) ->
  Reply = ok,
  {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(Info, State) ->
  ?LOG(info, "~p caught info: ~p", [?MODULE, Info]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------


% Start a new instance of the application
internal_start_new_instance(App, Port, From) ->
  ?LOG(info, "App ~p", [App]),
  
  TemplateCommand = App#app.start_command,
  ?LOG(info, "start command ~p", [TemplateCommand]),
  
  RealCmd = template_command_string(TemplateCommand, [
                                                        {"[[PORT]]", misc_utils:to_list(Port)},
                                                        {"[[GROUP]]", App#app.group},
                                                        {"[[USER]]", App#app.user}
                                                      ]),
  % START INSTANCE
  % port_handler:start("thin -R beehive.ru --port 5000 start", "/Users/auser/Development/erlang/mine/router/test/fixtures/apps").
  ?LOG(info, "Starting on port ~p as ~p:~p with ~p", [Port, App#app.group, App#app.user, RealCmd]),
  Pid = port_handler:start(RealCmd, App#app.path, self()),
  Host = host:myip(),
  Id = {App#app.name, Host, Port},
  
  Backend  = #backend{
    id                      = Id,
    app_name                = App#app.name,
    host                    = Host,
    port                    = Port,
    status                  = pending,
    pid                     = Pid,
    start_time              = date_util:now_to_seconds()
  },
  
  From ! {started_backend, Backend},
  ets:insert(?MODULE, {Id, Backend}),
  Backend.

% kill the instance of the application  
internal_stop_instance(Backend, App, From) ->
  RealCmd = template_command_string(App#app.stop_command, [
                                                        {"[[PORT]]", erlang:integer_to_list(Backend#backend.port)},
                                                        {"[[GROUP]]", App#app.group},
                                                        {"[[USER]]", App#app.user}
                                                      ]),

  Backend#backend.pid ! {stop, RealCmd},
  os:cmd(RealCmd),
  case ets:lookup(?MODULE, {App#app.name, Backend#backend.host, Backend#backend.port}) of
    [{Key, _B}] ->
      ets:delete(?MODULE, Key);
    _ -> true
  end,
  From ! {stopped_backend, Backend}.

% turn the command string from the comand string with the values
% of [[KEY]] replaced by the corresponding proplist element of
% the format:
%   {[[PORT]], "80"}
template_command_string(OriginalCommand, []) -> OriginalCommand;
template_command_string(OriginalCommand, [{Str, Replace}|T]) ->
  NewCommand = string_utils:gsub(OriginalCommand, Str, Replace),
  template_command_string(NewCommand, T).