(* F_Protect — the protection engine every block is built from.
A FUNCTION: no instance; the VAR_IN_OUTs are references to the owner's settings, status and private state.

- a condition acts after its delay; Off ignores it; Signal follows it with no alarm (no latch, count, retry,
warning or trip) and lets go once the cause has been gone tAutoRecoverAfter (a restart delay: a source refills before
its pump starts again; 0 = at once);
- Auto clears once the cause has been gone tAutoRecoverAfter; Retry does the same but locks out after nMaxRetriesBeforeLockout
trips in the window; Manual needs a reset;
- the recover wait counts from the raw cause gone; a cause back inside the wait starts it again; a reset is
taken only while the cause is gone;
- an operator reset clearing an Auto / Retry latch early sets bClearedEarly, not bReset;
- a garbage response acts as Trip, a garbage reset as Retry, both with bSettingBad; a negative delay /
recover acts as 0 (recover 0 keeps the retry limit), a negative nMaxRetriesBeforeLockout locks out at the first trip,
a negative window is one hour.
Returns TRUE while it trips. *)

FUNCTION F_Protect : BOOL
  VAR_INPUT
    tNow : TIME; (* TIME() of this scan *)
    bConditionPresent : BOOL; (* the condition is present now *)
    bResetRequest : BOOL; (* reset request this scan *)
    tRetryCountWindow : TIME; (* Retry counts trips within this window (T#0s: no window) *)
  END_VAR
  VAR_IN_OUT
    stSettings : ST_ProtectionSet; (* settings (read only) *)
    stStatus : ST_ProtectionSts; (* status *)
    stWorking : ST_ProtectionWork; (* working memory *)
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


stWorking.bResetDone := FALSE;
stWorking.bClearedEarly := FALSE;
bBad := FALSE;
CASE stSettings.eActionOnFault OF
  E_Response.Off:
    stStatus.eFaultState := E_ProtState.Clear;
    stStatus.nRetriesUsed := 0;
    stStatus.tTimeLeft := T#0s;
    stWorking.bActive := FALSE;
    stWorking.bLatched := FALSE;
    stWorking.bResetNeeded := FALSE;
    stWorking.bConditionLastScan := FALSE;
    stWorking.bActiveLastScan := FALSE;
    stWorking.bTripping := FALSE;
    stWorking.bWarning := FALSE;
    stWorking.bSignalling := FALSE;
    stWorking.bSettingBad := FALSE;
    F_Protect := FALSE;
    RETURN;
  E_Response.Warn, E_Response.Trip, E_Response.Signal:
    eResp := stSettings.eActionOnFault;
ELSE
  eResp := E_Response.Trip;       // a garbage response never removes a protection
  bBad := TRUE;
END_CASE;
CASE stSettings.eResetMode OF
  E_ResetMode.Manual, E_ResetMode.Retry, E_ResetMode.Auto:
    eRst := stSettings.eResetMode;
ELSE
  eRst := E_ResetMode.Retry;      // rides through glitches, locks out after its retries
  bBad := TRUE;
END_CASE;
tDelay := stSettings.tTripDelay;
IF tDelay < T#0s THEN tDelay := T#0s; bBad := TRUE; END_IF;
tRecover := stSettings.tAutoRecoverAfter;
IF tRecover < T#0s THEN
  tRecover := T#0s;
  bBad := TRUE;
  IF eRst = E_ResetMode.Auto THEN eRst := E_ResetMode.Retry; END_IF;   // never endless restarts
END_IF;
tWindow := tRetryCountWindow;
IF tWindow < T#0s THEN tWindow := T#1h; bBad := TRUE; END_IF;
IF eRst = E_ResetMode.Retry AND stSettings.nMaxRetriesBeforeLockout < 0 THEN bBad := TRUE; END_IF;
stWorking.bSettingBad := bBad;
bWin := tWindow > T#0s;

IF bConditionPresent AND NOT stWorking.bConditionLastScan THEN
  stWorking.tConditionCameAt := tNow;
END_IF;
stWorking.bConditionLastScan := bConditionPresent;
stWorking.bActive := bConditionPresent AND (tNow - stWorking.tConditionCameAt >= tDelay);
IF bConditionPresent THEN
  stWorking.tConditionWentAt := tNow;      // the recover wait counts from the raw cause gone
END_IF;

IF eResp = E_Response.Signal THEN
  (* a control point: follows the condition, no alarm, nothing latched; lets go tAutoRecoverAfter after the cause *)
  IF stWorking.bActive THEN
    stWorking.bSignalling := TRUE;
  ELSIF stWorking.bSignalling AND tNow - stWorking.tConditionWentAt < tRecover THEN
    stWorking.bSignalling := TRUE;       // the restart delay
  ELSE
    stWorking.bSignalling := FALSE;
  END_IF;
  stWorking.bLatched := FALSE;
  stWorking.bResetNeeded := FALSE;
  stWorking.bActiveLastScan := stWorking.bActive;
  stWorking.bTripping := FALSE;
  stWorking.bWarning := FALSE;
  stStatus.nRetriesUsed := 0;
  stStatus.tTimeLeft := T#0s;
  IF stWorking.bActive THEN
    stStatus.eFaultState := E_ProtState.Signal;
  ELSIF stWorking.bSignalling THEN
    stStatus.eFaultState := E_ProtState.Recovering;
    stStatus.tTimeLeft := tRecover - (tNow - stWorking.tConditionWentAt);
  ELSIF bConditionPresent THEN
    stStatus.eFaultState := E_ProtState.Pending;
    stStatus.tTimeLeft := tDelay - (tNow - stWorking.tConditionCameAt);
  ELSE
    stStatus.eFaultState := E_ProtState.Clear;
  END_IF;
  IF stStatus.tTimeLeft < T#0s THEN stStatus.tTimeLeft := T#0s; END_IF;
  F_Protect := FALSE;
  RETURN;
END_IF;
stWorking.bSignalling := FALSE;

IF stWorking.bActive AND NOT stWorking.bActiveLastScan THEN
  stStatus.nTripCount := stStatus.nTripCount + 1;
  stWorking.bLatched := TRUE;
  IF eRst = E_ResetMode.Manual THEN
    stWorking.bResetNeeded := TRUE;
  ELSIF eRst = E_ResetMode.Retry AND eResp = E_Response.Trip THEN
    IF stStatus.nRetriesUsed = 0 OR (bWin AND tNow - stWorking.tRetryWindowStartedAt > tWindow) THEN
      stWorking.tRetryWindowStartedAt := tNow;
      stStatus.nRetriesUsed := 0;
    END_IF;
    stStatus.nRetriesUsed := stStatus.nRetriesUsed + 1;
    IF stStatus.nRetriesUsed > stSettings.nMaxRetriesBeforeLockout THEN
      stWorking.bResetNeeded := TRUE;
    END_IF;
  END_IF;
END_IF;
stWorking.bActiveLastScan := stWorking.bActive;
IF bWin AND stStatus.nRetriesUsed > 0 AND NOT stWorking.bResetNeeded AND tNow - stWorking.tRetryWindowStartedAt > tWindow THEN
  stStatus.nRetriesUsed := 0;
END_IF;

IF stWorking.bLatched THEN
  IF stWorking.bResetNeeded THEN
    IF bResetRequest AND NOT bConditionPresent THEN
      stWorking.bLatched := FALSE;
      stWorking.bResetNeeded := FALSE;
      stStatus.nRetriesUsed := 0;
      stWorking.bResetDone := TRUE;      // a reset that was needed: the owner may ask for a new command
    END_IF;
  ELSIF eResp = E_Response.Warn THEN
    stWorking.bLatched := stWorking.bActive;
  ELSIF NOT bConditionPresent AND tNow - stWorking.tConditionWentAt >= tRecover THEN
    stWorking.bLatched := FALSE;
  ELSIF NOT bConditionPresent AND bResetRequest THEN
    (* the operator's reset with the cause gone: no wait, a fresh retry count, no command cycle *)
    stWorking.bLatched := FALSE;
    stStatus.nRetriesUsed := 0;
    stWorking.bClearedEarly := TRUE;
  END_IF;
ELSIF bResetRequest AND stStatus.nRetriesUsed > 0 THEN
  stStatus.nRetriesUsed := 0;
END_IF;

stStatus.tTimeLeft := T#0s;
IF stWorking.bLatched THEN
  IF NOT stWorking.bResetNeeded AND eResp = E_Response.Trip AND NOT bConditionPresent THEN
    stStatus.tTimeLeft := tRecover - (tNow - stWorking.tConditionWentAt);
  END_IF;
ELSIF bConditionPresent AND NOT stWorking.bActive THEN
  stStatus.tTimeLeft := tDelay - (tNow - stWorking.tConditionCameAt);
END_IF;
IF stStatus.tTimeLeft < T#0s THEN
  stStatus.tTimeLeft := T#0s;
END_IF;
stWorking.bTripping := stWorking.bLatched AND eResp = E_Response.Trip;
stWorking.bWarning := stWorking.bLatched AND eResp = E_Response.Warn;
IF stWorking.bLatched THEN
  IF stWorking.bResetNeeded THEN
    stStatus.eFaultState := E_ProtState.Locked;
  ELSIF stWorking.bWarning THEN
    stStatus.eFaultState := E_ProtState.Warning;
  ELSIF NOT bConditionPresent THEN
    stStatus.eFaultState := E_ProtState.Recovering;
  ELSE
    stStatus.eFaultState := E_ProtState.Tripped;
  END_IF;
ELSIF bConditionPresent THEN
  stStatus.eFaultState := E_ProtState.Pending;
ELSE
  stStatus.eFaultState := E_ProtState.Clear;
END_IF;
F_Protect := stWorking.bTripping;

END_FUNCTION