(* FB_Debounce — on / off delay filter. bQ switches on once bIn has been TRUE for tOnDelay without a break, and off
once it has been FALSE for tOffDelay. Anything shorter is ignored. bRising / bFalling: one scan when bQ switches.
A delay of 0 (or less) passes bIn straight through. While bIn differs from bQ, tElapsedTime is how long bIn has held its new
state and tTimeLeft the delay still to run; else both 0. *)

FUNCTION_BLOCK FB_Debounce
  VAR_INPUT
    bIn : BOOL; (* the raw signal *)
    tOnDelay : TIME := T#100ms; (* bIn must be TRUE this long to switch bQ on *)
    tOffDelay : TIME := T#100ms; (* bIn must be FALSE this long to switch bQ off *)
  END_VAR
  VAR_OUTPUT
    bQ : BOOL; (* the debounced output *)
    bRising : BOOL; (* one scan when bQ comes on *)
    bFalling : BOOL; (* one scan when bQ goes off *)
    tElapsedTime : TIME; (* how long bIn has held its new state *)
    tTimeLeft : TIME; (* the delay still to run *)
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
  tElapsedTime := tCur - tSince;
  IF tElapsedTime > tDly THEN tElapsedTime := tDly; END_IF;
  tTimeLeft := tDly - tElapsedTime;
ELSE
  tElapsedTime := T#0s;
  tTimeLeft := T#0s;
END_IF;

END_FUNCTION_BLOCK