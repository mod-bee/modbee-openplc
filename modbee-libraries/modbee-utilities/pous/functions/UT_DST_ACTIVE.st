(* TRUE while daylight saving is in force under the rule *)

FUNCTION UT_DST_ACTIVE : BOOL
  VAR_INPUT
    Utc : DT := DT#1970-01-01-00:00:00; (* the controller clock (UTC) *)
    OffsetMin : INT := 720; (* standard offset, minutes east of UTC (NZ 720) *)
    Dst : UT_DST_RULE := UT_DST_NZ;
  END_VAR
  VAR
    t : LINT; (* the time the rule counts in, seconds since 1970 *)
    day : DINT;
    y : INT;
    k : INT;
    mon : INT; (* the month the change is in *)
    wk : INT; (* the Sunday: 1 first, 2 second, -1 last *)
    hr : LINT; (* the hour of the change, in t *)
    d : DINT;
    onAt : LINT; (* daylight saving starts (in t) *)
    offAt : LINT; (* and ends (in t) *)
  END_VAR


UT_DST_ACTIVE := FALSE;
IF NOT (Dst = UT_DST_NZ OR Dst = UT_DST_AU_SE OR Dst = UT_DST_EU OR Dst = UT_DST_US) THEN
  RETURN;                        (* NONE, or unknown *)
END_IF;
t := DT_TO_LINT(Utc);
IF Dst <> UT_DST_EU THEN
  t := t + INT_TO_LINT(OffsetMin) * 60;   (* local standard time *)
END_IF;
IF t >= 0 THEN
  day := LINT_TO_DINT(t / 86400);
ELSE
  day := LINT_TO_DINT((t - 86399) / 86400);
END_IF;
(* the year: a close guess, then corrected *)
y := DINT_TO_INT(1970 + (day * 4 + 2) / 1461);
IF UT_DATE_DAYS(Year := y, Month := 1, Day := 1) > day THEN
  y := y - 1;
ELSIF UT_DATE_DAYS(Year := y + 1, Month := 1, Day := 1) <= day THEN
  y := y + 1;
END_IF;
FOR k := 1 TO 2 DO               (* 1: the start, 2: the end *)
  CASE Dst OF
  UT_DST_NZ:
    IF k = 1 THEN mon := 9; wk := -1; ELSE mon := 4; wk := 1; END_IF;
    hr := 2;                     (* 02:00 standard (the end: 03:00 daylight) *)
  UT_DST_AU_SE:
    IF k = 1 THEN mon := 10; ELSE mon := 4; END_IF;
    wk := 1;
    hr := 2;
  UT_DST_EU:
    IF k = 1 THEN mon := 3; ELSE mon := 10; END_IF;
    wk := -1;
    hr := 1;                     (* 01:00 UTC *)
  ELSE                           (* UT_DST_US *)
    IF k = 1 THEN mon := 3; wk := 2; hr := 2; ELSE mon := 11; wk := 1; hr := 1; END_IF;
  END_CASE;
  IF wk < 0 THEN
    d := UT_DATE_DAYS(Year := y, Month := mon + 1, Day := 1) - 1;   (* the last day *)
    d := d - (d + 4) MOD 7;      (* back to Sunday (1970-01-01 was a Thursday) *)
  ELSE
    d := UT_DATE_DAYS(Year := y, Month := mon, Day := 1);
    d := d + (7 - (d + 4) MOD 7) MOD 7 + 7 * INT_TO_DINT(wk - 1);
  END_IF;
  IF k = 1 THEN
    onAt := DINT_TO_LINT(d) * 86400 + hr * 3600;
  ELSE
    offAt := DINT_TO_LINT(d) * 86400 + hr * 3600;
  END_IF;
END_FOR;
IF onAt < offAt THEN
  UT_DST_ACTIVE := t >= onAt AND t < offAt;    (* northern: within the year *)
ELSE
  UT_DST_ACTIVE := t >= onAt OR t < offAt;     (* southern: over the new year *)
END_IF;

END_FUNCTION