(* F_IoForceSlot — one commissioning force slot (src-v2 UT_IO_FORCE_RUN): bCmdForce starts it (or starts its time
again), bCmdRelease or bRelease ends it, it ends by itself after tForceTime, a wrong address (eWhere not Ok) or
no permit refuses / ends it. A command held on acts once. Returns TRUE while it forces. *)

FUNCTION F_IoForceSlot : BOOL
  VAR_IN_OUT
    stS : ST_IoForce;
  END_VAR
  VAR_INPUT
    eWhere : E_IoQ; (* Ok, or why the address is wrong (NoModule, NoChannel) *)
    bPermit : BOOL; (* forcing allowed now (outputs: system Off) *)
    bRelease : BOOL; (* release now and refuse new forces *)
    tNow : TIME;
    tForceTime : TIME; (* how long a force lasts (already limited by the caller) *)
  END_VAR
  VAR
    bDoForce : BOOL;
    bDoRelease : BOOL;
    tLeft : TIME;
  END_VAR


bDoForce := stS.bCmdForce AND NOT stS.bForceSeen;
stS.bForceSeen := stS.bCmdForce;
stS.bCmdForce := FALSE;
bDoRelease := stS.bCmdRelease AND NOT stS.bReleaseSeen;
stS.bReleaseSeen := stS.bCmdRelease;
stS.bCmdRelease := FALSE;
IF bDoRelease OR bRelease THEN
  stS.bActive := FALSE;
  stS.eState := E_IoQ.Unused;
ELSIF bDoForce THEN
  IF eWhere <> E_IoQ.Ok THEN
    stS.bActive := FALSE;
    stS.eState := eWhere;
  ELSIF NOT bPermit THEN
    stS.bActive := FALSE;
    stS.eState := E_IoQ.NotPermitted;
  ELSE
    stS.bActive := TRUE;
    stS.tEndAt := tNow + tForceTime;
  END_IF;
ELSIF stS.bActive THEN
  IF eWhere <> E_IoQ.Ok THEN
    stS.bActive := FALSE;         // the address was changed to a wrong one
    stS.eState := eWhere;
  ELSIF NOT bPermit THEN
    stS.bActive := FALSE;
    stS.eState := E_IoQ.NotPermitted;
  ELSIF stS.tEndAt - tNow > tForceTime THEN
    stS.tEndAt := tNow + tForceTime;   // the force time was shortened
  END_IF;
END_IF;
tLeft := T#0s;
IF stS.bActive THEN
  tLeft := stS.tEndAt - tNow;
  IF tLeft <= T#0s THEN
    stS.bActive := FALSE;
    stS.eState := E_IoQ.Unused;
    tLeft := T#0s;
  END_IF;
END_IF;
IF stS.bActive THEN
  stS.eState := E_IoQ.Forced;
END_IF;
stS.tTimeLeft := tLeft;
F_IoForceSlot := stS.bActive;

END_FUNCTION