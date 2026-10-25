(* UT_PROTECT — one protection on any condition: delay, response (OFF / WARN /
TRIP / SIGNAL), reset (AUTO / RETRY / MANUAL), recover from the cause.
Settings kept by the block; a bad write is put back. Reset acts on its
rising edge, ResetReq (for block builders) while TRUE. *)

FUNCTION_BLOCK UT_PROTECT
  VAR_INPUT
    Cause : BOOL; (* the condition is present *)
    Reset : BOOL R_EDGE;
    ResetReq : BOOL; (* a reset while TRUE (builders) *)
    RetryWindow : TIME := T#1h;
  END_VAR
  VAR_OUTPUT
    Trip : BOOL;
    Warn : BOOL;
    Signal : BOOL; (* SIGNAL response: the condition's state (no alarm) *)
    Event : BOOL; (* one scan: it acted *)
    ResetDone : BOOL; (* one scan: a needed reset was done *)
    Cleared : BOOL; (* one scan: a reset cleared an AUTO / RETRY latch early *)
    BadSetting : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_PROTECT_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_PROTECTION;
    keptGood : BOOL;
  END_VAR
  VAR
    hReset : BOOL;
    keep : UT_KEEP;
    st : UT_PROT_ST;
    ok : BOOL;
    x : BOOL;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_PROT_OK(P := Data.set);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.refused := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_PROT_OK(P := Data.set);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
x := UT_PROT_RUN(TNow := TIME(), Cause := Cause, ResetReq := Reset OR ResetReq OR (Data.cmdReset AND NOT hReset),
                 RetryWindow := RetryWindow, Prot := Data.set, Sts := Data.sts, St := st);
hReset := Data.cmdReset;   (* the HMI command acts once per request, even when held on *)
Data.cmdReset := FALSE;
Trip := st.trip;
Warn := st.warn;
Signal := st.sig;
Event := st.event;
ResetDone := st.reset;
Cleared := st.cleared;
BadSetting := st.badSetting;

END_FUNCTION_BLOCK