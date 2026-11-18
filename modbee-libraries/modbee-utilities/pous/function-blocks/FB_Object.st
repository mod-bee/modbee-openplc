(* FB_Object — the base of every block: the error outputs and the system link.
bError: a trip is active now. bWarning: a warning is active now. eErrorId: the first error since the last
reset (first-out), else the first warning; None when nothing is active. eState: what the block is doing.
Kept settings (every block that keeps a last-good copy): a bad write is put back and shown by bRefused and
eRefusedWhy, the kind of the first bad setting: TimeBad (a time), ProtectionBad (a protection's settings),
ChoiceBad (a choice the block does not have), LimitsBad (two settings in the wrong order), BelowMin / AboveMax (a
number below / above its range), ValueBad (a number that is not valid), IoAddress (an IO address). Both clear
with the block's reset (its record's bCmdReset, the equipment's reset, or the plant reset). *)

FUNCTION_BLOCK ABSTRACT FB_Object IMPLEMENTS I_PartOwner
  VAR_INPUT
    ipSystem : I_SystemMode; (* the system mode block; unwired: no system Auto / power-up hold / reset *)
  END_VAR
  VAR_OUTPUT
    bError : BOOL;
    bWarning : BOOL;
    eErrorId : E_UtError;
    eState : E_State;
  END_VAR
  VAR
    tNow : TIME; (* TIME() of this scan *)
    bFirstScan : BOOL := TRUE; (* the first scan after a power-up or a download *)
    ipFirstPart : I_Part; (* the parts added to this block (a linked list) *)
    bPartTrip : BOOL; (* the parts' results of the last EvaluateParts *)
    bPartWarn : BOOL;
    bPartStop : BOOL;
    bPartHold : BOOL;
    bPartMask : BOOL;
    bPartDone : BOOL;
    bPartRun : BOOL;
    bPartCap : BOOL; (* a part's safety time cap is reached *)
    bPartHoldOff : BOOL; (* a part tripped on a cause that holds a motor's coil off (Thermistor) *)
    bPartRequest : BOOL; (* a part asks for a normal run (not urgent) *)
    ePartTrip : E_UtError;
    ePartWarn : E_UtError;
  END_VAR


(* A part adds itself on its first call (I_PartOwner). *)
METHOD PUBLIC FINAL AddPart
  VAR_INPUT
    ipPart : I_Part;
  END_VAR
  IF ipPart <> NULL THEN
    ipPart.SetNext(ipNext := ipFirstPart);
    ipFirstPart := ipPart;
  END_IF;
END_METHOD

(* The owner calls its parts in its own cycle; the results are in bPartTrip ... ePartWarn. *)
METHOD PROTECTED FINAL EvaluateParts
  VAR_INPUT
    bRunning : BOOL;
    bResetWanted : BOOL;
    bMasked : BOOL;
  END_VAR
  VAR
    ipCur : I_Part;
    nI : INT;
    eAct : E_PartAction;
    ePart : E_UtError;
  END_VAR
  bPartTrip := FALSE;
  bPartWarn := FALSE;
  bPartStop := FALSE;
  bPartHold := FALSE;
  bPartMask := FALSE;
  bPartDone := FALSE;
  bPartRun := FALSE;
  bPartRequest := FALSE;
  bPartCap := FALSE;
  bPartHoldOff := FALSE;
  ePartTrip := E_UtError.None;
  ePartWarn := E_UtError.None;
  ipCur := ipFirstPart;
  FOR nI := 1 TO 32 DO
    IF ipCur = NULL THEN
      EXIT;
    END_IF;
    eAct := ipCur.Evaluate(bRunning := bRunning, bResetWanted := bResetWanted, bMasked := bMasked, eErrorId => ePart);
    CASE eAct OF
      E_PartAction.Trip:
        IF NOT bPartTrip THEN ePartTrip := ePart; END_IF;
        bPartTrip := TRUE;
        IF ePart = E_UtError.Thermistor THEN bPartHoldOff := TRUE; END_IF;
      E_PartAction.Stop:
        bPartStop := TRUE;
      E_PartAction.HoldStart:
        bPartHold := TRUE;
      E_PartAction.Mask:
        bPartMask := TRUE;
      E_PartAction.Done:
        bPartDone := TRUE;
      E_PartAction.Run:
        bPartRun := TRUE;
      E_PartAction.Request:
        bPartRequest := TRUE;
      E_PartAction.Cap:
        bPartCap := TRUE;
      E_PartAction.Warn:
        IF NOT bPartWarn THEN ePartWarn := ePart; END_IF;
        bPartWarn := TRUE;
    ELSE
      ;
    END_CASE;
    ipCur := ipCur.GetNext();
  END_FOR;
END_METHOD

(* The system's reset request (FALSE when no system block is wired). *)
METHOD PROTECTED SystemReset : BOOL
  IF ipSystem <> NULL THEN
    SystemReset := ipSystem.bSystemReset;
  ELSE
    SystemReset := FALSE;
  END_IF;
END_METHOD

(* The system's power-on hold: automatic starts wait. *)
METHOD PROTECTED SystemHold : BOOL
  IF ipSystem <> NULL THEN
    SystemHold := ipSystem.bSystemHold;
  ELSE
    SystemHold := FALSE;
  END_IF;
END_METHOD

END_FUNCTION_BLOCK