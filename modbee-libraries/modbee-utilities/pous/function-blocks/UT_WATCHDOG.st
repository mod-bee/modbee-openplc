(* UT_WATCHDOG — comms / heartbeat monitor and generator.

Watches a value that should keep changing: a heartbeat bit (Beat, either
edge) or a counter (Counter, any change) from a remote PLC, a Modbus
register, an MQTT message counter. When neither has changed for `timeout`
the link is dead: CommsFail. The failure is a UT_PROTECT trip:

  failReset AUTO    CommsFail clears once the link has been alive recoverTime
  failReset RETRY   as AUTO, three times an hour, then as MANUAL
  failReset MANUAL  CommsFail stays until a reset (Reset pin, cmdReset)
                    with the link alive; a reset while it's dead is refused

Ok is on while the link is alive and has been for recoverTime (so it's off
at start until the first change). HeartbeatOut toggles and HeartbeatCount
counts up every beatPeriod, for the other side to watch; they keep going
when Enable is off.

failures and downTime (time dead, from the timeout to the next change) are
not kept over a power cut: they start at 0, and a held failure is
forgotten. *)

FUNCTION_BLOCK UT_WATCHDOG
  VAR_INPUT
    Beat : BOOL; (* heartbeat bit from the remote (any change counts) *)
    Counter : DINT; (* or a counter / register from the remote (any change counts) *)
    Enable : BOOL := TRUE;
    Reset : BOOL R_EDGE; (* reset a held failure (MANUAL) *)
  END_VAR
  VAR_OUTPUT
    Ok : BOOL; (* remote alive *)
    CommsFail : BOOL; (* no change for timeout *)
    HeartbeatOut : BOOL; (* toggles every beatPeriod; send this to the remote *)
    HeartbeatCount : DINT; (* counts up every beatPeriod *)
    Warning : BOOL; (* the link is down (report only) *)
  END_VAR
  VAR_IN_OUT
    Data : UT_WATCHDOG_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_WATCHDOG_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    setOk : BOOL;
    st : UT_PROT_ST;
    pSts : UT_PROT_STS;
    x : BOOL;
    stCode : UT_STATUS;
    shownSt : UT_STATUS;
    tCur : TIME;
    prevT : TIME;
    started : BOOL;
    beatPrev : BOOL;
    counterPrev : DINT;
    changed : BOOL;
    seen : BOOL; (* a change seen since start / enable *)
    lastChangeAt : TIME;
    aliveSince : TIME;
    dead : BOOL;
    sinceNow : TIME; (* since the last change, now *)
    sincePrev : TIME; (* and at the previous scan *)
    prot : UT_PROTECTION;
    failCount : UDINT;
    down : TIME;
    beatAt : TIME;
    resetPrev : BOOL;
    resetSeen : BOOL;
    resetReq : BOOL;
    countSeen : BOOL;
    doResetCount : BOOL;
  END_VAR


tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
setOk := Data.set.timeout > T#0s AND Data.set.recoverTime >= T#0s AND Data.set.beatPeriod >= T#0s
         AND (Data.set.failReset = UT_RST_AUTO OR Data.set.failReset = UT_RST_RETRY OR Data.set.failReset = UT_RST_MANUAL);
