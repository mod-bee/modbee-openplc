(* UT_TIME_TEXT — a duration as short text for a simple display (function).
The blocks do not call it: their times are TIME fields (timeLeft ...).

The two largest units, rounded up to the smaller one, so a countdown never
shows 0 while time is still left:

under 1 min        '35 s'
under 1 h          '42 m 10 s'   ('42 m' when the seconds are 0)
under 1 day        '1 h 20 m'    ('1 h')
1 day and more     '2 d 3 h'     ('2 d')

0, anything under a millisecond, and a negative TIME give '0 s'.

txt := CONCAT('Restart in ', UT_TIME_TEXT(Pump1.timeLeft)); *)

FUNCTION UT_TIME_TEXT : STRING(16)
  VAR_INPUT
    In : TIME; (* any duration *)
  END_VAR
  VAR
    ms : LINT; (* In in whole milliseconds *)
    big : LINT; (* the larger unit shown *)
    small : LINT; (* the smaller unit shown *)
    u1 : STRING(2); (* their unit letters *)
    u2 : STRING(2);
    txt : STRING(16);
  END_VAR


ms := TIME_TO_LINT(In);
IF ms <= 0 THEN
  UT_TIME_TEXT := '0 s';
  RETURN;
END_IF;

small := (ms + 999) / 1000;              (* seconds, rounded up *)
IF small < 3600 THEN
  big := small / 60;
  small := small MOD 60;
  u1 := ' m';
  u2 := ' s';
ELSE
  small := (small + 59) / 60;            (* minutes, rounded up *)
  IF small < 1440 THEN
    big := small / 60;
    small := small MOD 60;
    u1 := ' h';
    u2 := ' m';
  ELSE
    small := (small + 59) / 60;          (* hours, rounded up *)
    big := small / 24;
    small := small MOD 24;
    u1 := ' d';
    u2 := ' h';
  END_IF;
END_IF;

IF big = 0 THEN
  txt := CONCAT(DINT_TO_STRING(LINT_TO_DINT(small)), u2);
ELSE
  txt := CONCAT(DINT_TO_STRING(LINT_TO_DINT(big)), u1);
  IF small > 0 THEN
    txt := CONCAT(CONCAT(txt, ' '), CONCAT(DINT_TO_STRING(LINT_TO_DINT(small)), u2));
  END_IF;
END_IF;
UT_TIME_TEXT := txt;

END_FUNCTION