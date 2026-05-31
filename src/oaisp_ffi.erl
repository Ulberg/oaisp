-module(oaisp_ffi).
-export([run/1, read_file/1, write_file/2, rename/2, delete/1]).

%% Run a shell command, capturing stdout (binary) and the exit status. stderr
%% is not redirected, so the child's progress output stays on the parent's
%% stderr and never mixes into the captured stdout. Returns {Status, Output}.
run(Command) ->
    Port = open_port(
        {spawn, binary_to_list(Command)},
        [stream, binary, exit_status, hide]
    ),
    collect(Port, <<>>).

collect(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect(Port, <<Acc/binary, Data/binary>>);
        {Port, {exit_status, Status}} ->
            {Status, Acc}
    end.

%% File access over the OTP `file` module. Each returns a value shaped like a
%% Gleam Result: {ok, _} | {error, ReasonBinary}.
read_file(Path) ->
    case file:read_file(Path) of
        {ok, Bytes} -> {ok, Bytes};
        {error, Reason} -> {error, reason(Reason)}
    end.

write_file(Path, Data) ->
    case file:write_file(Path, Data) of
        ok -> {ok, nil};
        {error, Reason} -> {error, reason(Reason)}
    end.

rename(Source, Destination) ->
    case file:rename(Source, Destination) of
        ok -> {ok, nil};
        {error, Reason} -> {error, reason(Reason)}
    end.

delete(Path) ->
    case file:delete(Path) of
        ok -> {ok, nil};
        {error, Reason} -> {error, reason(Reason)}
    end.

reason(Reason) when is_atom(Reason) -> atom_to_binary(Reason, utf8);
reason(Reason) -> list_to_binary(io_lib:format("~p", [Reason])).
