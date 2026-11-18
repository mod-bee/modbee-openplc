(* F_Protect — the protection engine every block is built from.
A FUNCTION: no instance; the VAR_IN_OUTs are references to the owner's settings, status and private state.

- a condition acts after its delay; Off ignores it; Signal follows it with no alarm (no latch, count, retry,
warning or trip) and lets go once the cause has been gone tRecover (a restart delay: a source refills before
its pump starts again; 0 = at once);
- Auto clears once the cause has been gone tRecover; Retry does the same but locks out after nMaxRetries
trips in the window; Manual needs a reset;
- the recover wait counts from the raw cause gone; a cause back inside the wait starts it again; a reset is
taken only while the cause is gone;
- an operator reset clearing an Auto / Retry latch early sets bCleared, not bReset;
- a garbage response acts as Trip, a garbage reset as Retry, both with bBadSetting; a negative delay /
recover acts as 0 (recover 0 keeps the retry limit), a negative nMaxRetries locks out at the first trip,
a negative window is one hour.
Returns TRUE while it trips. *)

FUNCTION F_Protect : BOOL
  VAR_INPUT
    tNow : TIME; (* TIME() of this scan *)
    bCause : BOOL; (* the condition is present now *)
    bResetReq : BOOL; (* reset request this scan *)
    tRetryWindow : TIME; (* Retry counts trips within this window (T#0s: no window) *)
  END_VAR
  VAR_IN_OUT
    stSet : ST_ProtectionSet; (* settings (read only) *)
    stSts : ST_ProtectionSts;
    stWork : ST_ProtectionWork;
  END_VAR
  VAR
    eResp : E_Response;
    eRst : E_ResetMode;
    tDelay : TIME;
    tRecover : TIME;
    tWindow : TIME;
    bWin : BOOL;
    bBad : BOOL;
  END_VAR


stWork.bReset := FALSE;
stWork.bCleared := FALSE;
bBad := FALSE;
CASE stSet.eResponse OF
  E_Response.Off:
    stSts.eState := E_ProtState.Clear;
    stSts.nRetries := 0;
    stSts.tTimeLeft := T#0s;
    stWork.bActive := FALSE;
    stWork.bLatched := FALSE;
    stWork.bNeedsReset := FALSE;
    stWork.bCausePrev := FALSE;
    stWork.bActivePrev := FALSE;
    stWork.bTrip := FALSE;
    stWork.bWarn := FALSE;
    stWork.bSignal := FALSE;
    stWork.bBadSetting := FALSE;
    F_Protect := FALSE;
    RETURN;
  E_Response.Warn, E_Response.Trip, E_Response.Signal:
    eResp := stSet.eResponse;
ELSE
  eResp := E_Response.Trip;       // a garbage response never removes a protection
  bBad := TRUE;
END_CASE;
CASE stSet.eReset OF
  E_ResetMode.Manual, E_ResetMode.Retry, E_ResetMode.Auto:
    eRst := stSet.eReset;
ELSE
  eRst := E_ResetMode.Retry;      // rides through glitches, locks out after its retries
  bBad := TRUE;
END_CASE;
tDelay := stSet.tDelay;
IF tDelay < T#0s THEN tDelay := T#0s; bBad := TRUE; END_IF;
tRecover := stSet.tRecover;
IF tRecover < T#0s THEN
  tRecover := T#0s;
  bBad := TRUE;
  IF eRst = E_ResetMode.Auto THEN eRst := E_ResetMode.Retry; END_IF;   // never endless restarts
END_IF;
tWindow := tRetryWindow;
IF tWindow < T#0s THEN tWindow := T#1h; bBad := TRUE; END_IF;
IF eRst = E_ResetMode.Retry AND stSet.nMaxRetries < 0 THEN bBad := TRUE; END_IF;
stWork.bBadSetting := bBad;
bWin := tWindow > T#0s;

IF bCause AND NOT stWork.bCausePrev THEN
  stWork.tCauseSince := tNow;
END_IF;
stWork.bCausePrev := bCause;
stWork.bActive := bCause AND (tNow - stWork.tCauseSince >= tDelay);
IF bCause THEN
  stWork.tGoneSince := tNow;      // the recover wait counts from the raw cause gone
END_IF;

IF eResp = E_Response.Signal THEN
  (* a control point: follows the condition, no alarm, nothing latched; lets go tRecover after the cause *)
  IF stWork.bActive THEN
    stWork.bSignal := TRUE;
  ELSIF stWork.bSignal AND tNow - stWork.tGoneSince < tRecover THEN
    stWork.bSignal := TRUE;       // the restart delay
  ELSE
    stWork.bSignal := FALSE;
  END_IF;
  stWork.bLatched := FALSE;
  stWork.bNeedsReset := FALSE;
  stWork.bActivePrev := stWork.bActive;
  stWork.bTrip := FALSE;
  stWork.bWarn := FALSE;
  stSts.nRetries := 0;
  stSts.tTimeLeft := T#0s;
  IF stWork.bActive THEN
    stSts.eState := E_ProtState.Signal;
  ELSIF stWork.bSignal THEN
    stSts.eState := E_ProtState.Recovering;
    stSts.tTimeLeft := tRecover - (tNow - stWork.tGoneSince);
  ELSIF bCause THEN
    stSts.eState := E_ProtState.Pending;
    stSts.tTimeLeft := tDelay - (tNow - stWork.tCauseSince);
  ELSE
    stSts.eState := E_ProtState.Clear;
  END_IF;
  IF stSts.tTimeLeft < T#0s THEN stSts.tTimeLeft := T#0s; END_IF;
  F_Protect := FALSE;
  RETURN;
END_IF;
stWork.bSignal := FALSE;

IF stWork.bActive AND NOT stWork.bActivePrev THEN
  stSts.nCount := stSts.nCount + 1;
  stWork.bLatched := TRUE;
  IF eRst = E_ResetMode.Manual THEN
    stWork.bNeedsReset := TRUE;
  ELSIF eRst = E_ResetMode.Retry AND eResp = E_Response.Trip THEN
    IF stSts.nRetries = 0 OR (bWin AND tNow - stWork.tWindowStart > tWindow) THEN
      stWork.tWindowStart := tNow;
      stSts.nRetries := 0;
    END_IF;
    stSts.nRetries := stSts.nRetries + 1;
    IF stSts.nRetries > stSet.nMaxRetries THEN
      stWork.bNeedsReset := TRUE;
    END_IF;
  END_IF;
END_IF;
stWork.bActivePrev := stWork.bActive;
IF bWin AND stSts.nRetries > 0 AND NOT stWork.bNeedsReset AND tNow - stWork.tWindowStart > tWindow THEN
  stSts.nRetries := 0;
END_IF;

IF stWork.bLatched THEN
  IF stWork.bNeedsReset THEN
    IF bResetReq AND NOT bCause THEN
      stWork.bLatched := FALSE;
      stWork.bNeedsReset := FALSE;
      stSts.nRetries := 0;
      stWork.bReset := TRUE;      // a reset that was needed: the owner may ask for a new command
    END_IF;
  ELSIF eResp = E_Response.Warn THEN
    stWork.bLatched := stWork.bActive;
  ELSIF NOT bCause AND tNow - stWork.tGoneSince >= tRecover THEN
    stWork.bLatched := FALSE;
  ELSIF NOT bCause AND bResetReq THEN
    (* the operator's reset with the cause gone: no wait, a fresh retry count, no command cycle *)
    stWork.bLatched := FALSE;
    stSts.nRetries := 0;
    stWork.bCleared := TRUE;
  END_IF;
ELSIF bResetReq AND stSts.nRetries > 0 THEN
  stSts.nRetries := 0;
END_IF;

stSts.tTimeLeft := T#0s;
IF stWork.bLatched THEN
  IF NOT stWork.bNeedsReset AND eResp = E_Response.Trip AND NOT bCause THEN
    stSts.tTimeLeft := tRecover - (tNow - stWork.tGoneSince);
  END_IF;
ELSIF bCause AND NOT stWork.bActive THEN
  stSts.tTimeLeft := tDelay - (tNow - stWork.tCauseSince);
END_IF;
IF stSts.tTimeLeft < T#0s THEN
  stSts.tTimeLeft := T#0s;
END_IF;
stWork.bTrip := stWork.bLatched AND eResp = E_Response.Trip;
stWork.bWarn := stWork.bLatched AND eResp = E_Response.Warn;
IF stWork.bLatched THEN
  IF stWork.bNeedsReset THEN
    stSts.eState := E_ProtState.Locked;
  ELSIF stWork.bWarn THEN
    stSts.eState := E_ProtState.Warning;
  ELSIF NOT bCause THEN
    stSts.eState := E_ProtState.Recovering;
  ELSE
    stSts.eState := E_ProtState.Tripped;
  END_IF;
ELSIF bCause THEN
  stSts.eState := E_ProtState.Pending;
ELSE
  stSts.eState := E_ProtState.Clear;
END_IF;
F_Protect := stWork.bTrip;

END_FUNCTION