(* UT_SCHEDULE — weekly time-of-day schedule (a local fallback: the platform
holds the real calendar). Active is on inside the time windows, on the
days each window is set for; an operator can override it on or off for a
while. HourPulse / DayPulse give one scan on each new hour / at midnight.

The windows are the project's UT_SCHED_WINDOW instances (Windows, any
count; call them before the schedule): each keeps its own settings. A
window runs from start to stop on each day in its days bits (bit 0 Monday
... bit 6 Sunday); a stop earlier than the start crosses midnight (the part
after midnight belongs to the day it started); start = stop is empty.
everyDays N (2 or more) runs it only every N-th day from startDate.

Clock: local time from UT_LOCAL_TIME (optional: the boards have no real-time
clock; unwired = no clock, the schedule is off);
set.utcOffset is added. ClockOk is off when the clock is implausible
(before 2020 or from 2100) or has not moved for 5 s; the schedule is then
off (an override still works, Warning). The pulses are never doubled by a
clock set back. Overrides (OverrideOn / OverrideOff pins, cmdOverrideOn /
cmdOverrideOff / cmdCancelOverride): Active on / off for overrideFor (0 =
until the schedule next changes); Off wins, then Cancel, then On. Enable
FALSE (pin or set.enable) cancels an override. Settings kept; a bad write
is put back. *)

FUNCTION_BLOCK UT_SCHEDULE
  VAR_INPUT
    Enable : BOOL := TRUE; (* AND-ed with set.enable *)
    Clock : DT := DT#1970-01-01-00:00:00; (* local time (optional); unwired = no clock: the schedule is off *)
    OverrideOn : BOOL R_EDGE; (* Active on for overrideFor *)
    OverrideOff : BOOL R_EDGE; (* Active off for overrideFor *)
  END_VAR
  VAR_OUTPUT
    Active : BOOL;
    Window : INT; (* the first active window, 1 = first element; 0 none *)
    HourPulse : BOOL;
    DayPulse : BOOL;
    ClockOk : BOOL;
    Warning : BOOL; (* no clock, or a window with a bad setting *)
  END_VAR
  VAR_IN_OUT
    Windows : ARRAY [*] OF UT_SCHED_WINDOW;
    Data : UT_SCHED_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_SCHED_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    ok : BOOL;
    tCur : TIME;
    clk : DT;
    utcSecs : LINT;
    lastSecs : LINT;
    lastMove : TIME;
    seen : BOOL;
    local : LINT;
    dayNo : LINT;
    hourNo : LINT;
    lastHour : LINT;
    lastDay : LINT;
    marks : BOOL;
    sched : BOOL;
    win : INT;
    lo : DINT;
    hi : DINT;
    j : DINT;
    c : INT;
    probe : LINT;
    cand : LINT;
    nc : LINT;
    calcSecs : LINT := -1;
    found : BOOL;
    en : BOOL;
    ovState : BOOL;
    ovStart : TIME;
    ovSched : BOOL;
    overridden : BOOL;
    hOn : BOOL;
    hOff : BOOL;
    hCancel : BOOL;
    reqOn : BOOL;
    reqOff : BOOL;
    reqCancel : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := Data.set.overrideFor >= T#0s AND Data.set.utcOffset >= -T#24h AND Data.set.utcOffset <= T#24h;
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
HourPulse := FALSE;
DayPulse := FALSE;
lo := LOWER_BOUND(Windows, 1);
hi := UPPER_BOUND(Windows, 1);
en := Enable AND Data.set.enable;

(* the clock *)
clk := Clock;                    (* no real-time clock on the board: unwired = no clock, never CURRENT_DT *)
utcSecs := DT_TO_LINT(clk);
IF NOT seen OR utcSecs <> lastSecs THEN
  seen := TRUE;
  lastSecs := utcSecs;
  lastMove := tCur;
END_IF;
ClockOk := UT_CLOCK_OK(Utc := clk) AND tCur - lastMove <= T#5s;
local := utcSecs + TIME_TO_LINT(Data.set.utcOffset) / 1000;
Data.det.localTime := LINT_TO_DT(local);

(* the windows now; their settings faults *)
sched := FALSE;
win := 0;
Data.sts.configWindow := 0;
FOR j := lo TO hi DO
  IF NOT Windows[j].IsValid() AND Data.sts.configWindow = 0 THEN
    Data.sts.configWindow := DINT_TO_INT(j - lo) + 1;
  END_IF;
  IF ClockOk THEN
    IF Windows[j].IsIn(Local := LINT_TO_DT(local)) AND win = 0 THEN
      win := DINT_TO_INT(j - lo) + 1;
      sched := TRUE;
    END_IF;
  END_IF;
END_FOR;

