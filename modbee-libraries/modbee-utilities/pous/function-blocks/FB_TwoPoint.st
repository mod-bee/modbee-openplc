(* FB_TwoPoint — on/off (hysteresis) controller, thermostat style.

The setpoint order decides the direction, so there is no mode to set:
  fOnPoint < fOffPoint   fill / heat:   on below fOnPoint, off above fOffPoint
  fOnPoint > fOffPoint   empty / cool:  on above fOnPoint, off below fOffPoint
  fOnPoint = fOffPoint   a plain comparator with no hysteresis, in the
                       fill / heat direction (on below, off above)
A value exactly on a point is not past it, so nothing changes there.

tOnDelay / tOffDelay: the value must stay past the point this long.
tMinOnTime / tMinOffTime: anti-short-cycle. bOutputOn stays on at least tMinOnTime, and stays off
at least tMinOffTime before it may come on again. tMinOffTime is not applied at
start-up. The points are re-evaluated every scan, so changing or swapping
them while running takes effect cleanly (through the delays).

bEnable FALSE turns bOutputOn off at once, even inside tMinOnTime; tMinOffTime then counts from
that moment.

A value that is not a number (fIn or a point NaN or infinite) holds bOutputOn as it
is and sets bInputNotANumber; the delays start again once it is good.

tTimeLeft is the time left before bOutputOn changes: the delay and the tMinOnTime /
tMinOffTime still to run while the value is past the point that changes it
(T#0s otherwise). bHeldByMinTime is TRUE while the value is past that point and
its delay is over, but tMinOnTime / tMinOffTime still holds bOutputOn as it is. *)

FUNCTION_BLOCK FB_TwoPoint
  VAR_INPUT
    fIn : REAL; (* measured value *)
    bEnable : BOOL := TRUE; (* FALSE = output off *)
    eDirection : E_TwoPointDir; (* ByOrder (the points decide), OnBelow (fill / heat), OnAbove (empty / cool) *)
    fOnPoint : REAL := 20.0; (* the value at which bOutputOn comes on *)
    fOffPoint : REAL := 80.0; (* the value at which bOutputOn goes off *)
    tOnDelay : TIME; (* value must stay past fOnPoint this long *)
    tOffDelay : TIME; (* value must stay past fOffPoint this long *)
    tMinOnTime : TIME; (* shortest time on *)
    tMinOffTime : TIME; (* shortest time off before coming on again *)
  END_VAR
  VAR_OUTPUT
    bOutputOn : BOOL; (* the output *)
    bInputNotANumber : BOOL; (* fIn or a point is NaN or infinite: bOutputOn is held *)
    bPointsWrongWay : BOOL; (* the points are the wrong way round for eDirection (or eDirection is not a direction): bOutputOn off *)
    tTimeLeft : TIME; (* time left before bOutputOn changes (delay, tMinOnTime / tMinOffTime) *)
    bHeldByMinTime : BOOL; (* past the point, delay over, but tMinOnTime / tMinOffTime holds bOutputOn *)
  END_VAR
  VAR
    tNow : TIME;
    bWantOn : BOOL; (* past the on point now *)
    bWantOff : BOOL; (* past the off point now *)
    tOnSince : TIME;
    tOffSince : TIME;
    bWantOnPrev : BOOL;
    bWantOffPrev : BOOL;
    tSwitchedAt : TIME; (* when bOutputOn last changed *)
    bBeenOff : BOOL; (* bOutputOn has switched off at least once (tMinOffTime applies) *)
    dLeft : TIME; (* delay still to run *)
    tMLeft : TIME; (* tMinOnTime / tMinOffTime still to run *)
    bBelow : BOOL; (* on below fOnPoint (fill / heat) *)
    bEn : BOOL;
  END_VAR


tNow := TIME();
bInputNotANumber := NOT (fIn = fIn) OR fIn > 3.4E38 OR fIn < -3.4E38
            OR NOT (fOnPoint = fOnPoint) OR fOnPoint > 3.4E38 OR fOnPoint < -3.4E38
            OR NOT (fOffPoint = fOffPoint) OR fOffPoint > 3.4E38 OR fOffPoint < -3.4E38;
bPointsWrongWay := FALSE;
CASE eDirection OF
  E_TwoPointDir.ByOrder:
    bBelow := NOT (fOnPoint > fOffPoint);
  E_TwoPointDir.OnBelow:
    bBelow := TRUE;
    bPointsWrongWay := NOT bInputNotANumber AND fOnPoint > fOffPoint;
  E_TwoPointDir.OnAbove:
    bBelow := FALSE;
    bPointsWrongWay := NOT bInputNotANumber AND fOnPoint < fOffPoint;
ELSE
  bBelow := TRUE;
  bPointsWrongWay := TRUE;
END_CASE;
bEn := bEnable AND NOT bPointsWrongWay;
IF bInputNotANumber OR bPointsWrongWay THEN
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
  IF bOutputOn THEN
    bOutputOn := FALSE;
    tSwitchedAt := tNow;
    bBeenOff := TRUE;
  END_IF;
ELSIF bOutputOn THEN
  IF bWantOff AND tNow - tOffSince >= tOffDelay AND tNow - tSwitchedAt >= tMinOnTime THEN
    bOutputOn := FALSE;
    tSwitchedAt := tNow;
    bBeenOff := TRUE;
  END_IF;
ELSE
  IF bWantOn AND tNow - tOnSince >= tOnDelay AND (NOT bBeenOff OR tNow - tSwitchedAt >= tMinOffTime) THEN
    bOutputOn := TRUE;
    tSwitchedAt := tNow;
  END_IF;
END_IF;

(* what still holds bOutputOn as it is *)
dLeft := T#0s;
tMLeft := T#0s;
IF bEn AND bOutputOn AND bWantOff THEN
  dLeft := tOffDelay - (tNow - tOffSince);
  tMLeft := tMinOnTime - (tNow - tSwitchedAt);
ELSIF bEn AND NOT bOutputOn AND bWantOn THEN
  dLeft := tOnDelay - (tNow - tOnSince);
  IF bBeenOff THEN
    tMLeft := tMinOffTime - (tNow - tSwitchedAt);
  END_IF;
END_IF;
IF dLeft < T#0s THEN
  dLeft := T#0s;
END_IF;
IF tMLeft < T#0s THEN
  tMLeft := T#0s;
END_IF;
bHeldByMinTime := dLeft = T#0s AND tMLeft > T#0s;
IF tMLeft > dLeft THEN
  tTimeLeft := tMLeft;
ELSE
  tTimeLeft := dLeft;
END_IF;

END_FUNCTION_BLOCK