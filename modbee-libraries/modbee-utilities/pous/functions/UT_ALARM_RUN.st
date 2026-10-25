(* One alarm: TRUE = raised this scan; Sounding = it wants the siren *)

FUNCTION UT_ALARM_RUN : BOOL
  VAR_INPUT
    TNow : TIME;
    In : BOOL; (* the condition *)
    AckReq : BOOL; (* acknowledge *)
    ResetReq : BOOL; (* reset: a LATCHED / LOCKED alarm whose condition has gone clears *)
    SilenceReq : BOOL;
  END_VAR
  VAR_OUTPUT
    Sounding : BOOL;
  END_VAR
  VAR_IN_OUT
    Set : UT_AT_SET;
    Mem : UT_AT_MEM;
    Sts : UT_AT_STS;
  END_VAR
  VAR
    raise : BOOL;
    lock : BOOL;
    onD : TIME;
    offD : TIME;
  END_VAR


raise := FALSE;
Sounding := FALSE;
onD := MAX(Set.prot.delay, T#0s);            (* a bad time acts as 0: louder, never quieter *)
offD := MAX(Set.prot.recover, T#0s);
IF In <> Mem.inPrev THEN
  Mem.t := TNow;
END_IF;
Mem.inPrev := In;
IF Set.prot.response = UT_RESP_OFF THEN
  Mem.cond := FALSE;
  Sts.state := UT_AT_OFF;
  Sts.unacked := FALSE;
  Mem.silenced := FALSE;
  Sts.retries := 0;
ELSE
  IF Sts.state = UT_AT_OFF THEN
    Sts.state := UT_AT_NORMAL;               (* switched on again *)
  END_IF;
  IF Mem.cond THEN
    IF NOT In AND TNow - Mem.t >= offD THEN
      Mem.cond := FALSE;
    END_IF;
  ELSIF In AND TNow - Mem.t >= onD THEN
    Mem.cond := TRUE;
    raise := TRUE;
  END_IF;
  (* the retry window ran out: count again *)
  IF Sts.retries > 0 AND Sts.state <> UT_AT_LOCKED AND Set.retryWindow > T#0s AND TNow - Mem.tWin >= Set.retryWindow THEN
    Sts.retries := 0;
  END_IF;
  IF raise THEN
    lock := FALSE;
    IF Set.prot.reset = UT_RST_RETRY THEN
      IF Sts.retries = 0 THEN
        Mem.tWin := TNow;
      END_IF;
      IF Sts.retries < 255 THEN
        Sts.retries := Sts.retries + 1;
      END_IF;
      lock := USINT_TO_INT(Sts.retries) > Set.prot.maxRetries OR Sts.state = UT_AT_LOCKED;
    END_IF;
    IF lock THEN
      Sts.state := UT_AT_LOCKED;
    ELSE
      Sts.state := UT_AT_ACTIVE;
    END_IF;
    Sts.unacked := TRUE;
    Mem.silenced := FALSE;
  ELSIF Sts.state = UT_AT_ACTIVE AND NOT Mem.cond THEN
    IF Set.prot.reset = UT_RST_MANUAL THEN
      Sts.state := UT_AT_LATCHED;
    ELSIF Sts.unacked THEN
      Sts.state := UT_AT_RETURNED;
    ELSE
      Sts.state := UT_AT_NORMAL;
    END_IF;
  END_IF;
  (* acknowledge and reset *)
  IF AckReq AND Sts.unacked THEN
    Sts.unacked := FALSE;
    Mem.tAck := TNow;
  END_IF;
  IF ResetReq AND NOT Mem.cond THEN
    Sts.retries := 0;
    IF Sts.state <> UT_AT_ACTIVE THEN
      Sts.state := UT_AT_NORMAL;
    END_IF;
  END_IF;
  IF Sts.state = UT_AT_RETURNED AND NOT Sts.unacked THEN
    Sts.state := UT_AT_NORMAL;
  END_IF;
  IF Set.prot.reset <> UT_RST_MANUAL AND Sts.state = UT_AT_LATCHED THEN
    Sts.state := UT_AT_NORMAL;               (* changed from MANUAL while latched *)
  END_IF;
  (* silence and re-arm *)
  Sounding := Set.siren AND Sts.unacked AND NOT Mem.silenced
              AND (Sts.state = UT_AT_ACTIVE OR (Sts.state = UT_AT_LOCKED AND Mem.cond));
  IF SilenceReq AND Sounding THEN
    Mem.silenced := TRUE;
    Mem.tAck := TNow;
    Sounding := FALSE;
  END_IF;
  IF Mem.cond AND (Mem.silenced OR NOT Sts.unacked) AND Set.rearm > T#0s AND TNow - Mem.tAck >= Set.rearm THEN
    Sts.unacked := TRUE;                     (* still on: annunciate it again *)
    Mem.silenced := FALSE;
    Mem.tAck := TNow;
    Sounding := Set.siren;
  END_IF;
END_IF;
Sts.q := Sts.state = UT_AT_ACTIVE OR Sts.state = UT_AT_LATCHED OR Sts.state = UT_AT_LOCKED;
Sts.code := Set.code;
UT_ALARM_RUN := raise;

END_FUNCTION