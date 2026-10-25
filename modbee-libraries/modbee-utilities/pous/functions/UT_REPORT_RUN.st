(* The report decision: TRUE = send now (Value, Reason) *)

FUNCTION UT_REPORT_RUN : BOOL
  VAR_INPUT
    TNow : TIME;
    In : REAL;
    Quality : UT_QUALITY := UT_Q_GOOD;
    ForceReq : BOOL; (* a force request this scan *)
    Enable : BOOL := TRUE;
    Heartbeat : TIME; (* in use *)
    OnStart : BOOL; (* reportOnStart in use *)
  END_VAR
  VAR_OUTPUT
    Value : REAL;
    Reason : UT_REPORT_REASON;
  END_VAR
  VAR_IN_OUT
    Set : UT_REPORT_SET;
    Mem : UT_REPORT_MEM;
    Sts : UT_REPORT_STS;
  END_VAR
  VAR
    v : REAL;
    q : UT_QUALITY;
    db : REAL;
    r : LREAL;
    mode : UT_DEADBAND_MODE;
    send : BOOL;
  END_VAR


send := FALSE;
Reason := UT_RPT_NONE;
(* NaN fails every comparison; infinity is beyond any real *)
IF NOT (In = In) OR In > 3.4E38 OR In < -3.4E38 THEN
  v := Mem.good;
  q := UT_Q_BAD;
ELSE
  v := In;
  IF Set.resolution > 0.0 AND Set.resolution <= 3.4E38 THEN
    r := REAL_TO_LREAL(v) / REAL_TO_LREAL(Set.resolution);
    IF r < 1.0E15 AND r > -1.0E15 THEN
      v := LREAL_TO_REAL(LINT_TO_LREAL(LREAL_TO_LINT(r)) * REAL_TO_LREAL(Set.resolution));
    END_IF;
  END_IF;
  Mem.good := v;
  q := Quality;
END_IF;
IF ForceReq THEN
  Mem.force := Enable;
END_IF;
IF NOT Enable THEN
  Mem.started := FALSE;
  Mem.force := FALSE;
  Mem.change := FALSE;
  Mem.held := FALSE;
ELSIF NOT Mem.started THEN
  Mem.started := TRUE;
  Mem.force := FALSE;
  Mem.change := FALSE;
  Mem.held := FALSE;
  IF OnStart THEN
    send := TRUE;
    Reason := UT_RPT_FIRST;
  ELSE
    Sts.lastValue := v;          (* the starting point for changes *)
    Sts.quality := q;
    Mem.lastAt := TNow;
  END_IF;
ELSE
  db := Set.deadband;
  IF NOT (db >= 0.0) THEN
    db := 0.0;
  END_IF;
  mode := Set.deadbandMode;
  IF mode = UT_DB_ABS AND Set.deadbandPct THEN
    mode := UT_DB_PCT_VALUE;
  END_IF;
  IF mode = UT_DB_PCT_VALUE THEN
    db := ABS(Sts.lastValue) * db / 100.0;
  ELSIF mode = UT_DB_PCT_SPAN THEN
    IF Set.span > 0.0 AND Set.span <= 3.4E38 THEN
      db := Set.span * db / 100.0;
    ELSE
      db := 0.0;
    END_IF;
  END_IF;
  IF ABS(v - Sts.lastValue) > db OR q <> Sts.quality THEN
    Mem.change := TRUE;
  END_IF;
  IF TNow - Mem.lastAt >= Set.minInterval THEN
    IF Mem.force THEN
      send := TRUE;
      Reason := UT_RPT_FORCED;
    ELSIF Mem.change THEN
      send := TRUE;
      Reason := UT_RPT_CHANGE;
    ELSIF Heartbeat > T#0s AND TNow - Mem.lastAt >= Heartbeat THEN
      send := TRUE;
      Reason := UT_RPT_HEARTBEAT;
    END_IF;
  ELSIF (Mem.force OR Mem.change) AND NOT Mem.held THEN
    Mem.held := TRUE;
    Sts.suppressed := Sts.suppressed + 1;
  END_IF;
END_IF;
Sts.report := send;
Value := Sts.lastValue;
IF send THEN
  Value := v;
  Sts.reason := Reason;
  Sts.lastValue := v;
  Sts.quality := q;
  Sts.reports := Sts.reports + 1;
  Mem.lastAt := TNow;
  Mem.force := FALSE;
  Mem.change := FALSE;
  Mem.held := FALSE;
END_IF;
UT_REPORT_RUN := send;

END_FUNCTION