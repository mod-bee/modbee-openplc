(* FB_Debounce — on / off delay filter. bQ switches on once bIn has been TRUE for tOnDelay without a break, and off
once it has been FALSE for tOffDelay. Anything shorter is ignored. bRising / bFalling: one scan when bQ switches.
A delay of 0 (or less) passes bIn straight through. While bIn differs from bQ, tET is how long bIn has held its new
state and tRemaining the delay still to run; else both 0. *)

FUNCTION_BLOCK FB_Debounce
  VAR_INPUT
    bIn : BOOL;
    tOnDelay : TIME := T#100ms;
    tOffDelay : TIME := T#100ms;
  END_VAR
  VAR_OUTPUT
    bQ : BOOL;
    bRising : BOOL;
    bFalling : BOOL;
    tET : TIME;
    tRemaining : TIME;
  END_VAR
  VAR
    bInPrev : BOOL;
    tSince : TIME;
  END_VAR
  VAR_TEMP
    tCur : TIME;
    tDly : TIME;
  END_VAR


tCur := TIME();
bRising := FALSE;
bFalling := FALSE;
IF bIn <> bInPrev THEN
  tSince := tCur;
END_IF;
bInPrev := bIn;
IF bIn AND NOT bQ THEN
  IF tCur - tSince >= tOnDelay THEN
    bQ := TRUE;
    bRising := TRUE;
  END_IF;
ELSIF NOT bIn AND bQ THEN
  IF tCur - tSince >= tOffDelay THEN
    bQ := FALSE;
    bFalling := TRUE;
  END_IF;
END_IF;
IF bIn <> bQ THEN
  IF bIn THEN tDly := tOnDelay; ELSE tDly := tOffDelay; END_IF;
  IF tDly < T#0s THEN tDly := T#0s; END_IF;
  tET := tCur - tSince;
  IF tET > tDly THEN tET := tDly; END_IF;
  tRemaining := tDly - tET;
ELSE
  tET := T#0s;
  tRemaining := T#0s;
END_IF;

END_FUNCTION_BLOCK