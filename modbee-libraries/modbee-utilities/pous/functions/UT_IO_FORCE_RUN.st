(* UT_IO_FORCE_RUN — the engine of one force slot, shared by UT_IO_MAP_IN and
UT_IO_MAP_OUT. Not for your programs: the IO maps call it.

Returns TRUE while the slot forces its channel. cmdForce starts the force
(or starts its time again), cmdRelease, Release or the end of the time
stops it. A force is refused while Where is not OK (no such channel) or,
for outputs, while Permit is FALSE; losing either ends a running force.
Commands act on their rising edge and are cleared after acting, so a
command held on (a Modbus coil, a debugger force) acts only once. The maps
give Release on their first scan, so every force ends at power-up. *)

FUNCTION UT_IO_FORCE_RUN : BOOL
  VAR_IN_OUT
    S : UT_IO_FORCE; (* the slot *)
  END_VAR
  VAR_INPUT
    Where : UT_IO_Q; (* OK, or why the address is wrong (NO_MODULE, NO_CHANNEL) *)
    Permit : BOOL; (* forcing allowed now (outputs: system Off) *)
    Release : BOOL; (* TRUE: release now and refuse new forces *)
    Now : TIME; (* the scan's time *)
    ForceTime : TIME; (* how long a force lasts (already limited by the caller) *)
  END_VAR
  VAR
    doForce : BOOL;
    doRelease : BOOL;
    left : TIME;
  END_VAR


doForce := S.cmdForce AND NOT S.forceSeen;
S.forceSeen := S.cmdForce;
S.cmdForce := FALSE;
doRelease := S.cmdRelease AND NOT S.releaseSeen;
S.releaseSeen := S.cmdRelease;
S.cmdRelease := FALSE;

IF doRelease OR Release THEN
  S.active := FALSE;
  S.state := UT_IOQ_UNUSED;
ELSIF doForce THEN
  IF Where <> UT_IOQ_OK THEN
    S.active := FALSE;
    S.state := Where;
  ELSIF NOT Permit THEN
    S.active := FALSE;
    S.state := UT_IOQ_NOT_PERMITTED;
  ELSE
    S.active := TRUE;
    S.endAt := Now + ForceTime;
  END_IF;
ELSIF S.active THEN
  IF Where <> UT_IOQ_OK THEN
    S.active := FALSE;               (* the address was changed to a wrong one *)
    S.state := Where;
  ELSIF NOT Permit THEN
    S.active := FALSE;
    S.state := UT_IOQ_NOT_PERMITTED;
  ELSIF S.endAt - Now > ForceTime THEN
    S.endAt := Now + ForceTime;      (* the force time was shortened *)
  END_IF;
END_IF;
IF S.active THEN
  left := S.endAt - Now;
  IF left <= T#0s THEN
    S.active := FALSE;
    S.state := UT_IOQ_UNUSED;
  END_IF;
END_IF;
IF S.active THEN
  S.state := UT_IOQ_FORCED;
  S.leftS := DINT_TO_UINT((TIME_TO_DINT(left) + 999) / 1000);
ELSE
  S.leftS := 0;
END_IF;
UT_IO_FORCE_RUN := S.active;

END_FUNCTION