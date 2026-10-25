(* UT_FLASHER — on/off pulse generator.

While Enable is on, Q is on for OnTime and off for OffTime, over and over.
StartOn chooses the first phase: on (a flasher) or off (an "every X, pulse"
timer). Pulse is on for one scan at the start of every on phase, and Cycles
counts the on phases since Enable came on.

The phases are timed from where they should have started, not from the
scan that noticed them, so the timing never drifts: after 10,000 cycles the
on phases still start at exact multiples of OnTime + OffTime. A change of
OnTime or OffTime acts on the phase running now.

OnTime = 0: Q stays off and Pulse fires every OffTime. OffTime = 0: Q stays
on and Pulse fires every OnTime. Both 0: Pulse fires every scan. Negative
times count as 0. If a cycle is shorter than the task interval, Q and Pulse
can only change once per scan, but Cycles still counts every cycle.

Hold freezes the phase clock with Q off (a stirrer blocked at minimum
level keeps the rest of its on phase); the phase carries on where it
stopped when Hold drops. A rising edge on StartNow starts an on phase now
and restarts the cycle from it (while Hold is on, it starts when Hold
drops). ET and Remaining are the time spent in and left of the phase
running now; NextOnIn is the time to the next on phase (0 while on). *)

FUNCTION_BLOCK UT_FLASHER
  VAR_INPUT
    Enable : BOOL; (* runs while TRUE *)
    OnTime : TIME := T#500ms;
    OffTime : TIME := T#500ms;
    StartOn : BOOL := TRUE; (* first phase on (TRUE) or off (FALSE) *)
    Hold : BOOL; (* freeze the phase clock, Q off; carries on when released *)
    StartNow : BOOL; (* rising edge: start an on phase now, the cycle restarts from it *)
  END_VAR
  VAR_OUTPUT
    Q : BOOL;
    Pulse : BOOL; (* one scan at the start of every on phase *)
    Cycles : UDINT; (* on phases since Enable came on *)
    ET : TIME; (* time spent in the phase running now *)
    Remaining : TIME; (* time left in the phase running now *)
    NextOnIn : TIME; (* time to the next on phase (0 while on) *)
  END_VAR
  VAR
    tCur : TIME;
    running : BOOL;
    begun : BOOL; (* the first on phase has started *)
    tStart : TIME; (* when Enable came on *)
    cycleStart : TIME; (* when the current on phase started *)
    onDur : TIME;
    offDur : TIME;
    el : TIME;
    late : TIME; (* how long ago the next on phase was due *)
    period : TIME;
    acc : TIME;
    due : BOOL;
    n : LINT; (* whole cycles missed between two scans *)
    k : LINT;
    i : INT;
    held : BOOL; (* Hold is freezing the clock *)
    holdAt : TIME; (* when the hold began *)
    tEval : TIME; (* the clock the phase is read at (frozen while held) *)
    snPrev : BOOL;
    snPend : BOOL; (* StartNow seen while held: start on release *)
  END_VAR


tCur := TIME();
Pulse := FALSE;

IF NOT Enable THEN
  running := FALSE;
  begun := FALSE;
  held := FALSE;
  snPend := FALSE;
  snPrev := StartNow;
  Q := FALSE;
  ET := T#0s;
  Remaining := T#0s;
  NextOnIn := T#0s;
  RETURN;
END_IF;

onDur := OnTime;
IF onDur < T#0s THEN
  onDur := T#0s;
END_IF;
offDur := OffTime;
IF offDur < T#0s THEN
  offDur := T#0s;
END_IF;

IF NOT running THEN
  running := TRUE;
  tStart := tCur;
  Cycles := 0;
END_IF;

(* Hold: the clock stops; on release every reference moves on by the time
   held, so the phase carries on where it stopped *)
IF Hold AND NOT held THEN
  held := TRUE;
  holdAt := tCur;
ELSIF held AND NOT Hold THEN
  held := FALSE;
  tStart := tStart + (tCur - holdAt);
  cycleStart := cycleStart + (tCur - holdAt);
END_IF;

(* StartNow: an on phase now (after the hold, if held) *)
IF StartNow AND NOT snPrev THEN
  snPend := TRUE;
END_IF;
snPrev := StartNow;

IF held THEN
  due := FALSE;
ELSIF snPend THEN
  snPend := FALSE;
  due := TRUE;
  late := T#0s;
(* Is the next on phase due? Written as differences so that huge times
   never overflow. *)
ELSIF begun THEN
  el := tCur - cycleStart;
  due := el >= onDur AND el - onDur >= offDur;
  IF due THEN
    late := el - onDur - offDur;
  END_IF;
ELSE
  el := tCur - tStart;
  IF StartOn THEN
    due := TRUE;
    late := el;
  ELSE
    due := el >= offDur;
    IF due THEN
      late := el - offDur;
    END_IF;
  END_IF;
END_IF;

IF due THEN
  (* whole cycles that also passed since then (a cycle shorter than a
     scan): n := late / period, late := the remainder, by binary division *)
  n := 0;
  IF late >= onDur THEN
    IF late - onDur >= offDur THEN
      period := onDur + offDur;  (* no larger than late, so no overflow *)
      IF period <= T#0s THEN
        late := T#0s;            (* both times 0: a new cycle every scan *)
      ELSE
        (* TIME is 64 bits, so at most 62 doublings and 63 halvings *)
        acc := period;
        k := 1;
        FOR i := 1 TO 62 DO
          IF acc > late - acc THEN
            EXIT;
          END_IF;
          acc := acc + acc;
          k := k + k;
        END_FOR;
        FOR i := 1 TO 63 DO
          IF k < 1 THEN
            EXIT;
          END_IF;
          IF late >= acc THEN
            late := late - acc;
            n := n + k;
          END_IF;
          k := k / 2;
          acc := acc / 2;
        END_FOR;
      END_IF;
    END_IF;
  END_IF;
  cycleStart := tCur - late;
  begun := TRUE;
  Cycles := Cycles + 1 + LINT_TO_UDINT(n);
  Pulse := TRUE;
END_IF;

IF held THEN
  tEval := holdAt;
ELSE
  tEval := tCur;
END_IF;
Q := begun AND NOT held AND (tEval - cycleStart < onDur);

(* the time in and left of the phase running now *)
IF begun THEN
  el := tEval - cycleStart;
  IF el < onDur THEN
    ET := el;
    Remaining := onDur - el;
    NextOnIn := T#0s;
  ELSE
    ET := el - onDur;
    Remaining := offDur - ET;
    NextOnIn := Remaining;
  END_IF;
ELSE
  ET := tEval - tStart;
  Remaining := offDur - ET;
  NextOnIn := Remaining;
END_IF;
IF Remaining < T#0s THEN
  Remaining := T#0s;
END_IF;
IF NextOnIn < T#0s THEN
  NextOnIn := T#0s;
END_IF;

END_FUNCTION_BLOCK