(* UT_DIGITAL_IN — a switch, float or contact, cleaned up: debounce, an alarm
on a state, chatter detection and simulation.

  debounce  Q follows the input once it has held its new state for
            onDelay (turning on) or offDelay (turning off)
  chatter   more than chatterCount clean changes within chatterTime: Q
            holds its last stable value, Quality BAD, until the input has
            been steady for chatterTime (chatterCount 0 = off)
  alarm     a warning on the chosen state of Q, with alarmDelay and
            alarmReset (AUTO / RETRY / MANUAL)
  simulate  Q is simValue (not kept); Quality SIM
  InQ       from the IO map row: not mapped = not on this site: Q FALSE,
            no alarm, status "Not fitted"; any other bad quality: Q held,
            Quality BAD

Settings kept by the block; a bad write is put back. The change count and
the time on (since the last day rollover) are kept hourly. *)

FUNCTION_BLOCK UT_DIGITAL_IN
  VAR_INPUT
    In : BOOL; (* the raw input (NC: NOT at the pin) *)
    InQ : UT_IO_Q := UT_IOQ_OK; (* quality from the IO map row *)
    Reset : BOOL R_EDGE; (* reset a MANUAL alarm *)
  END_VAR
  VAR_OUTPUT
    Q : BOOL; (* clean signal *)
    Alarm : BOOL;
    Chatter : BOOL; (* too many changes; Q holds its last stable value *)
    Quality : UT_QUALITY;
  END_VAR
  VAR_IN_OUT
    Data : UT_DIGITAL_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_DIGITAL_SET;
    keptGood : BOOL;
    keptTot : UT_DIGITAL_TOT;
  END_VAR
  VAR
    hRoll : BOOL;
    hReset : BOOL;
    keep : UT_KEEP;
    ok : BOOL;
    tCur : TIME;
    tPrev : TIME;
    started : BOOL;
    notFitted : BOOL;
    qBad : BOOL;
    raw : BOOL;
    rawPrev : BOOL;
    rawSince : TIME;
    stable : BOOL;
    qPrev : BOOL;
    winStart : TIME;
    winCount : INT;
    chattering : BOOL;
    qOut : BOOL;
    qSince : TIME;
    prot : UT_PROTECTION;
    stAl : UT_PROT_ST;
    stsAl : UT_PROT_STS;
    x : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
IF keep.PowerUp THEN
  Data.simulate := FALSE;
END_IF;
ok := Data.set.onDelay >= T#0s AND Data.set.offDelay >= T#0s AND Data.set.alarmDelay >= T#0s
      AND Data.set.chatterCount >= 0 AND Data.set.chatterTime >= T#0s
      AND (Data.set.alarmOn = UT_DI_NONE OR Data.set.alarmOn = UT_DI_WHEN_TRUE OR Data.set.alarmOn = UT_DI_WHEN_FALSE)
      AND (Data.set.alarmReset = UT_RST_AUTO OR Data.set.alarmReset = UT_RST_RETRY OR Data.set.alarmReset = UT_RST_MANUAL);
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

tCur := TIME();
notFitted := InQ = UT_IOQ_UNUSED OR InQ = UT_IOQ_NOT_FITTED;
qBad := NOT notFitted AND NOT (InQ = UT_IOQ_OK OR InQ = UT_IOQ_FORCED);
raw := In AND NOT notFitted;
IF NOT started THEN
  started := TRUE;
  tPrev := tCur;
  rawPrev := raw;
  rawSince := tCur;
  stable := raw;
  qPrev := raw;
  qSince := tCur;
  qOut := raw;
END_IF;

(* debounce, and chatter: more than chatterCount clean changes in a window *)
IF notFitted THEN                (* not on this site: off, nothing held *)
  stable := FALSE;
  rawPrev := FALSE;
  chattering := FALSE;
  winCount := 0;
ELSIF NOT qBad THEN              (* a bad input holds Q *)
  IF raw <> rawPrev THEN
    rawSince := tCur;
  END_IF;
  rawPrev := raw;
  IF Data.set.chatterCount <= 0 THEN
    chattering := FALSE;
    winCount := 0;
  ELSIF chattering AND tCur - rawSince >= Data.set.chatterTime THEN
    chattering := FALSE;
    winCount := 0;
  END_IF;
  IF raw <> stable AND NOT chattering THEN
    IF (raw AND tCur - rawSince >= Data.set.onDelay) OR (NOT raw AND tCur - rawSince >= Data.set.offDelay) THEN
      IF Data.set.chatterCount > 0 THEN
        IF winCount = 0 OR tCur - winStart > Data.set.chatterTime THEN
          winStart := tCur;
          winCount := 0;
        END_IF;
        winCount := winCount + 1;
        chattering := winCount > Data.set.chatterCount;
      END_IF;
      IF NOT chattering THEN
        stable := raw;
      END_IF;
    END_IF;
  END_IF;
END_IF;
IF Data.simulate THEN
  Q := Data.simValue;
  Chatter := FALSE;
  Quality := UT_Q_SIM;
ELSE
  Q := stable;
  Chatter := chattering;
  IF chattering OR qBad OR notFitted THEN
    Quality := UT_Q_BAD;
  ELSE
    Quality := UT_Q_GOOD;
  END_IF;
END_IF;
IF stable <> qPrev THEN
  Data.tot.changes := Data.tot.changes + 1;
END_IF;
qPrev := stable;
IF Data.cmdDayRollover AND NOT hRoll THEN   (* once per request, even when held on *)
  Data.tot.onTime := T#0s;
ELSIF Q THEN
  Data.tot.onTime := Data.tot.onTime + (tCur - tPrev);
END_IF;
hRoll := Data.cmdDayRollover;
Data.cmdDayRollover := FALSE;
tPrev := tCur;
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;

(* alarm *)
IF Data.set.alarmOn = UT_DI_NONE OR notFitted THEN
  prot.response := UT_RESP_OFF;
ELSE
  prot.response := UT_RESP_WARN;
END_IF;
prot.delay := Data.set.alarmDelay;
prot.reset := Data.set.alarmReset;
prot.recover := T#0s;
x := UT_PROT_RUN(TNow := tCur, Cause := (Data.set.alarmOn = UT_DI_WHEN_TRUE AND Q) OR (Data.set.alarmOn = UT_DI_WHEN_FALSE AND NOT Q),
                 ResetReq := Reset OR (Data.cmdReset AND NOT hReset), RetryWindow := T#1h, Prot := prot, Sts := stsAl, St := stAl);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
Alarm := stAl.warn;
IF Q <> qOut THEN
  qSince := tCur;
END_IF;
qOut := Q;
Data.stateFor := tCur - qSince;

(* status *)
stF := UT_F_NONE;
IF notFitted THEN
  stCode := UT_ST_NOT_FITTED;
ELSIF Data.simulate THEN
  stCode := UT_ST_SIMULATED;
  stF := UT_F_SIMULATED;
ELSIF qBad THEN
  stCode := UT_ST_FAULT;
  stF := UT_F_INPUT_BAD;
ELSIF chattering THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_CHATTER;
ELSIF Alarm THEN
  stCode := UT_ST_ALARM;
ELSIF NOT ok THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_SETTING;
ELSIF Q THEN
  stCode := UT_ST_ACTIVE;
ELSE
  stCode := UT_ST_OFF;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.q := Q;
Data.sts.alarm := Alarm;
Data.sts.chatter := Chatter;
Data.sts.quality := Quality;

END_FUNCTION_BLOCK