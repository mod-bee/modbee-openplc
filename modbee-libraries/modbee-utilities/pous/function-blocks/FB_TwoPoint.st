(* FB_TwoPoint — on/off (hysteresis) controller, thermostat style.

The setpoint order decides the direction, so there is no mode to set:
  fOnPoint < fOffPoint   fill / heat:   on below fOnPoint, off above fOffPoint
  fOnPoint > fOffPoint   empty / cool:  on above fOnPoint, off below fOffPoint
  fOnPoint = fOffPoint   a plain comparator with no hysteresis, in the
                       fill / heat direction (on below, off above)
A value exactly on a point is not past it, so nothing changes there.

tOnDelay / tOffDelay: the value must stay past the point this long.
tMinOn / tMinOff: anti-short-cycle. bQ stays on at least tMinOn, and stays off
at least tMinOff before it may come on again. tMinOff is not applied at
start-up. The points are re-evaluated every scan, so changing or swapping
them while running takes effect cleanly (through the delays).

bEnable FALSE turns bQ off at once, even inside tMinOn; tMinOff then counts from
that moment.

A value that is not a number (fIn or a point NaN or infinite) holds bQ as it
is and sets bBadInput; the delays start again once it is good.

tRemaining is the time left before bQ changes: the delay and the tMinOn /
tMinOff still to run while the value is past the point that changes it
(T#0s otherwise). bWaiting is TRUE while the value is past that point and
its delay is over, but tMinOn / tMinOff still holds bQ as it is. *)

FUNCTION_BLOCK FB_TwoPoint
  VAR_INPUT
    fIn : REAL; (* measured value *)
    bEnable : BOOL := TRUE; (* FALSE = output off *)
    eDir : E_TwoPointDir; (* ByOrder (the points decide), OnBelow (fill / heat), OnAbove (empty / cool) *)
    fOnPoint : REAL := 20.0;
    fOffPoint : REAL := 80.0;
    tOnDelay : TIME; (* value must stay past fOnPoint this long *)
    tOffDelay : TIME; (* value must stay past fOffPoint this long *)
    tMinOn : TIME; (* shortest time on *)
    tMinOff : TIME; (* shortest time off before coming on again *)
  END_VAR
  VAR_OUTPUT
    bQ : BOOL;
    bBadInput : BOOL; (* fIn or a point is NaN or infinite: bQ is held *)
    bBadOrder : BOOL; (* the points are the wrong way round for eDir (or eDir is not a direction): bQ off *)
    tRemaining : TIME; (* time left before bQ changes (delay, tMinOn / tMinOff) *)
    bWaiting : BOOL; (* past the point, delay over, but tMinOn / tMinOff holds bQ *)
  END_VAR
  VAR
    tNow : TIME;
    bWantOn : BOOL; (* past the on point now *)
    bWantOff : BOOL; (* past the off point now *)
    tOnSince : TIME;
    tOffSince : TIME;
    bWantOnPrev : BOOL;
    bWantOffPrev : BOOL;
    tSwitchedAt : TIME; (* when bQ last changed *)
    bBeenOff : BOOL; (* bQ has switched off at least once (tMinOff applies) *)
    dLeft : TIME; (* delay still to run *)
    tMLeft : TIME; (* tMinOn / tMinOff still to run *)
    bBelow : BOOL; (* on below fOnPoint (fill / heat) *)
    bEn : BOOL;
  END_VAR


tNow := TIME();
bBadInput := NOT (fIn = fIn) OR fIn > 3.4E38 OR fIn < -3.4E38
            OR NOT (fOnPoint = fOnPoint) OR fOnPoint > 3.4E38 OR fOnPoint < -3.4E38
            OR NOT (fOffPoint = fOffPoint) OR fOffPoint > 3.4E38 OR fOffPoint < -3.4E38;
bBadOrder := FALSE;
CASE eDir OF
  E_TwoPointDir.ByOrder:
    bBelow := NOT (fOnPoint > fOffPoint);
  E_TwoPointDir.OnBelow:
    bBelow := TRUE;
    bBadOrder := NOT bBadInput AND fOnPoint > fOffPoint;
  E_TwoPointDir.OnAbove:
    bBelow := FALSE;
    bBadOrder := NOT bBadInput AND fOnPoint < fOffPoint;
ELSE
  bBelow := TRUE;
  bBadOrder := TRUE;
END_CASE;
bEn := bEnable AND NOT bBadOrder;
IF bBadInput OR bBadOrder THEN
  bWantOn := FALSE;
  bWantOff := FALSE;
ELSIF bBelow THEN
  bWantOn := fIn < fOnPoint;        (* fill / heat, and equal points *)
  bWantOff := fIn > fOffPoint;
ELSE
  bWantOn := fIn > fOnPoint;        (* empty / cool *)
  bWantOff := fIn < fOffPoint;
END_IF;

IF bWantOn AND NOT bWantOnPrev THEN
  tOnSince := tNow;
END_IF;
bWantOnPrev := bWantOn;
IF bWantOff AND NOT bWantOffPrev THEN
  tOffSince := tNow;
END_IF;
bWantOffPrev := bWantOff;

IF NOT bEn THEN
  IF bQ THEN
    bQ := FALSE;
    tSwitchedAt := tNow;
    bBeenOff := TRUE;
  END_IF;
ELSIF bQ THEN
  IF bWantOff AND tNow - tOffSince >= tOffDelay AND tNow - tSwitchedAt >= tMinOn THEN
    bQ := FALSE;
    tSwitchedAt := tNow;
    bBeenOff := TRUE;
  END_IF;
ELSE
  IF bWantOn AND tNow - tOnSince >= tOnDelay AND (NOT bBeenOff OR tNow - tSwitchedAt >= tMinOff) THEN
    bQ := TRUE;
    tSwitchedAt := tNow;
  END_IF;
END_IF;

(* what still holds bQ as it is *)
dLeft := T#0s;
tMLeft := T#0s;
IF bEn AND bQ AND bWantOff THEN
  dLeft := tOffDelay - (tNow - tOffSince);
  tMLeft := tMinOn - (tNow - tSwitchedAt);
ELSIF bEn AND NOT bQ AND bWantOn THEN
  dLeft := tOnDelay - (tNow - tOnSince);
  IF bBeenOff THEN
    tMLeft := tMinOff - (tNow - tSwitchedAt);
  END_IF;
END_IF;
IF dLeft < T#0s THEN
  dLeft := T#0s;
END_IF;
IF tMLeft < T#0s THEN
  tMLeft := T#0s;
END_IF;
bWaiting := dLeft = T#0s AND tMLeft > T#0s;
IF tMLeft > dLeft THEN
  tRemaining := tMLeft;
ELSE
  tRemaining := dLeft;
END_IF;

END_FUNCTION_BLOCK