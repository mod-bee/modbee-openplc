(* FB_Toggle — push-on / push-off. Each press (rising edge of bIn) flips bQ. bReset forces bQ off and wins; bForceOn
forces it on; both act while held. bQ starts off (not kept). A button held at the first scan counts as a press
only with bEdgeAtStart. *)

FUNCTION_BLOCK FB_Toggle
  VAR_INPUT
    bIn : BOOL R_EDGE;
    bReset : BOOL;
    bForceOn : BOOL;
    bEdgeAtStart : BOOL;
  END_VAR
  VAR_OUTPUT
    bQ : BOOL;
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
ELSIF bIn AND (NOT bFirstScan OR bEdgeAtStart) THEN
  bState := NOT bState;
END_IF;
bQ := bState;

END_FUNCTION_BLOCK