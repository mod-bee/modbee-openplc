(* A group's lamps, beacon, siren and healthy relay *)

FUNCTION_BLOCK UT_ALARM_SUM
  VAR_INPUT
    LampTest : BOOL;
    FastFlash : TIME := T#250ms;
    SlowFlash : TIME := T#1s;
    SirenTimeout : TIME; (* the siren stops after this (0 = until silenced) *)
    BeaconWarnings : BOOL := TRUE; (* warnings light the beacon too *)
    RelayOnWarning : BOOL; (* warnings drop the healthy relay too *)
  END_VAR
  VAR_OUTPUT
    FaultLamp : BOOL;
    WarnLamp : BOOL;
    Beacon : BOOL;
    Siren : BOOL;
    Healthy : BOOL;
  END_VAR
  VAR_IN_OUT
    Sum : UT_ALARM_SUM_REC;
  END_VAR
  VAR
    tCur : TIME;
    sirenAt : TIME;
    soundPrev : BOOL;
    fast : BOOL;
    slow : BOOL;
  END_VAR


tCur := TIME();
fast := UT_BLINK(OnTime := FastFlash, OffTime := FastFlash);
slow := UT_BLINK(OnTime := SlowFlash, OffTime := SlowFlash);
FaultLamp := (Sum.tripNew AND fast) OR (Sum.tripRet AND NOT Sum.tripNew AND slow)
             OR (Sum.tripOn AND NOT Sum.tripNew AND NOT Sum.tripRet);
WarnLamp := (Sum.warnNew AND fast) OR (Sum.warnRet AND NOT Sum.warnNew AND slow)
            OR (Sum.warnOn AND NOT Sum.warnNew AND NOT Sum.warnRet);
Beacon := Sum.tripCount > 0 OR Sum.tripNew OR Sum.tripRet
          OR (BeaconWarnings AND (Sum.onCount > Sum.tripCount OR Sum.warnNew OR Sum.warnRet));
IF Sum.sounding AND NOT soundPrev THEN
  sirenAt := tCur;               (* a new alarm sounds again *)
END_IF;
soundPrev := Sum.sounding;
Siren := Sum.sounding AND (SirenTimeout <= T#0s OR tCur - sirenAt < SirenTimeout);
Healthy := Sum.tripCount = 0 AND NOT (RelayOnWarning AND Sum.onCount > 0);
IF LampTest THEN
  FaultLamp := TRUE;
  WarnLamp := TRUE;
  Beacon := TRUE;
  Siren := TRUE;
END_IF;

END_FUNCTION_BLOCK