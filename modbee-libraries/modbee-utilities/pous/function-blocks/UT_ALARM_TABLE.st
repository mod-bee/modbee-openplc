(* UT_ALARM_TABLE — every alarm of a site in one block, with the lamps, the
beacon, the siren and the healthy relay. Optional: alarms are the HMI /
SCADA's (68-70); the core never depends on this.

The rows are the project's UT_AT_ALARM instances (Alarms, any count; one
box per alarm with its condition on In, called before the table); the row
number is the alarm's number for the HMI. Each row keeps its own settings
(response OFF / WARN / TRIP, reset AUTO / MANUAL / RETRY with lock-out,
on / off delays, siren, re-arm, code) and runs UT_ALARM_RUN. The table:
Silence / cmdSilence silences the siren (a new alarm sounds again); Reset /
cmdReset acknowledges every alarm and clears the latched and locked rows
whose condition has gone; LampTest lights everything while held.
FaultLamp / WarnLamp: fast flash new, slow flash returned, steady
acknowledged. Healthy: the common alarm relay, TRUE while no trip
(fail-safe; relayOnWarning: no warning either). Status: the first trip
(lowest row), else the first warning, with its code. Nothing is kept over
a power cut except the settings: a condition still present raises again. *)

FUNCTION_BLOCK UT_ALARM_TABLE
  VAR_INPUT
    Silence : BOOL R_EDGE; (* silence the siren *)
    Reset : BOOL R_EDGE; (* acknowledge all; clear latched rows whose cause has gone *)
    LampTest : BOOL; (* lamps, beacon, siren on while held *)
  END_VAR
  VAR_OUTPUT
    FaultLamp : BOOL;
    WarnLamp : BOOL;
    Beacon : BOOL;
    Siren : BOOL;
    Healthy : BOOL; (* common alarm relay, TRUE while no trip (fail-safe) *)
    AnyTrip : BOOL;
    AnyWarning : BOOL;
    AnyUnacked : BOOL;
    Changed : BOOL; (* one scan: an alarm was raised or the counts changed *)
    BadSetting : BOOL;
  END_VAR
  VAR_IN_OUT
    Alarms : ARRAY [*] OF UT_AT_ALARM;
    Data : UT_ALARM_TABLE_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_ALARM_TABLE_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    sumFb : UT_ALARM_SUM;
    sum : UT_ALARM_SUM_REC;
    ok : BOOL;
    hSil : BOOL;
    hRst : BOOL;
    silReq : BOOL;
    rstReq : BOOL;
    i : DINT;
    lo : DINT;
    row : INT;
    x : BOOL;
    onPrev : INT;
    unPrev : INT;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := Data.set.sirenTimeout >= T#0s AND Data.set.fastFlash > T#0s AND Data.set.slowFlash > T#0s;
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := TRUE;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
silReq := Silence OR (Data.cmdSilence AND NOT hSil);
hSil := Data.cmdSilence;
Data.cmdSilence := FALSE;
rstReq := Reset OR (Data.cmdReset AND NOT hRst);
hRst := Data.cmdReset;
Data.cmdReset := FALSE;
IF rstReq THEN
  Data.sts.firstOut := 0;
END_IF;

(* the rows: sum them; pass the commands on (they act on the row's next run) *)
x := UT_ALARM_SUM_CLEAR(Sum := sum);
Changed := FALSE;
Data.sts.badRow := 0;
lo := LOWER_BOUND(Alarms, 1);
FOR i := lo TO UPPER_BOUND(Alarms, 1) DO
  row := DINT_TO_INT(i - lo + 1);
  IF Alarms[i].Raised() THEN
    Data.sts.latest := row;
    Data.sts.latestCode := Alarms[i].Code();
    Changed := TRUE;
    IF Data.sts.firstOut = 0 THEN
      Data.sts.firstOut := row;
    END_IF;
  END_IF;
  IF NOT Alarms[i].IsValid() AND Data.sts.badRow = 0 THEN
    Data.sts.badRow := row;
  END_IF;
  x := UT_ALARM_ADD(Row := row, Trip := Alarms[i].IsTrip(), Q := Alarms[i].IsOn(), Unacked := Alarms[i].IsUnacked(),
                    Off := Alarms[i].State() = UT_AT_OFF, Sounding := Alarms[i].Sounding(),
                    BadSetting := NOT Alarms[i].IsValid(), Sum := sum);
  IF rstReq THEN
    x := Alarms[i].Ack();
  END_IF;
  IF silReq THEN
    x := Alarms[i].Silence();
  END_IF;
END_FOR;
sumFb(LampTest := LampTest, FastFlash := Data.set.fastFlash, SlowFlash := Data.set.slowFlash,
      SirenTimeout := Data.set.sirenTimeout, BeaconWarnings := Data.set.beaconWarnings,
      RelayOnWarning := Data.set.relayOnWarning, Sum := sum);
FaultLamp := sumFb.FaultLamp;
WarnLamp := sumFb.WarnLamp;
Beacon := sumFb.Beacon;
Siren := sumFb.Siren AND NOT silReq;
Healthy := sumFb.Healthy;
AnyTrip := sum.tripCount > 0;
AnyWarning := sum.onCount > sum.tripCount;
AnyUnacked := sum.unackedCount > 0;
BadSetting := sum.badSetting OR NOT ok;
Changed := Changed OR sum.onCount <> onPrev OR sum.unackedCount <> unPrev;
onPrev := sum.onCount;
unPrev := sum.unackedCount;
Data.sts.onCount := sum.onCount;
Data.sts.tripCount := sum.tripCount;
Data.sts.unackedCount := sum.unackedCount;

(* the status line: the first trip, else the first warning *)
stF := UT_F_NONE;
IF sum.firstTrip > 0 THEN
  Data.sts.first := sum.firstTrip;
ELSE
  Data.sts.first := sum.firstWarn;
END_IF;
IF Data.sts.first > 0 THEN
  i := lo + INT_TO_DINT(Data.sts.first) - 1;
  stF := Alarms[i].Code();
  IF Alarms[i].IsTrip() THEN
    IF Alarms[i].State() = UT_AT_LOCKED THEN
      stCode := UT_ST_FAULT_LOCKED;
    ELSIF Alarms[i].State() = UT_AT_LATCHED THEN
      stCode := UT_ST_FAULT_RESET;
    ELSE
      stCode := UT_ST_FAULT;
    END_IF;
  ELSE
    stCode := UT_ST_WARNING;
  END_IF;
ELSIF BadSetting THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_SETTING;
ELSE
  stCode := UT_ST_OK;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := AnyTrip, Check := FALSE, OutOfSpec := AnyWarning OR BadSetting, Maint := FALSE);

END_FUNCTION_BLOCK