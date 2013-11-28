-module(sm_SUITE).
-compile(export_all).

-include_lib("exml/include/exml.hrl").
-include_lib("escalus/include/escalus.hrl").
-include_lib("common_test/include/ct.hrl").

-define(MOD_SM, mod_stream_management).

%%--------------------------------------------------------------------
%% Suite configuration
%%--------------------------------------------------------------------

all() ->
    [{group, negotiation},
     {group, server_acking},
     {group, client_acking},
     {group, reconnection}].

groups() ->
    [{negotiation, [], [server_announces_sm,
                        server_enables_sm_before_session,
                        server_enables_sm_after_session,
                        server_returns_failed_after_start,
                        server_returns_failed_after_auth]},
     {server_acking,
      [shuffle, {repeat, 5}], [basic_ack,
                               h_ok_before_session,
                               h_ok_after_session_enabled_before_session,
                               h_ok_after_session_enabled_after_session,
                               h_ok_after_a_chat]},
     {client_acking,
      [shuffle, {repeat, 5}], [client_acks_more_than_sent,
                               too_many_unacked_stanzas,
                               server_requests_ack]},
     {reconnection, [], [resend_unacked_on_reconnection]}].

suite() ->
    escalus:suite().

%%--------------------------------------------------------------------
%% Init & teardown
%%--------------------------------------------------------------------

init_per_suite(Config) ->
    NewConfig = escalus_ejabberd:setup_option(ack_freq(never), Config),
    escalus:init_per_suite(NewConfig).

end_per_suite(Config) ->
    NewConfig = escalus_ejabberd:reset_option(ack_freq(never), Config),
    escalus:end_per_suite(NewConfig).

init_per_group(client_acking, Config) ->
    escalus_users:update_userspec(Config, alice, stream_management, true);
init_per_group(reconnection, Config) ->
    escalus_users:update_userspec(Config, alice, stream_management, true);
init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.

init_per_testcase(h_ok_after_a_chat = CaseName, Config) ->
    NewConfig = escalus_users:update_userspec(Config, alice,
                                              stream_management, true),
    escalus:init_per_testcase(CaseName, NewConfig);
init_per_testcase(too_many_unacked_stanzas = CaseName, Config) ->
    NewConfig = escalus_ejabberd:setup_option(buffer_max(2), Config),
    escalus:init_per_testcase(CaseName, NewConfig);
init_per_testcase(server_requests_ack = CaseName, Config) ->
    NewConfig = escalus_ejabberd:setup_option(ack_freq(2), Config),
    escalus:init_per_testcase(CaseName, NewConfig);
init_per_testcase(CaseName, Config) ->
    escalus:init_per_testcase(CaseName, Config).

end_per_testcase(too_many_unacked_stanzas = CaseName, Config) ->
    NewConfig = escalus_ejabberd:reset_option(buffer_max(2), Config),
    escalus:end_per_testcase(CaseName, NewConfig);
end_per_testcase(server_requests_ack = CaseName, Config) ->
    NewConfig = escalus_ejabberd:reset_option(ack_freq(2), Config),
    escalus:end_per_testcase(CaseName, NewConfig);
end_per_testcase(CaseName, Config) ->
    escalus:end_per_testcase(CaseName, Config).

%%--------------------------------------------------------------------
%% Tests
%%--------------------------------------------------------------------

server_announces_sm(Config) ->
    AliceSpec = [{stream_management, true}
                 | escalus_users:get_options(Config, alice)],
    {ok, _, Props, Features} = escalus_connection:start(AliceSpec,
                                                        [start_stream]),
    true = escalus_session:can_use_stream_management(Props, Features).

server_enables_sm_before_session(Config) ->
    AliceSpec = [{stream_management, true}
                 | escalus_users:get_options(Config, alice)],
    {ok, _, _, _} = escalus_connection:start(AliceSpec, [start_stream,
                                                         authenticate,
                                                         bind,
                                                         stream_management]).

server_enables_sm_after_session(Config) ->
    AliceSpec = [{stream_management, true}
                 | escalus_users:get_options(Config, alice)],
    {ok, _, _, _} = escalus_connection:start(AliceSpec, [start_stream,
                                                         authenticate,
                                                         bind,
                                                         session,
                                                         stream_management]).

server_returns_failed_after_start(Config) ->
    server_returns_failed(Config, []).

server_returns_failed_after_auth(Config) ->
    server_returns_failed(Config, [authenticate]).

server_returns_failed(Config, ConnActions) ->
    AliceSpec = [{stream_management, true}
                 | escalus_users:get_options(Config, alice)],
    {ok, Alice, _, _} = escalus_connection:start(AliceSpec,
                                                 [start_stream]
                                                 ++ ConnActions),
    escalus_connection:send(Alice, escalus_stanza:enable_sm()),
    escalus:assert(is_failed,
                   escalus_connection:get_stanza(Alice, enable_sm_failed)).