IF NOT setOk AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  setOk := TRUE;
END_IF;
IF keep.SaveSet AND (setOk OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := setOk;
END_IF;
IF NOT started THEN
  started := TRUE;
  prevT := tCur;
  beatPrev := Beat;
  counterPrev := Counter;
  lastChangeAt := tCur;
  beatAt := tCur;
END_IF;

(* pins act on a rising edge; HMI commands once per request, then cleared *)
resetReq := Reset OR (Data.cmdReset AND NOT resetSeen);
resetPrev := Reset;
resetSeen := Data.cmdReset;
Data.cmdReset := FALSE;
doResetCount := Data.cmdResetCount AND NOT countSeen;
countSeen := Data.cmdResetCount;
Data.cmdResetCount := FALSE;

(* heartbeat for the other side *)
IF Data.set.beatPeriod > T#0s THEN
  IF tCur - beatAt >= Data.set.beatPeriod THEN
    HeartbeatOut := NOT HeartbeatOut;
    IF HeartbeatCount = 2147483647 THEN
      HeartbeatCount := 0;
    ELSE
      HeartbeatCount := HeartbeatCount + 1;
    END_IF;
    beatAt := beatAt + Data.set.beatPeriod;
    IF tCur - beatAt >= Data.set.beatPeriod THEN
      beatAt := tCur;              (* the scan is slower than beatPeriod *)
    END_IF;
  END_IF;
ELSE
  HeartbeatOut := FALSE;
  beatAt := tCur;
END_IF;

(* the remote *)
changed := Beat <> beatPrev OR Counter <> counterPrev;
beatPrev := Beat;
counterPrev := Counter;
IF NOT Enable THEN
  seen := FALSE;
  dead := FALSE;
  lastChangeAt := tCur;
  prot.response := UT_RESP_OFF;
  x := UT_PROT_RUN(TNow := tCur, Cause := FALSE, ResetReq := FALSE, RetryWindow := T#1h, Prot := prot, Sts := pSts, St := st);
  Ok := FALSE;
  CommsFail := FALSE;
ELSE
  (* time dead since the previous scan, up to now or the change seen now *)
  sinceNow := tCur - lastChangeAt;
  sincePrev := prevT - lastChangeAt;
  IF sinceNow > Data.set.timeout THEN
    IF sincePrev > Data.set.timeout THEN
      down := down + (sinceNow - sincePrev);
    ELSE
      down := down + (sinceNow - Data.set.timeout);
    END_IF;
  END_IF;
  IF changed THEN
    seen := TRUE;
    lastChangeAt := tCur;
  END_IF;
  dead := tCur - lastChangeAt >= Data.set.timeout;
  IF dead OR NOT seen THEN
    aliveSince := tCur;            (* alive counts from the last dead scan, as UT_PROTECT's recover *)
  END_IF;
  prot.response := UT_RESP_TRIP;
  prot.delay := T#0s;
  prot.reset := Data.set.failReset;
  prot.recover := Data.set.recoverTime;
  prot.maxRetries := 3;
  x := UT_PROT_RUN(TNow := tCur, Cause := dead, ResetReq := resetReq, RetryWindow := T#1h, Prot := prot, Sts := pSts, St := st);
  IF st.event THEN
    failCount := failCount + 1;
  END_IF;
  CommsFail := st.trip;
  Ok := NOT CommsFail AND NOT dead AND seen AND tCur - aliveSince >= Data.set.recoverTime;
END_IF;
prevT := tCur;

IF doResetCount THEN
  failCount := 0;
  down := T#0s;
END_IF;

Data.sts.ok := Ok;
Data.det.lastChange := tCur - lastChangeAt;
Data.sts.failures := failCount;
Data.det.downTime := down;
Warning := CommsFail;
IF NOT setOk THEN
  stCode := UT_ST_CONFIG;
ELSIF NOT Enable THEN
  stCode := UT_ST_OFF;
ELSIF CommsFail THEN
  stCode := UT_ST_COMMS_LOST;
ELSIF Ok THEN
  stCode := UT_ST_LINK_OK;
ELSE
  stCode := UT_ST_LINK_WAITING;
END_IF;
IF stCode <> shownSt OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  IF CommsFail OR NOT setOk THEN
    Data.sts.statusText := UT_STATUS_TEXT(stCode, UT_F_LINK_TIMEOUT);
  ELSE
    Data.sts.statusText := UT_STATUS_TEXT(stCode, UT_F_NONE);
  END_IF;
END_IF;
Data.sts.statusCode := stCode;
IF CommsFail THEN Data.sts.faultId := UT_F_LINK_TIMEOUT; ELSE Data.sts.faultId := UT_F_NONE; END_IF;
Data.sts.ne107 := UT_NE107_RUN(Fault := FALSE, Check := FALSE, OutOfSpec := CommsFail, Maint := FALSE);

END_FUNCTION_BLOCK