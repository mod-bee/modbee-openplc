(* UT_ANNUNCIATOR — horn, alarm lamp and first-out for a group of UT_ALARMs.

Alarms is the array of the group's UT_ALARM records (each UT_ALARM uses one
element as its Data). The lamp follows the standard annunciator sequence:

  fast flash   a new alarm, not yet acknowledged
  slow flash   an alarm that cleared before it was acknowledged
  steady       alarms present, all acknowledged
  off          nothing

The horn sounds for each new alarm at or above hornPriority, until Ack,
Silence, hornTimeout, or nothing at that priority is left to acknowledge.
reHorn sounds it again while such an alarm stays unacknowledged. Ack
acknowledges every alarm in the group. LampTest turns the lamp and horn on
while held.

FirstOut is the array index of the alarm that started the current event (the
earliest sequence; alarms raised in the same millisecond: the lowest index).
The event ends when no alarm is present or waiting for acknowledgement; then
FirstOut is one below the array's first index (0 for ARRAY[1..n]).
Shelved, suppressed and out-of-service alarms are ignored. Healthy: no
TRIP alarm present (relayOnWarning: none at all). Settings kept. *)

FUNCTION_BLOCK UT_ANNUNCIATOR
  VAR_INPUT
    Ack : BOOL R_EDGE; (* acknowledge all (panel button) *)
    Silence : BOOL R_EDGE; (* silence the horn without acknowledging *)
    LampTest : BOOL; (* lamp and horn on while held *)
  END_VAR
  VAR_OUTPUT
    Horn : BOOL;
    Lamp : BOOL; (* fast flash new, steady acknowledged, slow flash cleared and unacknowledged *)
    AnyActive : BOOL; (* any alarm present *)
    AnyUnacked : BOOL; (* any alarm waiting for acknowledgement *)
    FirstOut : INT; (* array index of the first alarm in this event *)
    Highest : UT_PRIORITY; (* highest priority present *)
    ActiveCount : INT; (* alarms present *)
    Healthy : BOOL; (* no TRIP alarm present (fail-safe relay; relayOnWarning: none at all) *)
    BadSetting : BOOL;
  END_VAR
  VAR_IN_OUT
    Alarms : ARRAY [*] OF UT_ALARM_DATA;
    Data : UT_ANNUN_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_ANNUN_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    ok : BOOL;
    shownSt : UT_STATUS;
    lastSeq : UDINT; (* the newest raise seen (the horn sounds for newer ones) *)
    seqSeen : BOOL;
    tripOn : BOOL;
    tCur : TIME;
    i : DINT;
    lo : DINT;
    hi : DINT;
    st : UT_ALARM_STATE;
    prio : INT;
    hornPrio : INT;
    topPrio : INT;
    nActive : INT;
    nUnacked : INT;
    anyNew : BOOL; (* an alarm in UNACKED *)
    anyRtn : BOOL; (* an alarm in RTN_UNACKED *)
    anyAcked : BOOL; (* an alarm in ACKED *)
    newHorn : BOOL; (* a new alarm that sounds the horn *)
    hornUnacked : BOOL; (* an unacknowledged alarm at horn priority *)
    best : DINT; (* earliest alarm present or unacknowledged *)
    bestSeq : UDINT;
    eventOn : BOOL;
    first : DINT;
    hornOn : BOOL;
    hornStart : TIME;
    hornOffAt : TIME;
    pattern : INT; (* 0 off, 1 steady, 2 fast, 3 slow *)
    patternPrev : INT;
    flashOn : BOOL;
    flashAt : TIME;
    period : TIME;
    ackPrev : BOOL;
    silencePrev : BOOL;
    ackSeen : BOOL;
    silenceSeen : BOOL;
    ackReq : BOOL;
    silenceReq : BOOL;
  END_VAR


tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := Data.set.hornTimeout >= T#0s AND Data.set.reHorn >= T#0s AND Data.set.fastFlash >= T#0s AND Data.set.slowFlash >= T#0s;
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
(* pins act on a rising edge; HMI commands once per request, then cleared *)
ackReq := Ack OR (Data.cmdAck AND NOT ackSeen);
ackPrev := Ack;
ackSeen := Data.cmdAck;
Data.cmdAck := FALSE;
silenceReq := Silence OR (Data.cmdSilence AND NOT silenceSeen);
silencePrev := Silence;
silenceSeen := Data.cmdSilence;
Data.cmdSilence := FALSE;
CASE Data.set.hornPriority OF
UT_PRIO_MEDIUM: hornPrio := 1;
UT_PRIO_HIGH: hornPrio := 2;
UT_PRIO_CRITICAL: hornPrio := 3;
ELSE
  hornPrio := 0;
