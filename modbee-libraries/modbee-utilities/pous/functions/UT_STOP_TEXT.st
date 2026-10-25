(* UT_STOP_TEXT — why a run ended (a block's stopReason, UT_STOP) in words
(function), for a person looking at the PLC or a simple display:
txt := UT_STOP_TEXT(Pump1.stopReason);       // 'Stopped: interlock'
At most 30 characters. The blocks do not call it: an HMI or SCADA shows
its own words for the code. UT_STOP_NONE (no run has ended) gives ''. *)

FUNCTION UT_STOP_TEXT : STRING(30)
  VAR_INPUT
    Code : UT_STOP; (* a stopReason *)
  END_VAR

CASE Code OF
UT_STOP_NONE: UT_STOP_TEXT := '';
UT_STOP_DEMAND_ENDED: UT_STOP_TEXT := 'Auto: demand ended';
UT_STOP_OPERATOR: UT_STOP_TEXT := 'Stopped: operator';
UT_STOP_SWITCHED_OFF: UT_STOP_TEXT := 'Stopped: switched off';
UT_STOP_INTERLOCK: UT_STOP_TEXT := 'Stopped: interlock';
UT_STOP_FAULT: UT_STOP_TEXT := 'Stopped: fault';
UT_STOP_MAX_RUN: UT_STOP_TEXT := 'Stopped: max run time';
UT_STOP_DONE: UT_STOP_TEXT := 'Done';
UT_STOP_ABORTED: UT_STOP_TEXT := 'Stopped: aborted';
UT_STOP_INHIBITED: UT_STOP_TEXT := 'Stopped: inhibited';
UT_STOP_COMMS_LOST: UT_STOP_TEXT := 'Stopped: comms lost';
UT_STOP_GROUP: UT_STOP_TEXT := 'Stopped: group';
UT_STOP_LOW_LEVEL: UT_STOP_TEXT := 'Stopped: low level';
UT_STOP_FULL: UT_STOP_TEXT := 'Stopped: full';
UT_STOP_EXERCISE_DONE: UT_STOP_TEXT := 'Done: exercise';
UT_STOP_BY_MOTOR: UT_STOP_TEXT := 'Stopped: by the motor';
UT_STOP_REMOTE_OFF: UT_STOP_TEXT := 'Stopped: remote off';
UT_STOP_NOT_PERMITTED: UT_STOP_TEXT := 'Stopped: not permitted';
UT_STOP_PAUSED_LONG: UT_STOP_TEXT := 'Stopped: paused too long';
UT_STOP_SETTING: UT_STOP_TEXT := 'Stopped: setting invalid';
UT_STOP_POWER_CUT: UT_STOP_TEXT := 'Stopped: power cut';
UT_STOP_RAIN: UT_STOP_TEXT := 'Stopped: rain';
UT_STOP_PUMP_FAULT: UT_STOP_TEXT := 'Stopped: pump fault';
UT_STOP_STEP_TIMEOUT: UT_STOP_TEXT := 'Stopped: step timeout';
UT_STOP_REFUSED: UT_STOP_TEXT := 'Stopped: recipe refused';
UT_STOP_ABORT_CMD: UT_STOP_TEXT := 'Stopped: aborted (HMI)';
UT_STOP_ASLEEP: UT_STOP_TEXT := 'Asleep: demand met';
UT_STOP_LEVEL_BAD: UT_STOP_TEXT := 'Stopped: level signal bad';
UT_STOP_CLEAN_TIMEOUT: UT_STOP_TEXT := 'Stopped: cleaning too long';
UT_STOP_METER_FAILED: UT_STOP_TEXT := 'Stopped: meter failed';
UT_STOP_TIME_CAP: UT_STOP_TEXT := 'Stopped: time cap';
UT_STOP_LEVEL_END: UT_STOP_TEXT := 'Stopped: level reached';
UT_STOP_IRRIGATOR: UT_STOP_TEXT := 'Stopped: irrigator';
UT_STOP_NOT_PROVEN: UT_STOP_TEXT := 'Stopped: valve not proven';
UT_STOP_SOURCE_LOW: UT_STOP_TEXT := 'Stopped: source low';
UT_STOP_HELD_BY_LINK: UT_STOP_TEXT := 'Stopped: by owner';
UT_STOP_LIMIT: UT_STOP_TEXT := 'Stopped: limit';
UT_STOP_NO_FLOW: UT_STOP_TEXT := 'Stopped: no flow';
UT_STOP_BOOSTER: UT_STOP_TEXT := 'Stopped: booster';
UT_STOP_STOCK_LOW: UT_STOP_TEXT := 'Stopped: stock tank low';
UT_STOP_QUANTITY: UT_STOP_TEXT := 'Done: quantity';
UT_STOP_SYS_MANUAL: UT_STOP_TEXT := 'Stopped: system Manual';
UT_STOP_RUN_SIGNAL_LOST: UT_STOP_TEXT := 'Stopped: run signal stopped';
ELSE
  UT_STOP_TEXT := 'Stopped';
END_CASE;

END_FUNCTION