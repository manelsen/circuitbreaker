-module(circuit_breaker_global_ffi).
-export([global_put/2, global_get/1, global_has/1, global_delete/1, safe_is_process_alive/1]).

global_put(Key, Value) ->
    persistent_term:put(Key, Value),
    nil.

global_get(Key) ->
    try persistent_term:get(Key)
    catch
        error:badarg -> undefined
    end.

global_has(Key) ->
    try
        _ = persistent_term:get(Key),
        true
    catch
        error:badarg -> false
    end.

global_delete(Key) ->
    persistent_term:erase(Key),
    nil.

safe_is_process_alive(Subject) ->
    Pid = case Subject of
        {subject, P, _} -> P;
        _ -> Subject
    end,
    try erlang:is_process_alive(Pid) of
        Result -> Result
    catch
        _:_ -> false
    end.
