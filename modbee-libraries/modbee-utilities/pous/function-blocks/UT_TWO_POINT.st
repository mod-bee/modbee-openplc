(* UT_TWO_POINT — on/off (hysteresis) controller, thermostat style.

The setpoint order decides the direction, so there is no mode to set:
  OnPoint < OffPoint   fill / heat:   on below OnPoint, off above OffPoint
  OnPoint > OffPoint   empty / cool:  on above OnPoint, off below OffPoint
  OnPoint = OffPoint   a plain comparator with no hysteresis, in the
                       fill / heat direction (on below, off above)
A value exactly on a point is not past it, so nothing changes there.

OnDelay / OffDelay: the value must stay past the point this long.
MinOn / MinOff: anti-short-cycle. Q stays on at least MinOn, and stays off
at least MinOff before it may come on again. MinOff is not applied at
start-up. The points are re-evaluated every scan, so changing or swapping
them while running takes effect cleanly (through the delays).

Enable FALSE turns Q off at once, even inside MinOn; MinOff then counts from
that moment.

A value that is not a number (In or a point NaN or infinite) holds Q as it
is and sets BadInput; the delays start again once it is good.

Remaining is the time left before Q changes: the delay and the MinOn /
MinOff still to run while the value is past the point that changes it
(T#0s otherwise). Waiting is TRUE while the value is past that point and
its delay is over, but MinOn / MinOff still holds Q as it is. *)

FUNCTION_BLOCK UT_TWO_POINT
  VAR_INPUT
    In : REAL; (* measured value *)
    Enable : BOOL := TRUE; (* FALSE = output off *)
    Dir : UT_TP_DIR; (* BY_ORDER (the points decide), ON_BELOW (fill / heat), ON_ABOVE (empty / cool) *)
    OnPoint : REAL := 20.0;
    OffPoint : REAL := 80.0;
    OnDelay : TIME; (* value must stay past OnPoint this long *)
    OffDelay : TIME; (* value must stay past OffPoint this long *)
    MinOn : TIME; (* shortest time on *)
    MinOff : TIME; (* shortest time off before coming on again *)
  END_VAR
  VAR_OUTPUT
    Q : BOOL;
    BadInput : BOOL; (* In or a point is NaN or infinite: Q is held *)
    BadOrder : BOOL; (* the points are the wrong way round for Dir (or Dir is not a direction): Q off *)
    Remaining : TIME; (* time left before Q changes (delay, MinOn / MinOff) *)
    Waiting : BOOL; (* past the point, delay over, but MinOn / MinOff holds Q *)
  END_VAR
  VAR
    tNow : TIME;
    wantOn : BOOL; (* past the on point now *)
    wantOff : BOOL; (* past the off point now *)
    onSince : TIME;
    offSince : TIME;
    wantOnPrev : BOOL;
    wantOffPrev : BOOL;
    switchedAt : TIME; (* when Q last changed *)
    beenOff : BOOL; (* Q has switched off at least once (MinOff applies) *)
    dLeft : TIME; (* delay still to run *)
    mLeft : TIME; (* MinOn / MinOff still to run *)
    below : BOOL; (* on below OnPoint (fill / heat) *)
    en : BOOL;
  END_VAR


tNow := TIME();
BadInput := NOT (In = In) OR In > 3.4E38 OR In < -3.4E38
            OR NOT (OnPoint = OnPoint) OR OnPoint > 3.4E38 OR OnPoint < -3.4E38
            OR NOT (OffPoint = OffPoint) OR OffPoint > 3.4E38 OR OffPoint < -3.4E38;
BadOrder := FALSE;
CASE Dir OF
  UT_TP_BY_ORDER:
    below := NOT (OnPoint > OffPoint);
  UT_TP_ON_BELOW:
    below := TRUE;
    BadOrder := NOT BadInput AND OnPoint > OffPoint;
  UT_TP_ON_ABOVE:
    below := FALSE;
    BadOrder := NOT BadInput AND OnPoint < OffPoint;
ELSE
  below := TRUE;
  BadOrder := TRUE;
END_CASE;
en := Enable AND NOT BadOrder;
IF BadInput OR BadOrder THEN
  wantOn := FALSE;
  wantOff := FALSE;
ELSIF below THEN
  wantOn := In < OnPoint;        (* fill / heat, and equal points *)
  wantOff := In > OffPoint;
ELSE
  wantOn := In > OnPoint;        (* empty / cool *)
  wantOff := In < OffPoint;
END_IF;

IF wantOn AND NOT wantOnPrev THEN
  onSince := tNow;
END_IF;
wantOnPrev := wantOn;
IF wantOff AND NOT wantOffPrev THEN
  offSince := tNow;
END_IF;
wantOffPrev := wantOff;

IF NOT en THEN
  IF Q THEN
    Q := FALSE;
    switchedAt := tNow;
    beenOff := TRUE;
  END_IF;
ELSIF Q THEN
  IF wantOff AND tNow - offSince >= OffDelay AND tNow - switchedAt >= MinOn THEN
    Q := FALSE;
    switchedAt := tNow;
    beenOff := TRUE;
  END_IF;
ELSE
  IF wantOn AND tNow - onSince >= OnDelay AND (NOT beenOff OR tNow - switchedAt >= MinOff) THEN
    Q := TRUE;
    switchedAt := tNow;
  END_IF;
END_IF;

(* what still holds Q as it is *)
dLeft := T#0s;
mLeft := T#0s;
IF en AND Q AND wantOff THEN
  dLeft := OffDelay - (tNow - offSince);
  mLeft := MinOn - (tNow - switchedAt);
ELSIF en AND NOT Q AND wantOn THEN
  dLeft := OnDelay - (tNow - onSince);
  IF beenOff THEN
    mLeft := MinOff - (tNow - switchedAt);
  END_IF;
END_IF;
IF dLeft < T#0s THEN
  dLeft := T#0s;
END_IF;
IF mLeft < T#0s THEN
  mLeft := T#0s;
END_IF;
Waiting := dLeft = T#0s AND mLeft > T#0s;
IF mLeft > dLeft THEN
  Remaining := mLeft;
ELSE
  Remaining := dLeft;
END_IF;

END_FUNCTION_BLOCK