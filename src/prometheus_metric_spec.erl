-module(prometheus_metric_spec).

-export([get_value/2,
         get_value/3,
         fetch_value/2,
         registry/1,
         name/1,
         labels/1,
         help/1,
         use_call/1,
         duration_unit/1,
         extract_common_params/1]).

-ifdef(TEST).
-export([validate_metric_name/1,
         validate_metric_label_names/1,
         validate_metric_help/1]).
-endif.

-export_type([spec/0]).

%%====================================================================
%% Types
%%====================================================================

-type spec() :: proplists:proplist().

%%====================================================================
%% Macros
%%====================================================================

-define(DURATION_UNITS, [{"microseconds", microseconds},
                         {"milliseconds", milliseconds},
                         {"seconds", seconds},
                         {"minutes", minutes},
                         {"hours", hours},
                         {"days", days}]).

%%====================================================================
%% Public API
%%====================================================================

%% @private
registry(Spec) ->
  get_value(registry, Spec, default).

%% @private
name(Spec) ->
  Name = fetch_value(name, Spec),
  validate_metric_name(Name).

%% @private
labels(Spec) ->
  Labels = get_value(labels, Spec, []),
  validate_metric_label_names(Labels).

%% @private
help(Spec) ->
  Help = fetch_value(help, Spec),
  validate_metric_help(Help).

%% @private
data(Spec) ->
  get_value(data, Spec).

%% @private
use_call(Spec) ->
  get_value(use_call, Spec, false).

%% @private
duration_unit(Spec) ->
  Name = to_string(name(Spec)),

  NameDU = duration_unit_from_name(Name),

  case duration_unit_from_spec(Spec) of
    false -> undefined;
    undefined -> NameDU;
    NameDU -> NameDU;
    DU -> case NameDU of
            undefined -> DU;
            _ -> erlang:error({duration_unit_no_match, NameDU, DU})
          end
  end.

duration_unit_from_name(Name) ->
  duration_unit_from_name(Name, ?DURATION_UNITS).

duration_unit_from_name(Name, [{SDU, DU}|Rest]) ->
  case string:rstr(Name, SDU) of
    0 -> duration_unit_from_name(Name, Rest);
    _ -> DU
  end;
duration_unit_from_name(_, []) ->
  undefined.

duration_unit_from_spec(Spec) ->
  SDU = get_value(duration_unit, Spec, undefined),
  validate_duration_unit(SDU).

validate_duration_unit(false) ->
  false;
validate_duration_unit(undefined) ->
  undefined;
validate_duration_unit(SDU) ->
  case lists:any(fun({_, DU}) ->
                     DU == SDU
                 end,
                 ?DURATION_UNITS) of
    true ->
      SDU;
    _ ->
      erlang:error({unknown_duration_unit, SDU})
  end.

%% @private
extract_common_params(Spec) ->
  Registry = registry(Spec),

  Name = name(Spec),

  Labels = labels(Spec),

  Help = help(Spec),

  Data = data(Spec),

  UseCall = use_call(Spec),

  DurationUnit = duration_unit(Spec),

  {Registry, Name, Labels, Help, UseCall, DurationUnit, Data}.

-spec get_value(Key :: atom(), Spec :: spec()) -> any().
%% @private
%% @equiv get_value(Key, Spec, undefined)
get_value(Key, Spec) ->
  get_value(Key, Spec, undefined).

-spec get_value(Key :: atom(), Spec :: spec(), Default :: any()) -> any().
%% @private
get_value(Key, Spec, Default) ->
  proplists:get_value(Key, Spec, Default).

-spec fetch_value(Key :: atom(), Spec :: spec()) -> any() | no_return().
%% @private
fetch_value(Key, Spec) ->
  case proplists:get_value(Key, Spec) of
    undefined ->
      erlang:error({missing_metric_spec_key, Key, Spec});
    Value ->
      Value
  end.

%%====================================================================
%% Private Parts
%%===================================================================

%% @private
validate_metric_name(RawName) when is_atom(RawName) ->
  validate_metric_name(RawName, atom_to_list(RawName));
validate_metric_name(RawName) when is_binary(RawName) ->
  validate_metric_name(RawName, binary_to_list(RawName));
validate_metric_name(RawName) when is_list(RawName) ->
  validate_metric_name(RawName, RawName);
validate_metric_name(RawName) ->
  erlang:error({invalid_metric_name, RawName, "metric name is not a string"}).

%% @private
validate_metric_name(RawName, ListName) ->
  case io_lib:printable_unicode_list(ListName) of
    true ->
      Regex = "^[a-zA-Z_:][a-zA-Z0-9_:]*$",
      case re:run(ListName, Regex) of
        {match, _} ->
          RawName;
        nomatch ->
          erlang:error({invalid_metric_name, RawName,
                        "metric name doesn't match regex " ++ Regex})
      end;
    false ->
      erlang:error({invalid_metric_name, RawName,
                    "metric name is invalid string"})
  end.

%% @private
validate_metric_label_names(RawLabels) when is_list(RawLabels) ->
  lists:map(fun validate_metric_label_name/1, RawLabels);
validate_metric_label_names(RawLabels) ->
  erlang:error({invalid_metric_labels, RawLabels, "not list"}).

%% @private
validate_metric_label_name(RawName) when is_atom(RawName) ->
  validate_metric_label_name(atom_to_list(RawName));
validate_metric_label_name(RawName) when is_binary(RawName) ->
  validate_metric_label_name(binary_to_list(RawName));
validate_metric_label_name(RawName) when is_list(RawName) ->
  case io_lib:printable_unicode_list(RawName) of
    true ->
      validate_metric_label_name_content(RawName);
    false ->
      erlang:error({invalid_metric_label_name, RawName,
                    "metric label is invalid string"})
  end;
validate_metric_label_name(RawName) ->
  erlang:error({invalid_metric_label_name, RawName,
                "metric label is not a string"}).

validate_metric_label_name_content("__"  ++ _Rest = RawName) ->
  erlang:error({invalid_metric_label_name, RawName,
                "metric label can't start with __"});
validate_metric_label_name_content(RawName) ->
  Regex = "^[a-zA-Z_][a-zA-Z0-9_]*$",
  case re:run(RawName, Regex) of
    {match, _} -> RawName;
    nomatch ->
      erlang:error({invalid_metric_label_name, RawName,
                    "metric label doesn't match regex " ++ Regex})
  end.

%% @private
validate_metric_help(RawHelp) when is_binary(RawHelp) ->
  validate_metric_help(binary_to_list(RawHelp));
validate_metric_help(RawHelp) when is_list(RawHelp) ->
  case io_lib:printable_unicode_list(RawHelp) of
    true  -> RawHelp;
    false -> erlang:error({invalid_metric_help, RawHelp,
                           "metric help is invalid string"})
  end;
validate_metric_help(RawHelp) ->
  erlang:error({invalid_metric_help, RawHelp, "metric help is not a string"}).

to_string(Value) when is_atom(Value) ->
  atom_to_list(Value);
to_string(Value) when is_binary(Value) ->
  binary_to_list(Value);
to_string(Value) when is_list(Value) ->
  Value.