END_CASE;
lo := LOWER_BOUND(Alarms, 1);
hi := UPPER_BOUND(Alarms, 1);
nActive := 0;
nUnacked := 0;
topPrio := 0;
anyNew := FALSE;
anyRtn := FALSE;
anyAcked := FALSE;
newHorn := FALSE;
hornUnacked := FALSE;
best := lo - 1;
tripOn := FALSE;
FOR i := lo TO hi DO
  CASE Alarms[i].set.prio OF
  UT_PRIO_MEDIUM: prio := 1;
  UT_PRIO_HIGH: prio := 2;
  UT_PRIO_CRITICAL: prio := 3;
  ELSE
    prio := 0;
  END_CASE;
  st := Alarms[i].sts.state;
  IF st = UT_ALM_UNACKED OR st = UT_ALM_ACKED OR st = UT_ALM_LATCHED OR st = UT_ALM_LOCKED THEN
    nActive := nActive + 1;
    IF prio > topPrio THEN
      topPrio := prio;
    END_IF;
  END_IF;
  IF st = UT_ALM_UNACKED OR st = UT_ALM_RTN_UNACKED THEN
    nUnacked := nUnacked + 1;
    IF prio >= hornPrio THEN
      hornUnacked := TRUE;
    END_IF;
    IF ackReq THEN
      Alarms[i].grp.ack := TRUE;   (* the alarm acknowledges itself on its next call *)
    END_IF;
  END_IF;
  IF st = UT_ALM_UNACKED THEN
    anyNew := TRUE;
  ELSIF st = UT_ALM_RTN_UNACKED THEN
    anyRtn := TRUE;
  ELSIF st = UT_ALM_ACKED THEN
    anyAcked := TRUE;
  END_IF;
  IF st = UT_ALM_UNACKED AND (NOT seqSeen OR UDINT_TO_DINT(Alarms[i].sts.sequence - lastSeq) > 0) THEN
    IF prio >= hornPrio THEN
      newHorn := TRUE;           (* raised since the last look *)
    END_IF;
  END_IF;
  IF (st = UT_ALM_UNACKED OR st = UT_ALM_ACKED OR st = UT_ALM_LATCHED OR st = UT_ALM_LOCKED)
     AND Alarms[i].set.alarm.prot.response = UT_RESP_TRIP THEN
    tripOn := TRUE;
  END_IF;
  IF st = UT_ALM_UNACKED OR st = UT_ALM_ACKED OR st = UT_ALM_RTN_UNACKED OR st = UT_ALM_LATCHED OR st = UT_ALM_LOCKED THEN
    (* earliest sequence; it wraps, so compare the difference *)
    IF best < lo OR UDINT_TO_DINT(Alarms[i].sts.sequence - bestSeq) < 0 THEN
      best := i;
      bestSeq := Alarms[i].sts.sequence;
    END_IF;
  END_IF;
END_FOR;
(* the newest raise seen *)
FOR i := lo TO hi DO
  IF Alarms[i].sts.state = UT_ALM_UNACKED AND (NOT seqSeen OR UDINT_TO_DINT(Alarms[i].sts.sequence - lastSeq) > 0) THEN
    lastSeq := Alarms[i].sts.sequence;
    seqSeen := TRUE;
  END_IF;
END_FOR;
(* first-out: taken when an event starts, kept until it is over *)
IF best >= lo THEN
  IF NOT eventOn THEN
    eventOn := TRUE;
    first := best;
  END_IF;
ELSE
  eventOn := FALSE;
END_IF;
IF NOT eventOn THEN
  first := lo - 1;
END_IF;
(* horn *)
IF newHorn THEN
  hornOn := TRUE;
  hornStart := tCur;
END_IF;
IF ackReq OR silenceReq THEN
  hornOn := FALSE;
  hornOffAt := tCur;
END_IF;
IF hornOn AND Data.set.hornTimeout > T#0s AND tCur - hornStart >= Data.set.hornTimeout THEN
  hornOn := FALSE;
  hornOffAt := tCur;
END_IF;
IF NOT hornUnacked THEN
  hornOn := FALSE;
END_IF;
IF NOT hornOn AND hornUnacked AND Data.set.reHorn > T#0s AND tCur - hornOffAt >= Data.set.reHorn THEN
  hornOn := TRUE;
  hornStart := tCur;
END_IF;
(* lamp *)
IF anyNew THEN
  pattern := 2;
ELSIF anyRtn THEN
  pattern := 3;
ELSIF anyAcked THEN
  pattern := 1;
ELSE
  pattern := 0;
END_IF;
IF pattern <> patternPrev THEN
  flashOn := TRUE;
  flashAt := tCur;
  patternPrev := pattern;
END_IF;
IF pattern >= 2 THEN
  IF pattern = 2 THEN
    period := Data.set.fastFlash;
  ELSE
    period := Data.set.slowFlash;
  END_IF;
  IF period <= T#0s THEN
    flashOn := TRUE;
  ELSIF tCur - flashAt >= period THEN
    flashOn := NOT flashOn;
    flashAt := flashAt + period;
    IF tCur - flashAt >= period THEN
      flashAt := tCur;             (* the scan is slower than the flash *)
    END_IF;
  END_IF;
END_IF;
Horn := hornOn OR LampTest;
Lamp := LampTest OR pattern = 1 OR (pattern >= 2 AND flashOn);
AnyActive := nActive > 0;
AnyUnacked := nUnacked > 0;
FirstOut := DINT_TO_INT(first);
CASE topPrio OF
1: Highest := UT_PRIO_MEDIUM;
2: Highest := UT_PRIO_HIGH;
3: Highest := UT_PRIO_CRITICAL;
ELSE
  Highest := UT_PRIO_LOW;
END_CASE;
ActiveCount := nActive;
Data.sts.firstOut := FirstOut;
Data.sts.activeCount := nActive;
Data.sts.unackedCount := nUnacked;
Healthy := NOT tripOn AND NOT (Data.set.relayOnWarning AND nActive > 0);
BadSetting := NOT ok;
Data.sts.badSetting := BadSetting;
IF tripOn THEN
  Data.sts.statusCode := UT_ST_FAULT;
ELSIF nActive > 0 THEN
  Data.sts.statusCode := UT_ST_WARNING;
ELSE
  Data.sts.statusCode := UT_ST_OK;
END_IF;
IF Data.sts.statusCode <> shownSt OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := Data.sts.statusCode;
  Data.sts.statusText := UT_STATUS_TEXT(Data.sts.statusCode, UT_F_NONE);
END_IF;
Data.sts.ne107 := UT_NE107_RUN(Fault := tripOn, Check := FALSE, OutOfSpec := nActive > 0 OR BadSetting, Maint := FALSE);

END_FUNCTION_BLOCK