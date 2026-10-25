(* A group's summary starts empty each scan *)

FUNCTION UT_ALARM_SUM_CLEAR : BOOL
  VAR_IN_OUT
    Sum : UT_ALARM_SUM_REC;
  END_VAR

Sum.onCount := 0;
Sum.tripCount := 0;
Sum.unackedCount := 0;
Sum.firstTrip := 0;
Sum.firstWarn := 0;
Sum.tripNew := FALSE;
Sum.tripRet := FALSE;
Sum.tripOn := FALSE;
Sum.warnNew := FALSE;
Sum.warnRet := FALSE;
Sum.warnOn := FALSE;
Sum.sounding := FALSE;
Sum.badSetting := FALSE;
UT_ALARM_SUM_CLEAR := TRUE;

END_FUNCTION