basic_ack(Config) ->
    AliceSpec = [{stream_management, true}
                 | escalus_users:get_options(Config, alice)],
    {ok, Alice, _, _} = escalus_connection:start(AliceSpec,
                                                 [start_stream,
                                                  authenticate,
                                                  bind,
                                                  session,
                                                  stream_management]),
    escalus_connection:send(Alice, escalus_stanza:roster_get()),
    escalus:assert(is_roster_result,
                   escalus_connection:get_stanza(Alice, roster_result)),
    escalus_connection:send(Alice, escalus_stanza:sm_request()),
    escalus:assert(is_ack,
                   escalus_connection:get_stanza(Alice, stream_mgmt_ack)).

%% Test that "h" value is valid when:
%% - SM is enabled *before* the session is established
%% - <r/> is sent *before* the session is established
h_ok_before_session(Config) ->
    AliceSpec = [{stream_management, true}
                 | escalus_users:get_options(Config, alice)],
    {ok, Alice, _, _} = escalus_connection:start(AliceSpec,
                                                 [start_stream,
                                                  authenticate,
                                                  bind,
                                                  stream_management]),
    escalus_connection:send(Alice, escalus_stanza:sm_request()),
    escalus:assert(is_ack, [0],
                   escalus_connection:get_stanza(Alice, stream_mgmt_ack)).

%% Test that "h" value is valid when:
%% - SM is enabled *before* the session is established
%% - <r/> is sent *after* the session is established
h_ok_after_session_enabled_before_session(Config) ->
    AliceSpec = [{stream_management, true}
                 | escalus_users:get_options(Config, alice)],
    {ok, Alice, _, _} = escalus_connection:start(AliceSpec,
                                                 [start_stream,
                                                  authenticate,
                                                  bind,
                                                  stream_management,
                                                  session]),
    escalus_connection:send(Alice, escalus_stanza:sm_request()),
    escalus:assert(is_ack, [1],
                   escalus_connection:get_stanza(Alice, stream_mgmt_ack)).

%% Test that "h" value is valid when:
%% - SM is enabled *after* the session is established
%% - <r/> is sent *after* the session is established
h_ok_after_session_enabled_after_session(Config) ->
    AliceSpec = [{stream_management, true}
                 | escalus_users:get_options(Config, alice)],
    {ok, Alice, _, _} = escalus_connection:start(AliceSpec,
                                                 [start_stream,
                                                  authenticate,
                                                  bind,
                                                  session,
                                                  stream_management]),
    escalus_connection:send(Alice, escalus_stanza:roster_get()),
    escalus:assert(is_roster_result,
                   escalus_connection:get_stanza(Alice, roster_result)),
    escalus_connection:send(Alice, escalus_stanza:sm_request()),
    escalus:assert(is_ack, [1],
                   escalus_connection:get_stanza(Alice, stream_mgmt_ack)).

%% Test that "h" value is valid after exchanging a few messages.
h_ok_after_a_chat(Config) ->
    escalus:story(Config, [{alice,1}, {bob,1}], fun(Alice, Bob) ->
        escalus:send(Alice, escalus_stanza:chat_to(Bob, <<"Hi, Bob!">>)),
        escalus:assert(is_chat_message, [<<"Hi, Bob!">>],
                       escalus:wait_for_stanza(Bob)),
        escalus:send(Bob, escalus_stanza:chat_to(Alice, <<"Hi, Alice!">>)),
        escalus:assert(is_chat_message, [<<"Hi, Alice!">>],
                       escalus:wait_for_stanza(Alice)),
        escalus:send(Bob, escalus_stanza:chat_to(Alice, <<"How's life?">>)),
        escalus:assert(is_chat_message, [<<"How's life?">>],
                       escalus:wait_for_stanza(Alice)),
        escalus:send(Alice, escalus_stanza:chat_to(Bob, <<"Pretty !@#$%^$">>)),
        escalus:assert(is_chat_message, [<<"Pretty !@#$%^$">>],
                       escalus:wait_for_stanza(Bob)),
        escalus:send(Alice, escalus_stanza:sm_request()),
        escalus:assert(is_ack, [3], escalus:wait_for_stanza(Alice)),
        %% Ack, so that unacked messages don't go into offline store.
        escalus:send(Alice, escalus_stanza:sm_ack(3))
    end).

client_acks_more_than_sent(Config) ->
    escalus:story(Config, [{alice,1}], fun(Alice) ->
        escalus:send(Alice, escalus_stanza:sm_ack(5)),
        escalus:assert(is_stream_error, [<<"policy-violation">>,
                                         <<"h attribute too big">>],
                       escalus:wait_for_stanza(Alice))
    end).

