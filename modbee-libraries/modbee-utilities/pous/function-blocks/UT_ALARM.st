(* UT_ALARM — one alarm as its own block, the ISA-18.2 way (optional: alarms
are the HMI / SCADA's, 68-70).

The condition is In, or the device on Src (UT_I_STATUS: a TRIP alarm
follows HasFault, a WARN alarm HasWarning or HasFault; the code is its
FaultId). UT_ALARM_RUN does the rest as a table row: on / off delays
(alarm.prot.delay / recover), AUTO / MANUAL (latched until Reset with the
condition gone) / RETRY (locks out after maxRetries raises in
retryWindow), acknowledge, re-arm. States: NORMAL, UNACKED, ACKED,
RTN_UNACKED, SHELVED (cmdShelve, for shelveFor, at most maxShelve),
SUPPRESSED (Inhibit), OOS (cmdOutOfService), LATCHED, LOCKED. A shelved,
suppressed or out-of-service alarm still present comes back as a new one.
latch: Q stays on until acknowledged after the condition cleared;
ackRequired FALSE: an event that never needs acknowledging. Ack / cmdAck /
grp.ack (from UT_ANNUNCIATOR) acknowledge; Reset / cmdReset acknowledge and
clear a latched / locked alarm whose condition has gone. raisedAt /
ackedAt / clearedAt from Clock (optional; unwired: blank - the boards
have no real-time clock, the SCADA stamps on arrival);
sequence orders the first-out. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_ALARM
  VAR_INPUT
    In : BOOL; (* the condition (when Src is unwired) *)
    Src : UT_I_STATUS; (* follow a device *)
    Inhibit : BOOL; (* suppressed by design *)
    Ack : BOOL R_EDGE;
    Reset : BOOL R_EDGE;
    Clock : DT := DT#1970-01-01-00:00:00; (* a real-time clock (optional); unwired = no clock: the times stay blank *)
  END_VAR
  VAR_OUTPUT
    Q : BOOL; (* to annunciate *)
    Unacked : BOOL;
    Active : BOOL; (* the condition now (after the delays) *)
    BadSetting : BOOL;
    Code : UT_FAULT;
  END_VAR
  VAR_IN_OUT
    Data : UT_ALARM_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_ALARM_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    mem : UT_AT_MEM;
    run : UT_AT_STS;
    ok : BOOL;
    tCur : TIME;
    clk : DT;
    cond : BOOL;
    raised : BOOL;
    sounding : BOOL;
    removed : BOOL;
    oos : BOOL;
    shelved : BOOL;
    shelveAt : TIME;
    shelveDur : TIME;
    ackReq : BOOL;
    rstReq : BOOL;
    hAck : BOOL;
    hShelve : BOOL;
    hUnshelve : BOOL;
    hOos : BOOL;
    hIn : BOOL;
    hCount : BOOL;
    hRst : BOOL;
    doShelve : BOOL;
    doUnshelve : BOOL;
    doOos : BOOL;
    doIn : BOOL;
    activePrev : BOOL;
    activeAt : TIME;
    unackedPrev : BOOL;
    stCode : UT_STATUS;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


tCur := TIME();
clk := Clock;                    (* no real-time clock on the board: unwired = no clock, never CURRENT_DT *)
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_PROT_OK(P := Data.set.alarm.prot) AND Data.set.alarm.retryWindow >= T#0s AND Data.set.alarm.rearm >= T#0s
      AND Data.set.maxShelve >= T#0s AND Data.set.shelveFor >= T#0s
      AND (Data.set.prio = UT_PRIO_LOW OR Data.set.prio = UT_PRIO_MEDIUM OR Data.set.prio = UT_PRIO_HIGH
           OR Data.set.prio = UT_PRIO_CRITICAL);
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

(* commands: once per request *)
ackReq := Ack OR (Data.cmdAck AND NOT hAck) OR Data.grp.ack;
hAck := Data.cmdAck;
Data.cmdAck := FALSE;
Data.grp.ack := FALSE;
rstReq := Reset OR (Data.cmdReset AND NOT hRst);
hRst := Data.cmdReset;
Data.cmdReset := FALSE;
doShelve := Data.cmdShelve AND NOT hShelve;
hShelve := Data.cmdShelve;
Data.cmdShelve := FALSE;
doUnshelve := Data.cmdUnshelve AND NOT hUnshelve;
hUnshelve := Data.cmdUnshelve;
Data.cmdUnshelve := FALSE;
doOos := Data.cmdOutOfService AND NOT hOos;
hOos := Data.cmdOutOfService;
Data.cmdOutOfService := FALSE;
doIn := Data.cmdInService AND NOT hIn;
hIn := Data.cmdInService;
Data.cmdInService := FALSE;
IF Data.cmdResetCount AND NOT hCount THEN
  Data.sts.count := 0;
END_IF;
hCount := Data.cmdResetCount;
Data.cmdResetCount := FALSE;

(* out of service and shelving; together, the alarm stays live *)
IF doOos AND NOT doIn THEN
  oos := TRUE;
ELSIF doIn THEN
  oos := FALSE;
END_IF;
IF doShelve AND NOT doUnshelve THEN
  shelveDur := Data.set.shelveFor;
  IF shelveDur <= T#0s OR shelveDur > Data.set.maxShelve THEN
    shelveDur := Data.set.maxShelve;
  END_IF;
  IF shelveDur > T#0s THEN
    shelved := TRUE;
    shelveAt := tCur;
  END_IF;
ELSIF doUnshelve THEN
  shelved := FALSE;
END_IF;
IF shelved AND (tCur - shelveAt >= MIN(shelveDur, Data.set.maxShelve)) THEN
  shelved := FALSE;
END_IF;
IF shelved THEN
  Data.det.shelvedFor := MIN(shelveDur, Data.set.maxShelve) - (tCur - shelveAt);
ELSE
  Data.det.shelvedFor := T#0s;
END_IF;

(* the condition: In, or the device *)
cond := In;
Code := Data.set.alarm.code;
IF Src <> NULL THEN
  IF Data.set.alarm.prot.response = UT_RESP_TRIP THEN
    cond := Src.HasFault();
  ELSE
    cond := Src.HasWarning() OR Src.HasFault();
  END_IF;
  IF Src.FaultId() <> UT_F_NONE THEN
    Code := Src.FaultId();
  END_IF;
END_IF;
removed := oos OR Inhibit OR shelved;
raised := UT_ALARM_RUN(TNow := tCur, In := cond AND NOT removed,
                       AckReq := ackReq OR rstReq OR removed OR NOT Data.set.ackRequired,
                       ResetReq := rstReq OR removed, SilenceReq := FALSE, Set := Data.set.alarm, Mem := mem, Sts := run,
                       Sounding => sounding);
IF raised THEN
  Data.sts.count := Data.sts.count + 1;
  Data.sts.sequence := TIME_TO_UDINT(tCur);
  Data.sts.raisedAt := clk;
  Data.sts.code := Code;
END_IF;
IF unackedPrev AND NOT run.unacked AND Data.set.ackRequired THEN
  Data.sts.ackedAt := clk;
END_IF;
unackedPrev := run.unacked;
Active := mem.cond;
IF Active AND NOT activePrev THEN
  activeAt := tCur;
END_IF;
IF activePrev AND NOT Active THEN
  Data.sts.lastDuration := tCur - activeAt;
  Data.sts.clearedAt := clk;
END_IF;
activePrev := Active;

(* the ISA-18.2 state *)
IF oos THEN
  Data.sts.state := UT_ALM_OOS;
ELSIF Inhibit THEN
  Data.sts.state := UT_ALM_SUPPRESSED;
ELSIF shelved THEN
  Data.sts.state := UT_ALM_SHELVED;
ELSE
  CASE run.state OF
  UT_AT_ACTIVE:
    IF run.unacked THEN Data.sts.state := UT_ALM_UNACKED; ELSE Data.sts.state := UT_ALM_ACKED; END_IF;
  UT_AT_RETURNED: Data.sts.state := UT_ALM_RTN_UNACKED;
  UT_AT_LATCHED: Data.sts.state := UT_ALM_LATCHED;
  UT_AT_LOCKED: Data.sts.state := UT_ALM_LOCKED;
  ELSE
    Data.sts.state := UT_ALM_NORMAL;
  END_CASE;
END_IF;
Unacked := run.unacked AND NOT removed;
Q := NOT removed AND (run.q OR (Data.set.latch AND run.state = UT_AT_RETURNED));
BadSetting := NOT ok;
Data.sts.active := Active;
Data.sts.unacked := Unacked;
Data.sts.badSetting := BadSetting;
IF NOT Q THEN
  stCode := UT_ST_OK;
ELSIF Data.set.alarm.prot.response = UT_RESP_TRIP THEN
  IF run.state = UT_AT_LOCKED THEN stCode := UT_ST_FAULT_LOCKED;
  ELSIF run.state = UT_AT_LATCHED THEN stCode := UT_ST_FAULT_RESET;
  ELSE stCode := UT_ST_FAULT;
  END_IF;
ELSE
  stCode := UT_ST_WARNING;
END_IF;
IF stCode <> shownSt OR Code <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := Code;
  IF stCode = UT_ST_OK THEN
    Data.sts.statusText := UT_STATUS_TEXT(stCode, UT_F_NONE);
  ELSE
    Data.sts.statusText := UT_STATUS_TEXT(stCode, Code);
  END_IF;
END_IF;
Data.sts.statusCode := stCode;
IF Q THEN Data.sts.faultId := Code; ELSE Data.sts.faultId := UT_F_NONE; END_IF;
Data.sts.ne107 := UT_NE107_RUN(Fault := Q AND Data.set.alarm.prot.response = UT_RESP_TRIP, Check := removed,
                               OutOfSpec := Q AND Data.set.alarm.prot.response <> UT_RESP_TRIP, Maint := FALSE);

END_FUNCTION_BLOCK