(* FB_Flasher — on/off pulse generator.

While bEnable is on, bQ is on for tOnTime and off for tOffTime, over and over.
bStartOn chooses the first phase: on (a flasher) or off (an "every X, pulse"
timer). bPulse is on for one scan at the start of every on phase, and nOnPhaseCount
counts the on phases since bEnable came on.

The phases are timed from where they should have started, not from the
scan that noticed them, so the timing never drifts: after 10,000 cycles the
on phases still start at exact multiples of tOnTime + tOffTime. A change of
tOnTime or tOffTime acts on the phase running now.

tOnTime = 0: bQ stays off and bPulse fires every tOffTime. tOffTime = 0: bQ stays
on and bPulse fires every tOnTime. Both 0: bPulse fires every scan. Negative
times count as 0. If a cycle is shorter than the task interval, bQ and bPulse
can only change once per scan, but nOnPhaseCount still counts every cycle.

bPause freezes the phase clock with bQ off (a stirrer blocked at minimum
level keeps the rest of its on phase); the phase carries on where it
stopped when bPause drops. A rising edge on bStartNow starts an on phase now
and restarts the cycle from it (while bPause is on, it starts when bPause
drops). tElapsedTime and tTimeLeft are the time spent in and left of the phase
running now; tNextOnTimeLeft is the time to the next on phase (0 while on). *)

FUNCTION_BLOCK FB_Flasher
  VAR_INPUT
    bEnable : BOOL; (* runs while TRUE *)
    tOnTime : TIME := T#500ms; (* on time *)
    tOffTime : TIME := T#500ms; (* off time *)
    bStartOn : BOOL := TRUE; (* first phase on (TRUE) or off (FALSE) *)
    bPause : BOOL; (* freeze the phase clock, bQ off; carries on when released *)
    bStartNow : BOOL; (* rising edge: start an on phase now, the cycle restarts from it *)
  END_VAR
  VAR_OUTPUT
    bQ : BOOL; (* the flashing output *)
    bPulse : BOOL; (* one scan at the start of every on phase *)
    nOnPhaseCount : UDINT; (* on phases since bEnable came on *)
    tElapsedTime : TIME; (* time spent in the phase running now *)
    tTimeLeft : TIME; (* time left in the phase running now *)
    tNextOnTimeLeft : TIME; (* time to the next on phase (0 while on) *)
  END_VAR
  VAR
    tCur : TIME;
    bRunning : BOOL;
    bBegun : BOOL; (* the first on phase has started *)
    tStart : TIME; (* when bEnable came on *)
    tCycleStart : TIME; (* when the current on phase started *)
    tOnDur : TIME;
    tOffDur : TIME;
    tEl : TIME;
    tLate : TIME; (* how long ago the next on phase was due *)
    tPeriod : TIME;
    tAcc : TIME;
    bDue : BOOL;
    nN : LINT; (* whole cycles missed between two scans *)
    nK : LINT;
    nI : INT;
    bHeld : BOOL; (* bPause is freezing the clock *)
    tHoldAt : TIME; (* when the hold began *)
    tEval : TIME; (* the clock the phase is read at (frozen while held) *)
    bSnPrev : BOOL;
    bSnPend : BOOL; (* bStartNow seen while held: start on release *)
  END_VAR


tCur := TIME();
bPulse := FALSE;

IF NOT bEnable THEN
  bRunning := FALSE;
  bBegun := FALSE;
  bHeld := FALSE;
  bSnPend := FALSE;
  bSnPrev := bStartNow;
  bQ := FALSE;
  tElapsedTime := T#0s;
  tTimeLeft := T#0s;
  tNextOnTimeLeft := T#0s;
  RETURN;
END_IF;

tOnDur := tOnTime;
IF tOnDur < T#0s THEN
  tOnDur := T#0s;
END_IF;
tOffDur := tOffTime;
IF tOffDur < T#0s THEN
  tOffDur := T#0s;
END_IF;

IF NOT bRunning THEN
  bRunning := TRUE;
  tStart := tCur;
  nOnPhaseCount := 0;
