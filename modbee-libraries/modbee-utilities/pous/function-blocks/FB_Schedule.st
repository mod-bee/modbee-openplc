(* FB_Schedule — weekly time-of-day schedule, a local fallback (the platform holds the real calendar) (src-v2
UT_SCHEDULE + UT_SCHED_WINDOW, rows instead of element blocks; the same rules).
aWindow (the project's table, one row per time window, at most 16 kept): a window runs from todStart to todStop
on each day in its nDays bits (bit 0 Monday ... bit 6 Sunday); a todStop earlier than todStart crosses midnight
(the part after midnight belongs to the day it started); todStart = todStop is empty. nEveryDays N (2 or more)
runs it only every N-th day from dStartDate. bActive is on inside any window; nWindow is the first one on
(1 = the first row), sts.nInMask has a bit per window (bit 0 = the first row, up to 32).
Clock: dtClock, local time from F_LocalTime (the boards have no real-time clock: unwired = no clock, the schedule
is off); set.tUtcOffset is added. bClockOk is off when the clock is implausible (F_ClockOk) or has not moved for
5 s: the schedule is then off (an override still works), warning NoClock. bHourPulse / bDayPulse give one scan on
each new hour / at midnight, never doubled by a clock set back.
Overrides (bOverrideOn / bOverrideOff pins, bCmdOverrideOn / bCmdOverrideOff / bCmdCancelOverride, each once per
write): bActive on / off for set.tOverrideFor (0 = until the schedule next changes); Off wins, then Cancel, then
On. bEnable FALSE (pin or set.bEnable) cancels an override. sts.dtNextChange is the next time the schedule
changes (within 8 days; DT#1970-01-01-00:00:00 = none or no clock).
Kept (a retained last-good copy, restored at power-up, a bad write put back): set and the window rows. A window
with a bad setting and no good copy is left out: warning BadSetting, sts.nConfigWindow names it. *)

FUNCTION_BLOCK FB_Schedule EXTENDS FB_Object
  VAR_INPUT
    bEnable : BOOL := TRUE; (* AND-ed with set.bEnable *)
    dtClock : DT := DT#1970-01-01-00:00:00; (* local time (optional): unwired = no clock, the schedule is off *)
    bOverrideOn : BOOL R_EDGE; (* bActive on for set.tOverrideFor *)
    bOverrideOff : BOOL R_EDGE; (* bActive off for set.tOverrideFor *)
    refData : REFERENCE TO ST_ScheduleData;
  END_VAR
  VAR_IN_OUT
    aWindow : ARRAY [*] OF ST_SCHEDWINDOW;
  END_VAR
  VAR_OUTPUT
    bActive : BOOL;
    nWindow : INT; (* the first window on, 1 = the first row; 0 none *)
    bHourPulse : BOOL;
    bDayPulse : BOOL;
    bClockOk : BOOL;
    bOverridden : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_ScheduleSet;
    aKeptWindow : ARRAY [1..16] OF ST_SCHEDWINDOW;
    nKeptMask : WORD; (* bit n-1: slot n holds a good copy (a row bad from the start has none) *)
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
    cMaxKept : DINT := 16;
  END_VAR
  VAR
    nLastSecs : LINT;
    tLastMove : TIME;
    bSeen : BOOL;
    bMarks : BOOL;
    nLastHour : LINT;
    nLastDay : LINT;
    nCalcSecs : LINT := -1;
    bOvState : BOOL;
    tOvStart : TIME;
    bOvSched : BOOL;
    bOnSeen : BOOL;
    bOffSeen : BOOL;
    bCancelSeen : BOOL;
  END_VAR
  VAR_TEMP
    nBit : WORD; (* this row's bit in nKeptMask *)
    bOkSet : BOOL;
    bEn : BOOL;
    nLo : DINT;
    nHi : DINT;
    nI : DINT;
    nJ : DINT;
    nC : INT;
    nSecs : LINT;
    nLocal : LINT;
    nDayNo : LINT;
    nHourNo : LINT;
    nProbe : LINT;
    nCand : LINT;
    nNc : LINT;
    nW : LINT;
    bSched : BOOL;
    bFound : BOOL;
    bReqOn : BOOL;
    bReqOff : BOOL;
    bReqCancel : BOOL;
  END_VAR


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_ScheduleSet;
  END_VAR
  SetOk := stS.tOverrideFor >= T#0s AND stS.tUtcOffset >= -T#24h AND stS.tUtcOffset <= T#24h;
END_METHOD

METHOD PRIVATE WindowOk : BOOL
  VAR_INPUT
    stW : REFERENCE TO ST_SchedWindow;
  END_VAR
  WindowOk := stW.nEveryDays >= 0 AND stW.nEveryDays <= 366 AND stW.nDays <= 16#7F;
END_METHOD

(* the window is on at this local time (seconds since 1970) *)
METHOD PRIVATE WindowIn : BOOL
  VAR_INPUT
    stW : REFERENCE TO ST_SchedWindow;
    nAt : LINT;
  END_VAR
  VAR
    nDayP : LINT;
    nDow : INT;
    nDowPrev : INT;
    nMs : DINT;
    nSt : DINT;
    nSp : DINT;
    bDayOk : BOOL;
    bPrevOk : BOOL;
    nSDay : LINT;
  END_VAR
  WindowIn := FALSE;
  IF WindowOk(stW := stW) AND stW.bEnable AND stW.todStart <> stW.todStop THEN
    nDayP := nAt / 86400;
    nDow := LINT_TO_INT((nDayP + 3) MOD 7);
    nDowPrev := (nDow + 6) MOD 7;
    nMs := LINT_TO_DINT(nAt MOD 86400) * 1000;
    nSt := TOD_TO_DINT(stW.todStart);
    nSp := TOD_TO_DINT(stW.todStop);
    bDayOk := (stW.nDays AND SHL(BYTE#1, nDow)) <> 0;
    bPrevOk := (stW.nDays AND SHL(BYTE#1, nDowPrev)) <> 0;
    IF stW.nEveryDays >= 2 THEN
      nSDay := DATE_TO_LINT(stW.dStartDate) / 86400;
      bDayOk := bDayOk AND nDayP >= nSDay AND (nDayP - nSDay) MOD INT_TO_LINT(stW.nEveryDays) = 0;
      bPrevOk := bPrevOk AND nDayP - 1 >= nSDay AND (nDayP - 1 - nSDay) MOD INT_TO_LINT(stW.nEveryDays) = 0;
    END_IF;
    IF nSt < nSp THEN
      WindowIn := bDayOk AND nMs >= nSt AND nMs < nSp;
    ELSE
      WindowIn := (bDayOk AND nMs >= nSt) OR (bPrevOk AND nMs < nSp);
    END_IF;
  END_IF;
END_METHOD

(* the window's next start or stop after this local time, in seconds (-1 = none) *)
METHOD PRIVATE WindowNext : LINT
  VAR_INPUT
    stW : REFERENCE TO ST_SchedWindow;
    nAt : LINT;
  END_VAR
  VAR
    nDay0 : LINT;
    nA : LINT;
    nB : LINT;
  END_VAR
  WindowNext := -1;
  IF WindowOk(stW := stW) AND stW.bEnable AND stW.todStart <> stW.todStop THEN
    nDay0 := (nAt / 86400) * 86400;
    nA := nDay0 + (TOD_TO_LINT(stW.todStart) + 999) / 1000;
    IF nA <= nAt THEN nA := nA + 86400; END_IF;
    nB := nDay0 + (TOD_TO_LINT(stW.todStop) + 999) / 1000;
    IF nB <= nAt THEN nB := nB + 86400; END_IF;
    WindowNext := MIN(nA, nB);
  END_IF;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bActive := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nLo := LOWER_BOUND(aWindow, 1);
nHi := UPPER_BOUND(aWindow, 1);

(* kept settings and windows; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nHi - nLo + 1, cMaxKept) DO
      IF (nKeptMask AND SHL(WORD#1, nI - 1)) <> 0 THEN
        aWindow[nLo + nI - 1] := aKeptWindow[nI];
      END_IF;
    END_FOR;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
END_IF;
bOkSet := SetOk(stS := refData.set);
IF bOkSet THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
refData.sts.nConfigWindow := 0;
FOR nI := 1 TO nHi - nLo + 1 DO
  nJ := nLo + nI - 1;
  nBit := 0;
  IF nI <= cMaxKept THEN
    nBit := SHL(WORD#1, nI - 1);
  END_IF;
  IF WindowOk(stW := aWindow[nJ]) THEN
    IF nI <= cMaxKept THEN
      aKeptWindow[nI] := aWindow[nJ];
      nKeptMask := nKeptMask OR nBit;
    END_IF;
  ELSIF nBit <> 0 AND (nKeptMask AND nBit) <> 0 THEN
    aWindow[nJ] := aKeptWindow[nI];
    refData.sts.bRefused := TRUE;
  ELSIF refData.sts.nConfigWindow = 0 THEN
    refData.sts.nConfigWindow := DINT_TO_INT(nI);
  END_IF;
END_FOR;
bHourPulse := FALSE;
bDayPulse := FALSE;
bEn := bEnable AND refData.set.bEnable AND bOkSet;

(* the clock: no real-time clock on the board, unwired = no clock (never the system clock) *)
nSecs := DT_TO_LINT(dtClock);
IF NOT bSeen OR nSecs <> nLastSecs THEN
  bSeen := TRUE;
  nLastSecs := nSecs;
  tLastMove := tNow;
END_IF;
bClockOk := F_ClockOk(dtUtc := dtClock) AND tNow - tLastMove <= T#5s;
nLocal := nSecs + TIME_TO_LINT(refData.set.tUtcOffset) / 1000;
refData.det.dtLocal := LINT_TO_DT(nLocal);

(* the windows now *)
bSched := FALSE;
nWindow := 0;
refData.sts.nInMask := 0;
IF bClockOk THEN
  FOR nI := 1 TO nHi - nLo + 1 DO
    IF WindowIn(stW := aWindow[nLo + nI - 1], nAt := nLocal) THEN
      bSched := TRUE;
      IF nWindow = 0 THEN
        nWindow := DINT_TO_INT(nI);
      END_IF;
      IF nI <= 32 THEN
        refData.sts.nInMask := refData.sts.nInMask OR SHL(DWORD#1, nI - 1);
      END_IF;
    END_IF;
  END_FOR;
END_IF;

IF bClockOk THEN
  nDayNo := nLocal / 86400;
  nHourNo := nLocal / 3600;
  refData.sts.nDayOfWeek := LINT_TO_INT((nDayNo + 3) MOD 7) + 1;
  IF NOT bMarks THEN
    bMarks := TRUE;
    nLastHour := nHourNo;
    nLastDay := nDayNo;
  ELSE
    IF nHourNo > nLastHour THEN
      bHourPulse := TRUE;
      nLastHour := nHourNo;
    ELSIF nHourNo < nLastHour - 1 THEN
      nLastHour := nHourNo;       (* set back more than an hour: follow it *)
    END_IF;
    IF nDayNo > nLastDay THEN
      bDayPulse := TRUE;
      nLastDay := nDayNo;
    ELSIF nDayNo < nLastDay - 1 THEN
      nLastDay := nDayNo;
    END_IF;
  END_IF;
  (* the next change, once a second: step through the windows' boundaries (8 days at most) *)
  IF nLocal <> nCalcSecs THEN
    nCalcSecs := nLocal;
    nProbe := nLocal;
    nNc := -1;
    FOR nC := 1 TO 64 DO
      nCand := -1;
      FOR nJ := nLo TO nHi DO
        nW := WindowNext(stW := aWindow[nJ], nAt := nProbe);
        IF nW > 0 AND (nCand < 0 OR nW < nCand) THEN
          nCand := nW;
        END_IF;
      END_FOR;
      IF nCand < 0 OR nCand > nLocal + 8 * 86400 THEN
        EXIT;
      END_IF;
      bFound := FALSE;
      FOR nJ := nLo TO nHi DO
        IF WindowIn(stW := aWindow[nJ], nAt := nCand) THEN
          bFound := TRUE;
        END_IF;
      END_FOR;
      IF bFound <> bSched THEN
        nNc := nCand;
        EXIT;
      END_IF;
      nProbe := nCand;
    END_FOR;
    IF nNc >= 0 THEN
      refData.sts.dtNextChange := LINT_TO_DT(nNc);
    ELSE
      refData.sts.dtNextChange := DT#1970-01-01-00:00:00;
    END_IF;
  END_IF;
ELSE
  refData.sts.nDayOfWeek := 0;
  refData.sts.dtNextChange := DT#1970-01-01-00:00:00;
  nCalcSecs := -1;
END_IF;
IF bClockOk AND DT_TO_LINT(refData.sts.dtNextChange) > nLocal THEN
  refData.det.tNextChangeIn := LINT_TO_TIME((DT_TO_LINT(refData.sts.dtNextChange) - nLocal) * 1000);
ELSE
  refData.det.tNextChangeIn := T#0s;
END_IF;

(* overrides: once per request; Off wins, then Cancel, then On *)
bReqOn := bOverrideOn OR (refData.bCmdOverrideOn AND NOT bOnSeen);
bReqOff := bOverrideOff OR (refData.bCmdOverrideOff AND NOT bOffSeen);
bReqCancel := refData.bCmdCancelOverride AND NOT bCancelSeen;
bOnSeen := refData.bCmdOverrideOn;
bOffSeen := refData.bCmdOverrideOff;
bCancelSeen := refData.bCmdCancelOverride;
refData.bCmdOverrideOn := FALSE;
refData.bCmdOverrideOff := FALSE;
refData.bCmdCancelOverride := FALSE;
IF bReqOff THEN
  bOverridden := TRUE;
  bOvState := FALSE;
  tOvStart := tNow;
  bOvSched := bSched;
ELSIF bReqCancel THEN
  bOverridden := FALSE;
ELSIF bReqOn THEN
  bOverridden := TRUE;
  bOvState := TRUE;
  tOvStart := tNow;
  bOvSched := bSched;
END_IF;
refData.det.tOverrideLeft := T#0s;
IF NOT bEn THEN
  bOverridden := FALSE;
ELSIF bOverridden THEN
  IF refData.set.tOverrideFor > T#0s THEN
    IF tNow - tOvStart >= refData.set.tOverrideFor THEN
      bOverridden := FALSE;
    ELSE
      refData.det.tOverrideLeft := refData.set.tOverrideFor - (tNow - tOvStart);
    END_IF;
  ELSIF bSched <> bOvSched THEN
    bOverridden := FALSE;         (* untimed: ends when the schedule changes *)
  END_IF;
END_IF;
IF NOT bEn THEN
  bActive := FALSE;
  nWindow := 0;
ELSIF bOverridden THEN
  bActive := bOvState;
ELSE
  bActive := bSched;
END_IF;
IF SystemReset() THEN
  refData.sts.bRefused := FALSE;
END_IF;
refData.sts.bActive := bActive;
refData.sts.bOverridden := bOverridden;

bError := NOT bOkSet;
bWarning := NOT bError AND ((bEn AND NOT bClockOk) OR refData.sts.nConfigWindow > 0 OR refData.sts.bRefused);
IF bError THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bEn AND NOT bClockOk THEN
  eErrorId := E_UtError.NoClock;
ELSIF refData.sts.nConfigWindow > 0 THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bEn THEN
  eState := E_State.Off;
ELSIF bActive THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK