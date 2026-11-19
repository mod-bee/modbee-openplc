(* F_IoForceSlot — one commissioning force slot: bCmdForceNow starts it (or starts its time again), bCmdReleaseNow or
bReleaseAllForces ends it, it ends by itself after tForceTime, a wrong address (eAddressQuality not Ok) or
no permit refuses / ends it. A command held on acts once. Returns TRUE while it forces. *)

FUNCTION F_IoForceSlot : BOOL
  VAR_IN_OUT
    stForceSlot : ST_IoForce; (* the force slot *)
  END_VAR
  VAR_INPUT
    eAddressQuality : E_IoQ; (* Ok, or why the address is wrong (NoModule, NoChannel) *)
    bForcingAllowed : BOOL; (* forcing allowed now (outputs: system Off) *)
    bReleaseAllForces : BOOL; (* release now and refuse new forces *)
    tNow : TIME; (* TIME() of this scan *)
    tForceTime : TIME; (* how long a force lasts (already limited by the caller) *)
  END_VAR
  VAR
    bDoForce : BOOL;
    bDoRelease : BOOL;
    tLeft : TIME;
  END_VAR


bDoForce := stForceSlot.bCmdForceNow AND NOT stForceSlot.bForceCommandTaken;
stForceSlot.bForceCommandTaken := stForceSlot.bCmdForceNow;
stForceSlot.bCmdForceNow := FALSE;
bDoRelease := stForceSlot.bCmdReleaseNow AND NOT stForceSlot.bReleaseCommandTaken;
stForceSlot.bReleaseCommandTaken := stForceSlot.bCmdReleaseNow;
stForceSlot.bCmdReleaseNow := FALSE;
IF bDoRelease OR bReleaseAllForces THEN
  stForceSlot.bForcing := FALSE;
  stForceSlot.eForceState := E_IoQ.Unused;
ELSIF bDoForce THEN
  IF eAddressQuality <> E_IoQ.Ok THEN
    stForceSlot.bForcing := FALSE;
    stForceSlot.eForceState := eAddressQuality;
  ELSIF NOT bForcingAllowed THEN
    stForceSlot.bForcing := FALSE;
    stForceSlot.eForceState := E_IoQ.NotPermitted;
  ELSE
    stForceSlot.bForcing := TRUE;
    stForceSlot.tReleasesAt := tNow + tForceTime;
  END_IF;
ELSIF stForceSlot.bForcing THEN
  IF eAddressQuality <> E_IoQ.Ok THEN
    stForceSlot.bForcing := FALSE;         // the address was changed to a wrong one
    stForceSlot.eForceState := eAddressQuality;
  ELSIF NOT bForcingAllowed THEN
    stForceSlot.bForcing := FALSE;
    stForceSlot.eForceState := E_IoQ.NotPermitted;
  ELSIF stForceSlot.tReleasesAt - tNow > tForceTime THEN
    stForceSlot.tReleasesAt := tNow + tForceTime;   // the force time was shortened
  END_IF;
END_IF;
tLeft := T#0s;
IF stForceSlot.bForcing THEN
  tLeft := stForceSlot.tReleasesAt - tNow;
  IF tLeft <= T#0s THEN
    stForceSlot.bForcing := FALSE;
    stForceSlot.eForceState := E_IoQ.Unused;
    tLeft := T#0s;
  END_IF;
END_IF;
IF stForceSlot.bForcing THEN
  stForceSlot.eForceState := E_IoQ.Forced;
END_IF;
stForceSlot.tTimeLeft := tLeft;
F_IoForceSlot := stForceSlot.bForcing;

END_FUNCTION