IF ClockOk THEN
  dayNo := local / 86400;
  hourNo := local / 3600;
  Data.sts.dayOfWeek := LINT_TO_INT((dayNo + 3) MOD 7) + 1;
  IF NOT marks THEN
    marks := TRUE;
    lastHour := hourNo;
    lastDay := dayNo;
  ELSE
    IF hourNo > lastHour THEN
      HourPulse := TRUE;
      lastHour := hourNo;
    ELSIF hourNo < lastHour - 1 THEN
      lastHour := hourNo;        (* set back more than an hour: follow it *)
    END_IF;
    IF dayNo > lastDay THEN
      DayPulse := TRUE;
      lastDay := dayNo;
    ELSIF dayNo < lastDay - 1 THEN
      lastDay := dayNo;
    END_IF;
  END_IF;
  (* the next change, once a second: step through the windows' boundaries (8 days at most) *)
  IF local <> calcSecs THEN
    calcSecs := local;
    probe := local;
    nc := -1;
    FOR c := 1 TO 64 DO
      cand := -1;
      FOR j := lo TO hi DO
        IF DT_TO_LINT(Windows[j].NextChange(Local := LINT_TO_DT(probe))) > 0 THEN
          IF cand < 0 OR DT_TO_LINT(Windows[j].NextChange(Local := LINT_TO_DT(probe))) < cand THEN
            cand := DT_TO_LINT(Windows[j].NextChange(Local := LINT_TO_DT(probe)));
          END_IF;
        END_IF;
      END_FOR;
      IF cand < 0 OR cand > local + 8 * 86400 THEN
        EXIT;
      END_IF;
      found := FALSE;
      FOR j := lo TO hi DO
        IF Windows[j].IsIn(Local := LINT_TO_DT(cand)) THEN
          found := TRUE;
        END_IF;
      END_FOR;
      IF found <> sched THEN
        nc := cand;
        EXIT;
      END_IF;
      probe := cand;
    END_FOR;
    FOR j := lo TO hi DO
      found := Windows[j].IsIn(Local := LINT_TO_DT(local));   (* each window's own state: now again *)
    END_FOR;
    IF nc >= 0 THEN
      Data.sts.nextChange := LINT_TO_DT(nc);
    ELSE
      Data.sts.nextChange := DT#1970-01-01-00:00:00;
    END_IF;
  END_IF;
ELSE
  Data.sts.dayOfWeek := 0;
  Data.sts.nextChange := DT#1970-01-01-00:00:00;
  calcSecs := -1;
END_IF;
IF ClockOk AND DT_TO_LINT(Data.sts.nextChange) > local THEN
  Data.det.nextChangeIn := LINT_TO_TIME((DT_TO_LINT(Data.sts.nextChange) - local) * 1000);
ELSE
  Data.det.nextChangeIn := T#0s;
END_IF;

(* overrides: once per request; Off wins, then Cancel, then On *)
reqOn := OverrideOn OR (Data.cmdOverrideOn AND NOT hOn);
reqOff := OverrideOff OR (Data.cmdOverrideOff AND NOT hOff);
reqCancel := Data.cmdCancelOverride AND NOT hCancel;
hOn := Data.cmdOverrideOn;
hOff := Data.cmdOverrideOff;
hCancel := Data.cmdCancelOverride;
Data.cmdOverrideOn := FALSE;
Data.cmdOverrideOff := FALSE;
Data.cmdCancelOverride := FALSE;
IF reqOff THEN
  overridden := TRUE;
  ovState := FALSE;
  ovStart := tCur;
  ovSched := sched;
ELSIF reqCancel THEN
  overridden := FALSE;
ELSIF reqOn THEN
  overridden := TRUE;
  ovState := TRUE;
  ovStart := tCur;
  ovSched := sched;
END_IF;
Data.det.overrideLeft := T#0s;
IF NOT en THEN
  overridden := FALSE;
ELSIF overridden THEN
  IF Data.set.overrideFor > T#0s THEN
    IF tCur - ovStart >= Data.set.overrideFor THEN
      overridden := FALSE;
    ELSE
      Data.det.overrideLeft := Data.set.overrideFor - (tCur - ovStart);
    END_IF;
  ELSIF sched <> ovSched THEN
    overridden := FALSE;         (* untimed: ends when the schedule changes *)
  END_IF;
END_IF;
IF NOT en THEN
  Active := FALSE;
  Window := 0;
ELSIF overridden THEN
  Active := ovState;
  Window := win;
ELSE
  Active := sched;
  Window := win;
END_IF;
Warning := (en AND NOT ClockOk) OR Data.sts.configWindow > 0;

stF := UT_F_NONE;
IF NOT en THEN
  stCode := UT_ST_OFF;
ELSIF overridden AND ovState THEN
  stCode := UT_ST_OVERRIDE_ON;
ELSIF overridden THEN
  stCode := UT_ST_OVERRIDE_OFF;
ELSIF NOT ClockOk THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_NO_CLOCK;
ELSIF Data.sts.configWindow > 0 THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_SCHED_WINDOW;
ELSIF Active THEN
  stCode := UT_ST_ACTIVE;
ELSE
  stCode := UT_ST_IDLE;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := FALSE, Check := NOT en OR overridden, OutOfSpec := Warning, Maint := FALSE);
Data.sts.active := Active;
Data.sts.overridden := overridden;

END_FUNCTION_BLOCK