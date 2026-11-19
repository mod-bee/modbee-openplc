(* FB_Tonr — retentive (accumulating) on-delay timer. Like a TON, but the elapsed time is kept when bIn goes off
and timing carries on from there the next time bIn is on. bQ once bIn has been on for tPresetTime in total. bReset clears
the time (wins while held). As Siemens TONR / Rockwell RTO, the time lives only while powered (nothing retained).
tElapsedTime stops at tPresetTime; tPresetTime lowered below the time gathered: bQ at once; tPresetTime <= 0: bQ as soon as bIn is on. Each scan
interval counts if bIn was on at its start. *)

FUNCTION_BLOCK FB_Tonr
  VAR_INPUT
    bIn : BOOL; (* gathers time while TRUE *)
    tPresetTime : TIME := T#10s; (* preset *)
    bReset : BOOL; (* clears tElapsedTime (wins) *)
  END_VAR
  VAR_OUTPUT
    bQ : BOOL; (* tElapsedTime has reached tPresetTime *)
    tElapsedTime : TIME; (* time gathered (stops at tPresetTime) *)
    tTimeLeft : TIME; (* time remaining *)
    bTiming : BOOL; (* gathering time now *)
  END_VAR
  VAR
    tPrev : TIME;
    bWasOn : BOOL;
    tAcc : TIME;
    bStarted : BOOL;
  END_VAR
  VAR_TEMP
    tCur : TIME;
    tPreset : TIME;
  END_VAR


tCur := TIME();
tPreset := tPresetTime;
IF tPreset < T#0s THEN
  tPreset := T#0s;
END_IF;
IF bReset THEN
  tAcc := T#0s;
  bStarted := FALSE;
  bWasOn := FALSE;
ELSE
  IF bWasOn AND tAcc < tPreset THEN
    tAcc := tAcc + (tCur - tPrev);
    IF tAcc > tPreset THEN
      tAcc := tPreset;
    END_IF;
  END_IF;
  IF bIn THEN
    bStarted := TRUE;
  END_IF;
  bWasOn := bIn;
END_IF;
tPrev := tCur;
bQ := bStarted AND tAcc >= tPreset;
IF tAcc < tPreset THEN
  tElapsedTime := tAcc;
ELSE
  tElapsedTime := tPreset;
END_IF;
tTimeLeft := tPreset - tElapsedTime;
bTiming := bIn AND NOT bReset AND NOT bQ;

END_FUNCTION_BLOCK