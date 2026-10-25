(* Adds one alarm (row number Row) to a group summary *)

FUNCTION UT_ALARM_ADD : BOOL
  VAR_INPUT
    Row : INT;
    Trip : BOOL; (* a TRIP alarm (else a warning) *)
    Q : BOOL; (* on *)
    Unacked : BOOL;
    Off : BOOL; (* switched off *)
    Sounding : BOOL;
    BadSetting : BOOL;
  END_VAR
  VAR_IN_OUT
    Sum : UT_ALARM_SUM_REC;
  END_VAR


IF Q THEN
  Sum.onCount := Sum.onCount + 1;
  IF Trip THEN
    Sum.tripCount := Sum.tripCount + 1;
    IF Sum.firstTrip = 0 THEN Sum.firstTrip := Row; END_IF;
  ELSIF Sum.firstWarn = 0 THEN
    Sum.firstWarn := Row;
  END_IF;
END_IF;
IF Unacked THEN
  Sum.unackedCount := Sum.unackedCount + 1;
END_IF;
IF Trip THEN
  Sum.tripNew := Sum.tripNew OR (Q AND Unacked);
  Sum.tripRet := Sum.tripRet OR (NOT Q AND Unacked);
  Sum.tripOn := Sum.tripOn OR (Q AND NOT Unacked);
ELSIF NOT Off THEN
  Sum.warnNew := Sum.warnNew OR (Q AND Unacked);
  Sum.warnRet := Sum.warnRet OR (NOT Q AND Unacked);
  Sum.warnOn := Sum.warnOn OR (Q AND NOT Unacked);
END_IF;
Sum.sounding := Sum.sounding OR Sounding;
Sum.badSetting := Sum.badSetting OR BadSetting;
UT_ALARM_ADD := Q;

END_FUNCTION