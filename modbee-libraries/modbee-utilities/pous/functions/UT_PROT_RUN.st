(* UT_PROT_RUN / UT_LEVEL_RUN / UT_MEAS_RUN — the protection engines every block
is built from (FUNCTIONs: no instance; the VAR_IN_OUTs are references).

Settings (UT_PROTECTION / UT_LEVEL / UT_MEAS) are the owner's kept settings and
are only read here; the live state goes to UT_PROT_STS / UT_MEAS_STS (the
owner's status) and the engine state to UT_PROT_ST / UT_MEAS_ST (private).

The rules (decisions 9, 10, 14, 15, 30):
- a condition acts after its delay; OFF ignores it; SIGNAL follows it with no
alarm (no latch, count, retry, warning or trip);
- AUTO clears once the CAUSE has been gone `recover`; RETRY does the same but
locks out after `maxRetries` trips in the window; MANUAL needs a reset;
- the recover wait counts from the raw cause gone; a cause back inside the
wait starts it again; a reset is taken only while the cause is gone;
- an operator reset clearing an AUTO / RETRY latch early sets `cleared`, not
`reset`: the owner needs no command cycle after it (no device left stuck);
`reset` is set only where a reset was needed (MANUAL, a locked-out RETRY);
- a garbage `response` acts as TRIP, a garbage `reset` as RETRY, both with
`badSetting`; a negative delay / recover acts as 0 (recover 0 keeps the
retry limit), a negative maxRetries locks out at the first trip, a negative
window is one hour. *)

FUNCTION UT_PROT_RUN : BOOL
  VAR_INPUT
    TNow : TIME; (* TIME() of this scan *)
    Cause : BOOL; (* the condition is present now *)
    ResetReq : BOOL; (* reset request this scan *)
    RetryWindow : TIME; (* RETRY counts trips within this window (T#0s: no window) *)
  END_VAR
  VAR_IN_OUT
    Prot : UT_PROTECTION; (* settings (read only) *)
    Sts : UT_PROT_STS; (* status *)
    St : UT_PROT_ST; (* engine state *)
  END_VAR
  VAR
    resp : UT_RESPONSE;
    rst : UT_RESET_MODE;
    delay : TIME;
    recover : TIME;
    window : TIME;
    win : BOOL;
    bad : BOOL;
  END_VAR


St.event := FALSE;
St.reset := FALSE;
St.cleared := FALSE;
bad := FALSE;
CASE Prot.response OF
  UT_RESP_OFF:
    Sts.active := FALSE;
    Sts.tripped := FALSE;
    Sts.locked := FALSE;
    Sts.retries := 0;
    Sts.timeLeft := T#0s;
    St.latched := FALSE;
    St.needsReset := FALSE;
    St.causePrev := FALSE;
    St.activePrev := FALSE;
    St.trip := FALSE;
    St.warn := FALSE;
    St.sig := FALSE;
    St.badSetting := FALSE;
    UT_PROT_RUN := FALSE;
    RETURN;
  UT_RESP_WARN, UT_RESP_TRIP, UT_RESP_SIGNAL:
    resp := Prot.response;
ELSE
  resp := UT_RESP_TRIP;          // a garbage response never removes a protection
  bad := TRUE;
END_CASE;
CASE Prot.reset OF
  UT_RST_AUTO, UT_RST_RETRY, UT_RST_MANUAL:
    rst := Prot.reset;
ELSE
  rst := UT_RST_RETRY;           // rides through glitches, locks out after its retries
  bad := TRUE;
END_CASE;
delay := Prot.delay;
IF delay < T#0s THEN delay := T#0s; bad := TRUE; END_IF;
recover := Prot.recover;
IF recover < T#0s THEN
  recover := T#0s;
  bad := TRUE;
  IF rst = UT_RST_AUTO THEN rst := UT_RST_RETRY; END_IF;   // never endless restarts
END_IF;
window := RetryWindow;
IF window < T#0s THEN window := T#1h; bad := TRUE; END_IF;
IF rst = UT_RST_RETRY AND Prot.maxRetries < 0 THEN bad := TRUE; END_IF;
St.badSetting := bad;
win := window > T#0s;

IF Cause AND NOT St.causePrev THEN
  St.causeSince := TNow;
END_IF;
St.causePrev := Cause;
Sts.active := Cause AND (TNow - St.causeSince >= delay);
IF Cause THEN
  St.goneSince := TNow;          // the recover wait counts from the raw cause gone
END_IF;

IF resp = UT_RESP_SIGNAL THEN
  (* a control point: follows the condition, no alarm, nothing latched *)
  St.sig := Sts.active;
  St.latched := FALSE;
  St.needsReset := FALSE;
  St.activePrev := Sts.active;
  St.trip := FALSE;
  St.warn := FALSE;
  Sts.tripped := Sts.active;
  Sts.locked := FALSE;
  Sts.retries := 0;
  IF Cause AND NOT Sts.active THEN
    Sts.timeLeft := delay - (TNow - St.causeSince);
  ELSE
    Sts.timeLeft := T#0s;
  END_IF;
  IF Sts.timeLeft < T#0s THEN Sts.timeLeft := T#0s; END_IF;
  UT_PROT_RUN := FALSE;
  RETURN;
END_IF;
St.sig := FALSE;

IF Sts.active AND NOT St.activePrev THEN
  St.event := TRUE;
  Sts.count := Sts.count + 1;
  St.latched := TRUE;
  IF rst = UT_RST_MANUAL THEN
    St.needsReset := TRUE;
  ELSIF rst = UT_RST_RETRY AND resp = UT_RESP_TRIP THEN
    IF Sts.retries = 0 OR (win AND TNow - St.windowStart > window) THEN
      St.windowStart := TNow;
      Sts.retries := 0;
    END_IF;
    Sts.retries := Sts.retries + 1;
    IF Sts.retries > Prot.maxRetries THEN
      St.needsReset := TRUE;
    END_IF;
  END_IF;
END_IF;
St.activePrev := Sts.active;
IF win AND Sts.retries > 0 AND NOT St.needsReset AND TNow - St.windowStart > window THEN
  Sts.retries := 0;
END_IF;

IF St.latched THEN
  IF St.needsReset THEN
    IF ResetReq AND NOT Cause THEN
      St.latched := FALSE;
      St.needsReset := FALSE;
      Sts.retries := 0;
      St.reset := TRUE;          // a reset that was needed: the owner may ask for a new command
    END_IF;
  ELSIF resp = UT_RESP_WARN THEN
    St.latched := Sts.active;
  ELSIF NOT Cause AND TNow - St.goneSince >= recover THEN
    St.latched := FALSE;
  ELSIF NOT Cause AND ResetReq THEN
    (* the operator's reset with the cause gone: no wait, a fresh retry count,
       and no command cycle for the owner *)
    St.latched := FALSE;
    Sts.retries := 0;
    St.cleared := TRUE;
  END_IF;
ELSIF ResetReq AND Sts.retries > 0 THEN
  Sts.retries := 0;
END_IF;

Sts.timeLeft := T#0s;
IF St.latched THEN
  IF NOT St.needsReset AND resp = UT_RESP_TRIP AND NOT Cause THEN
    Sts.timeLeft := recover - (TNow - St.goneSince);
  END_IF;
ELSIF Cause AND NOT Sts.active THEN
  Sts.timeLeft := delay - (TNow - St.causeSince);
END_IF;
IF Sts.timeLeft < T#0s THEN
  Sts.timeLeft := T#0s;
END_IF;
St.trip := St.latched AND resp = UT_RESP_TRIP;
St.warn := St.latched AND resp = UT_RESP_WARN;
Sts.tripped := St.latched;
Sts.locked := St.needsReset;
UT_PROT_RUN := St.trip;

END_FUNCTION