END_IF;

(* bPause: the clock stops; on release every reference moves on by the time
   held, so the phase carries on where it stopped *)
IF bPause AND NOT bHeld THEN
  bHeld := TRUE;
  tHoldAt := tCur;
ELSIF bHeld AND NOT bPause THEN
  bHeld := FALSE;
  tStart := tStart + (tCur - tHoldAt);
  tCycleStart := tCycleStart + (tCur - tHoldAt);
END_IF;

(* bStartNow: an on phase now (after the hold, if held) *)
IF bStartNow AND NOT bSnPrev THEN
  bSnPend := TRUE;
END_IF;
bSnPrev := bStartNow;

IF bHeld THEN
  bDue := FALSE;
ELSIF bSnPend THEN
  bSnPend := FALSE;
  bDue := TRUE;
  tLate := T#0s;
(* Is the next on phase due? Written as differences so that huge times
   never overflow. *)
ELSIF bBegun THEN
  tEl := tCur - tCycleStart;
  bDue := tEl >= tOnDur AND tEl - tOnDur >= tOffDur;
  IF bDue THEN
    tLate := tEl - tOnDur - tOffDur;
  END_IF;
ELSE
  tEl := tCur - tStart;
  IF bStartOn THEN
    bDue := TRUE;
    tLate := tEl;
  ELSE
    bDue := tEl >= tOffDur;
    IF bDue THEN
      tLate := tEl - tOffDur;
    END_IF;
  END_IF;
END_IF;

IF bDue THEN
  (* whole cycles that also passed since then (a cycle shorter than a
     scan): n := late / period, late := the remainder, by binary division *)
  nN := 0;
  IF tLate >= tOnDur THEN
    IF tLate - tOnDur >= tOffDur THEN
      tPeriod := tOnDur + tOffDur;  (* no larger than late, so no overflow *)
      IF tPeriod <= T#0s THEN
        tLate := T#0s;            (* both times 0: a new cycle every scan *)
      ELSE
        (* TIME is 64 bits, so at most 62 doublings and 63 halvings *)
        tAcc := tPeriod;
        nK := 1;
        FOR nI := 1 TO 62 DO
          IF tAcc > tLate - tAcc THEN
            EXIT;
          END_IF;
          tAcc := tAcc + tAcc;
          nK := nK + nK;
        END_FOR;
        FOR nI := 1 TO 63 DO
          IF nK < 1 THEN
            EXIT;
          END_IF;
          IF tLate >= tAcc THEN
            tLate := tLate - tAcc;
            nN := nN + nK;
          END_IF;
          nK := nK / 2;
          tAcc := tAcc / 2;
        END_FOR;
      END_IF;
    END_IF;
  END_IF;
  tCycleStart := tCur - tLate;
  bBegun := TRUE;
  nOnPhaseCount := nOnPhaseCount + 1 + LINT_TO_UDINT(nN);
  bPulse := TRUE;
END_IF;

IF bHeld THEN
  tEval := tHoldAt;
ELSE
  tEval := tCur;
END_IF;
bQ := bBegun AND NOT bHeld AND (tEval - tCycleStart < tOnDur);

(* the time in and left of the phase running now *)
IF bBegun THEN
  tEl := tEval - tCycleStart;
  IF tEl < tOnDur THEN
    tElapsedTime := tEl;
    tTimeLeft := tOnDur - tEl;
    tNextOnTimeLeft := T#0s;
  ELSE
    tElapsedTime := tEl - tOnDur;
    tTimeLeft := tOffDur - tElapsedTime;
    tNextOnTimeLeft := tTimeLeft;
  END_IF;
ELSE
  tElapsedTime := tEval - tStart;
  tTimeLeft := tOffDur - tElapsedTime;
  tNextOnTimeLeft := tTimeLeft;
END_IF;
IF tTimeLeft < T#0s THEN
  tTimeLeft := T#0s;
END_IF;
IF tNextOnTimeLeft < T#0s THEN
  tNextOnTimeLeft := T#0s;
END_IF;

END_FUNCTION_BLOCK