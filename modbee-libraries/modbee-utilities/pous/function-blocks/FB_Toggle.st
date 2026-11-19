(* FB_Toggle — push-on / push-off. Each press (rising edge of bIn) flips bQ. bReset forces bQ off and wins; bForceOn
forces it on; both act while held. bQ starts off (not kept). A button held at the first scan counts as a press
only with bPressAtFirstScan. *)

FUNCTION_BLOCK FB_Toggle
  VAR_INPUT
    bIn : BOOL R_EDGE; (* rising edge: flip bQ *)
    bReset : BOOL; (* held: bQ off (wins) *)
    bForceOn : BOOL; (* held: bQ on *)
    bPressAtFirstScan : BOOL; (* a button held at the first scan counts as a press *)
  END_VAR
  VAR_OUTPUT
    bQ : BOOL; (* the output *)
  END_VAR
  VAR
    bState : BOOL;
    bStarted : BOOL;
  END_VAR
  VAR_TEMP
    bFirstScan : BOOL;
  END_VAR


bFirstScan := NOT bStarted;
bStarted := TRUE;
IF bReset THEN
  bState := FALSE;
ELSIF bForceOn THEN
  bState := TRUE;
ELSIF bIn AND (NOT bFirstScan OR bPressAtFirstScan) THEN
  bState := NOT bState;
END_IF;
bQ := bState;

END_FUNCTION_BLOCK