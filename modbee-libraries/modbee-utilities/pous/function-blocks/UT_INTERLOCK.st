(* UT_INTERLOCK — the conditions that must all be healthy before a device may
run, as one Ok signal (-> the device's Interlock or Permissive), with
first-out and maintenance bypasses.

The conditions are the project's UT_INTLK_COND instances (Conditions, any
count; one box per condition on its own rung, called before the
interlock). Each one: delay (must be not OK this long to count); reset AUTO
(OK again as soon as healthy), MANUAL (held until a Reset while healthy:
pull cords, e-stops) or RETRY (by itself while healthy, at most maxRetries
times in retryWindow, then held); bypass (its command, only when the
condition allows it, while BypassEnable, for at most bypassTimeout, 0 =
never drops out; it drops out until the request or BypassEnable goes).
FirstOut is the first condition to stop the device since the last Reset
(same scan: the lowest; after a Reset with conditions still out, the lowest
of those). Settings kept (the conditions keep their own); a bad write is
put back. *)

FUNCTION_BLOCK UT_INTERLOCK
  VAR_INPUT
    BypassEnable : BOOL; (* key switch / HMI permission for bypasses *)
    Reset : BOOL R_EDGE; (* clear the first-out and the held conditions *)
  END_VAR
  VAR_OUTPUT
    Ok : BOOL; (* all OK or bypassed -> the device's Interlock / Permissive *)
    FirstOut : INT; (* the first condition out since the reset (0 = none) *)
    NotOkCount : INT;
    Bypassed : BOOL; (* a bypass in effect (show it!) *)
    Warning : BOOL; (* a bypass, or a bad setting *)
  END_VAR
  VAR_IN_OUT
    Conditions : ARRAY [*] OF UT_INTLK_COND;
    Data : UT_INTLK_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_INTLK_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    setOk : BOOL;
    hReset : BOOL;
    resetReq : BOOL;
    lb : DINT;
    i : DINT;
    x : BOOL;
    first : DINT;
    firstByp : DINT;
    firstWait : DINT;
    cfgAt : DINT;
    wentFirst : DINT;
    okPrev : BOOL := TRUE;
    resetAge : INT := 9; (* scans since a reset (a held condition clears on the next scan) *)
    stCode : UT_STATUS;
    stF : UT_FAULT;
    stAt : DINT;
    tLeft : TIME;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
setOk := Data.set.bypassTimeout >= T#0s AND Data.set.maxRetries >= 0 AND Data.set.retryWindow >= T#0s;
IF NOT setOk AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_BYPASS_TIMEOUT;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  setOk := TRUE;
END_IF;
IF keep.SaveSet AND (setOk OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := setOk;
END_IF;
resetReq := Reset OR (Data.cmdReset AND NOT hReset);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
IF resetReq THEN
  FirstOut := 0;
  resetAge := 0;
ELSIF resetAge < 9 THEN
  resetAge := resetAge + 1;
END_IF;

lb := LOWER_BOUND(Conditions, 1);
first := lb - 1;
firstByp := lb - 1;
firstWait := lb - 1;
cfgAt := lb - 1;
wentFirst := lb - 1;
Ok := TRUE;
Bypassed := FALSE;
NotOkCount := 0;
FOR i := lb TO UPPER_BOUND(Conditions, 1) DO
  x := Conditions[i].Permit(Bypass := BypassEnable AND setOk, Timeout := Data.set.bypassTimeout,
                            MaxRetries := Data.set.maxRetries, Window := Data.set.retryWindow);
  IF resetReq THEN
    x := Conditions[i].Reset();
  END_IF;
  IF NOT Conditions[i].IsValid() AND cfgAt < lb THEN
    cfgAt := i;
  END_IF;
  IF Conditions[i].IsBypassed() THEN
    Bypassed := TRUE;
    IF firstByp < lb THEN firstByp := i; END_IF;
  ELSIF Conditions[i].IsBad() THEN
    Ok := FALSE;
    NotOkCount := NotOkCount + 1;
    IF first < lb THEN first := i; END_IF;
    IF Conditions[i].WentBad() AND wentFirst < lb THEN wentFirst := i; END_IF;
  ELSIF Conditions[i].IsWaiting() AND firstWait < lb THEN
    firstWait := i;
  END_IF;
END_FOR;
IF UPPER_BOUND(Conditions, 1) < lb THEN
  Ok := FALSE;                   (* no conditions at all: never OK *)
END_IF;
(* first-out: kept until a reset; the one that went bad first (same scan: the lowest) *)
IF FirstOut = 0 THEN
  IF wentFirst >= lb THEN
    FirstOut := DINT_TO_INT(wentFirst - lb + 1);
  ELSIF first >= lb AND resetAge >= 2 THEN
    FirstOut := DINT_TO_INT(first - lb + 1);   (* after a reset with conditions still out *)
  END_IF;
END_IF;
IF okPrev AND NOT Ok THEN
  Data.sts.trips := Data.sts.trips + 1;
END_IF;
okPrev := Ok;
Warning := Bypassed OR cfgAt >= lb OR NOT setOk;

(* status: config > blocked > bypassed > bad setting > OK (with a delay counting) *)
stCode := UT_ST_OK;
stF := UT_F_NONE;
stAt := 0;
tLeft := T#0s;
IF UPPER_BOUND(Conditions, 1) < lb THEN
  stCode := UT_ST_CONFIG;
  stF := UT_F_NO_CONDITIONS;
ELSIF first >= lb THEN
  stF := UT_F_CONDITION;
  stAt := first - lb + 1;
  IF Conditions[first].IsHealthyHeld() THEN
    stCode := UT_ST_RESET_NEEDED;
  ELSE
    stCode := UT_ST_INTERLOCK;
  END_IF;
ELSIF firstByp >= lb THEN
  stCode := UT_ST_BYPASSED;
  stF := UT_F_CONDITION;
  stAt := firstByp - lb + 1;
ELSIF cfgAt >= lb THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_CONDITION;
  stAt := cfgAt - lb + 1;
ELSIF NOT setOk THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_BYPASS_TIMEOUT;
ELSIF firstWait >= lb THEN
  stF := UT_F_CONDITION;
  stAt := firstWait - lb + 1;
END_IF;
Data.det.timeLeft := tLeft;
Data.sts.statusCond := DINT_TO_INT(stAt);
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := NOT Ok, Check := Bypassed, OutOfSpec := Warning, Maint := FALSE);
Data.sts.ok := Ok;
Data.sts.firstOut := FirstOut;
Data.sts.bypassed := Bypassed;
Data.sts.notOkCount := NotOkCount;
Data.sts.warning := Warning;

END_FUNCTION_BLOCK