too_many_unacked_stanzas(Config) ->
    escalus:story(Config, [{alice,1}, {bob,1}], fun(Alice, Bob) ->
        Msg = escalus_stanza:chat_to(Alice, <<"Hi, Alice!">>),
        [escalus:send(Bob, Msg) || _ <- lists:seq(1,2)],
        escalus:wait_for_stanzas(Alice, 2),
        escalus:assert(is_stream_error, [<<"resource-constraint">>,
                                         <<"too many unacked stanzas">>],
                       escalus:wait_for_stanza(Alice))
    end),
    discard_offline_messages(Config, alice).

server_requests_ack(Config) ->
    escalus:story(Config, [{alice,1}, {bob,1}], fun(Alice, Bob) ->
        escalus:send(Bob, escalus_stanza:chat_to(Alice, <<"Hi, Alice!">>)),
        escalus:assert(is_chat_message, [<<"Hi, Alice!">>],
                       escalus:wait_for_stanza(Alice)),
        escalus:assert(is_ack_request, escalus:wait_for_stanza(Alice))
    end),
    discard_offline_messages(Config, alice).

resend_unacked_on_reconnection(Config) ->
    Messages = [<<"msg-1">>, <<"msg-2">>, <<"msg-3">>],
    escalus:story(Config, [{alice, 1}, {bob, 1}], fun(Alice, Bob) ->
        %% Bob sends some messages to Alice.
        [escalus:send(Bob, escalus_stanza:chat_to(Alice, Msg))
         || Msg <- Messages],
        %% Alice receives the messages.
        Stanzas = escalus:wait_for_stanzas(Alice, 3),
        [escalus:assert(is_chat_message, [Msg], Stanza)
         || {Msg, Stanza} <- lists:zip(Messages, Stanzas)]
        %% Alice disconnects without acking the messages.
    end),
    %% Messages go to the offline store.
    %% Alice receives the messages from the offline store.
    %% This is done without escalus:story() as a story() performs
    %% an is_presence assertion on the first stanza after connection
    %% initiation which fails as the message from offline store will come
    %% before that presence.
    AliceSpec = escalus_users:get_options(Config, alice),
    {ok, Alice, _, _} = escalus_connection:start(AliceSpec),
    escalus_connection:send(Alice, escalus_stanza:presence(<<"available">>)),
    Stanzas = [escalus_connection:get_stanza(Alice, {msg,I})
               || I <- lists:seq(1, 3)],
    [escalus:assert(is_chat_message, [Msg], Stanza)
     || {Msg, Stanza} <- lists:zip(Messages, Stanzas)],
    %% Alice acks the delayed messages so they won't go again
    %% to the offline store.
    escalus_connection:send(Alice, escalus_stanza:sm_ack(3)).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

discard_offline_messages(Config, UserName) ->
    discard_offline_messages(Config, UserName, 1).

discard_offline_messages(Config, UserName, H) when is_atom(UserName) ->
    Spec = escalus_users:get_options(Config, UserName),
    {ok, User, _, _} = escalus_connection:start(Spec),
    escalus_connection:send(User, escalus_stanza:presence(<<"available">>)),
    discard_offline_messages(Config, User, H);
discard_offline_messages(Config, User, H) ->
    Stanza = escalus_connection:get_stanza(User, maybe_offline_msg),
    escalus_connection:send(User, escalus_stanza:sm_ack(H)),
    case escalus_pred:is_presence(Stanza) of
        true ->
            ok;
        false ->
            discard_offline_messages(Config, User, H+1)
    end.

buffer_max(BufferMax) ->
    {buffer_max,
     fun () ->
             escalus_ejabberd:rpc(?MOD_SM, get_buffer_max, [unset])
     end,
     fun (unset) ->
             ct:pal("buffer_max was not set - setting to 'undefined'"),
             escalus_ejabberd:rpc(?MOD_SM, set_buffer_max, [undefined]);
         (V) ->
             escalus_ejabberd:rpc(?MOD_SM, set_buffer_max, [V])
     end,
     BufferMax}.

ack_freq(AckFreq) ->
    {ack_freq,
     fun () ->
             escalus_ejabberd:rpc(?MOD_SM, get_ack_freq, [unset])
     end,
     fun (unset) ->
             ct:pal("ack_freq was not set - setting to 'undefined'"),
             escalus_ejabberd:rpc(?MOD_SM, set_ack_freq, [undefined]);
         (V) ->
             escalus_ejabberd:rpc(?MOD_SM, set_ack_freq, [V])
     end,
     AckFreq}.
