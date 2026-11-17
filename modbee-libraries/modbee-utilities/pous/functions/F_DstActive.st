(* TRUE while daylight saving is in force under the rule *)

FUNCTION F_DstActive : BOOL
  VAR_INPUT
    dtUtc : DT := DT#1970-01-01-00:00:00; (* the controller clock (UTC) *)
    nOffsetMin : INT := 720; (* standard offset, minutes east of UTC (NZ 720) *)
    eDst : E_DstRule := E_DstRule.Nz;
  END_VAR
  VAR
    nT : LINT; (* the time the rule counts in, seconds since 1970 *)
    nDay : DINT;
    nY : INT;
    nK : INT;
    nMon : INT; (* the month the change is in *)
    nWk : INT; (* the Sunday: 1 first, 2 second, -1 last *)
    nHr : LINT; (* the hour of the change, in t *)
    nD : DINT;
    nOnAt : LINT; (* daylight saving starts (in t) *)
    nOffAt : LINT; (* and ends (in t) *)
  END_VAR


F_DstActive := FALSE;
IF NOT (eDst = E_DstRule.Nz OR eDst = E_DstRule.AuSe OR eDst = E_DstRule.Eu OR eDst = E_DstRule.Us) THEN
  RETURN;                        (* NONE, or unknown *)
END_IF;
nT := DT_TO_LINT(dtUtc);
IF eDst <> E_DstRule.Eu THEN
  nT := nT + INT_TO_LINT(nOffsetMin) * 60;   (* local standard time *)
END_IF;
IF nT >= 0 THEN
  nDay := LINT_TO_DINT(nT / 86400);
ELSE
  nDay := LINT_TO_DINT((nT - 86399) / 86400);
END_IF;
(* the year: a close guess, then corrected *)
nY := DINT_TO_INT(1970 + (nDay * 4 + 2) / 1461);
IF F_DateDays(nYear := nY, nMonth := 1, nDay := 1) > nDay THEN
  nY := nY - 1;
ELSIF F_DateDays(nYear := nY + 1, nMonth := 1, nDay := 1) <= nDay THEN
  nY := nY + 1;
END_IF;
FOR nK := 1 TO 2 DO               (* 1: the start, 2: the end *)
  CASE eDst OF
  E_DstRule.Nz:
    IF nK = 1 THEN nMon := 9; nWk := -1; ELSE nMon := 4; nWk := 1; END_IF;
    nHr := 2;                     (* 02:00 standard (the end: 03:00 daylight) *)
  E_DstRule.AuSe:
    IF nK = 1 THEN nMon := 10; ELSE nMon := 4; END_IF;
    nWk := 1;
    nHr := 2;
  E_DstRule.Eu:
    IF nK = 1 THEN nMon := 3; ELSE nMon := 10; END_IF;
    nWk := -1;
    nHr := 1;                     (* 01:00 UTC *)
  ELSE                           (* E_DstRule.Us *)
    IF nK = 1 THEN nMon := 3; nWk := 2; nHr := 2; ELSE nMon := 11; nWk := 1; nHr := 1; END_IF;
  END_CASE;
  IF nWk < 0 THEN
    nD := F_DateDays(nYear := nY, nMonth := nMon + 1, nDay := 1) - 1;   (* the last day *)
    nD := nD - (nD + 4) MOD 7;      (* back to Sunday (1970-01-01 was a Thursday) *)
  ELSE
    nD := F_DateDays(nYear := nY, nMonth := nMon, nDay := 1);
    nD := nD + (7 - (nD + 4) MOD 7) MOD 7 + 7 * INT_TO_DINT(nWk - 1);
  END_IF;
  IF nK = 1 THEN
    nOnAt := DINT_TO_LINT(nD) * 86400 + nHr * 3600;
  ELSE
    nOffAt := DINT_TO_LINT(nD) * 86400 + nHr * 3600;
  END_IF;
END_FOR;
IF nOnAt < nOffAt THEN
  F_DstActive := nT >= nOnAt AND nT < nOffAt;    (* northern: within the year *)
ELSE
  F_DstActive := nT >= nOnAt OR nT < nOffAt;     (* southern: over the new year *)
END_IF;

END_FUNCTION