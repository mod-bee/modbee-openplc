(* UT_MEAS_CHECK — a 4-level measurement for block builders: the settings and
the status live in the caller's own record (Meas, Sts), so a block can
hold any number of measurements. The value comes from the Sensor plug
(transmitter, float set, voted set, vessel) or else from In / InGood. *)

FUNCTION_BLOCK UT_MEAS_CHECK
  VAR_INPUT
    In : REAL; (* when Sensor is not wired *)
    InGood : BOOL := TRUE;
    HighSwitch : BOOL;
    LowSwitch : BOOL;
    Running : BOOL; (* for onlyWhenRunning *)
    Masked : BOOL; (* for maskAtStart *)
    Reset : BOOL R_EDGE;
    ResetReq : BOOL; (* a reset while TRUE (builders) *)
    RetryWindow : TIME := T#1h;
    Sensor : UT_I_MEAS;
  END_VAR
  VAR_OUTPUT
    Trip : BOOL;
    Warn : BOOL;
    HiHi : BOOL;
    Hi : BOOL;
    Lo : BOOL;
    LoLo : BOOL;
    SensorBad : BOOL;
    ResetDone : BOOL;
    Cleared : BOOL;
    BadInput : BOOL;
    BadSetting : BOOL;
    BadOrder : BOOL;
  END_VAR
  VAR_IN_OUT
    Meas : UT_MEAS; (* the caller's settings *)
    Sts : UT_MEAS_STS; (* the caller's status *)
  END_VAR
  VAR
    st : UT_MEAS_ST;
    v : REAL;
    g : BOOL;
    hasV : BOOL;
    fit : BOOL;
    bHH : BOOL;
    bH : BOOL;
    bL : BOOL;
    bLL : BOOL;
    x : BOOL;
  END_VAR


x := UT_MEAS_READ(Sensor := Sensor, In := In, InGood := InGood, V => v, G => g, HasValue => hasV, Fitted => fit,
                  BandHH => bHH, BandH => bH, BandL => bL, BandLL => bLL);
x := UT_MEAS_RUN(TNow := TIME(), In := v, Good := g, HasValue := hasV, Fitted := fit, Linked := Sensor <> NULL, HighSwitch := HighSwitch,
                 LowSwitch := LowSwitch, BandHH := bHH, BandH := bH, BandL := bL, BandLL := bLL, Running := Running,
                 Masked := Masked, ResetReq := Reset OR ResetReq, RetryWindow := RetryWindow,
                 Meas := Meas, Sts := Sts, St := st);
Trip := st.trip;
Warn := st.warn;
HiHi := st.hiHi;
Hi := st.hi;
Lo := st.lo;
LoLo := st.loLo;
SensorBad := st.sb.trip OR st.sb.warn;
ResetDone := st.reset;
Cleared := st.hh.cleared OR st.h.cleared OR st.l.cleared OR st.ll.cleared OR st.sb.cleared;
BadInput := st.badInput;
BadSetting := st.badSetting;
BadOrder := st.badOrder;

END_FUNCTION_BLOCK