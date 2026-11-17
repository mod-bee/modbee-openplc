(* F_TimeText — a duration as short text for a simple display (function).
The blocks do not call it: their times are TIME fields (timeLeft ...).

The two largest units, rounded up to the smaller one, so a countdown never
shows 0 while time is still left:

under 1 min        '35 s'
under 1 h          '42 m 10 s'   ('42 m' when the seconds are 0)
under 1 day        '1 h 20 m'    ('1 h')
1 day and more     '2 d 3 h'     ('2 d')

0, anything under a millisecond, and a negative TIME give '0 s'.

txt := CONCAT('Restart in ', F_TimeText(Pump1.timeLeft)); *)

FUNCTION F_TimeText : STRING(16)
  VAR_INPUT
    tIn : TIME; (* any duration *)
  END_VAR
  VAR
    nMs : LINT; (* tIn in whole milliseconds *)
    nBig : LINT; (* the larger unit shown *)
    nSmall : LINT; (* the smaller unit shown *)
    sU1 : STRING(2); (* their unit letters *)
    sU2 : STRING(2);
    sTxt : STRING(16);
  END_VAR


nMs := TIME_TO_LINT(tIn);
IF nMs <= 0 THEN
  F_TimeText := '0 s';
  RETURN;
END_IF;

nSmall := (nMs + 999) / 1000;              (* seconds, rounded up *)
IF nSmall < 3600 THEN
  nBig := nSmall / 60;
  nSmall := nSmall MOD 60;
  sU1 := ' m';
  sU2 := ' s';
ELSE
  nSmall := (nSmall + 59) / 60;            (* minutes, rounded up *)
  IF nSmall < 1440 THEN
    nBig := nSmall / 60;
    nSmall := nSmall MOD 60;
    sU1 := ' h';
    sU2 := ' m';
  ELSE
    nSmall := (nSmall + 59) / 60;          (* hours, rounded up *)
    nBig := nSmall / 24;
    nSmall := nSmall MOD 24;
    sU1 := ' d';
    sU2 := ' h';
  END_IF;
END_IF;

IF nBig = 0 THEN
  sTxt := CONCAT(DINT_TO_STRING(LINT_TO_DINT(nSmall)), sU2);
ELSE
  sTxt := CONCAT(DINT_TO_STRING(LINT_TO_DINT(nBig)), sU1);
  IF nSmall > 0 THEN
    sTxt := CONCAT(CONCAT(sTxt, ' '), CONCAT(DINT_TO_STRING(LINT_TO_DINT(nSmall)), sU2));
  END_IF;
END_IF;
F_TimeText := sTxt;

END_FUNCTION