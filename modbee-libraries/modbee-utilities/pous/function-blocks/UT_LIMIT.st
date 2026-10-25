(* UT_LIMIT — four levels (HH / H / L / LL) on one measurement, for
protections and control tiers. The value comes from the Sensor plug
(transmitter, float set, voted set, vessel: its bands act as the levels'
switches) or from In / InGood. A bad reading is ridden through until
sensorBad acts. Inhibit treats every level as absent. Settings kept; a bad
write (incl. setpoints out of order) is put back. *)

FUNCTION_BLOCK UT_LIMIT
  VAR_INPUT
    In : REAL; (* the value (when Sensor is not wired) *)
    InGood : BOOL := TRUE;
    HighSwitch : BOOL; (* switches backing up the value *)
    LowSwitch : BOOL;
    Running : BOOL; (* for onlyWhenRunning *)
    Masked : BOOL; (* for maskAtStart *)
    Inhibit : BOOL; (* every level treated as absent *)
    Reset : BOOL R_EDGE;
    Sensor : UT_I_MEAS; (* transmitter, float set, voted set or vessel *)
  END_VAR
  VAR_OUTPUT
    HiHi : BOOL; (* each level in effect (trip, warning or SIGNAL) *)
    Hi : BOOL;
    Lo : BOOL;
    LoLo : BOOL;
    Trip : BOOL;
    Warning : BOOL;
    Fault : BOOL; (* setpoints out of order, or the sensor bad as a trip *)
    SensorBad : BOOL;
    Value : REAL; (* the value checked (NaN when none) *)
  END_VAR
  VAR_IN_OUT
    Data : UT_LIMIT_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_LIMIT_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    hReset : BOOL;
    keep : UT_KEEP;
    st : UT_MEAS_ST;
    ok : BOOL;
    v : REAL;
    g : BOOL;
    hasV : BOOL;
    fit : BOOL;
    bHH : BOOL;
    bH : BOOL;
    bL : BOOL;
    bLL : BOOL;
    x : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_MEAS_OK(OrderCheck := Data.set.orderCheck, M := Data.set.meas) AND Data.set.retryWindow >= T#0s;
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_LEVEL_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_MEAS_OK(OrderCheck := Data.set.orderCheck, M := Data.set.meas) AND Data.set.retryWindow >= T#0s;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

x := UT_MEAS_READ(Sensor := Sensor, In := In, InGood := InGood, V => v, G => g, HasValue => hasV, Fitted => fit,
                  BandHH => bHH, BandH => bH, BandL => bL, BandLL => bLL);
x := UT_MEAS_RUN(TNow := TIME(), In := v, Good := g, HasValue := hasV, Fitted := fit, Inhibit := Inhibit, Linked := Sensor <> NULL,
                 HighSwitch := HighSwitch, LowSwitch := LowSwitch, BandHH := bHH, BandH := bH, BandL := bL,
                 BandLL := bLL, Running := Running, Masked := Masked, ResetReq := Reset OR (Data.cmdReset AND NOT hReset),
                 RetryWindow := Data.set.retryWindow, Meas := Data.set.meas, Sts := Data.sts.meas, St := st);
hReset := Data.cmdReset;   (* the HMI command acts once per request, even when held on *)
Data.cmdReset := FALSE;
IF NOT Data.set.orderCheck THEN
  st.badOrder := FALSE;
  Data.sts.meas.badOrder := FALSE;
END_IF;
HiHi := st.hiHi;
Hi := st.hi;
Lo := st.lo;
LoLo := st.loLo;
Trip := st.hh.trip OR st.h.trip OR st.l.trip OR st.ll.trip;
SensorBad := st.sb.trip OR st.sb.warn;
Fault := st.badOrder OR st.sb.trip;
Warning := st.warn OR st.badSetting OR st.goodHeld;
Value := v;

stCode := UT_MEAS_STATUS(Inhibit := Inhibit, Fitted := fit, Meas := Data.set.meas, Sts := Data.sts.meas, St := st,
                         FaultId => stF, TimeLeft => Data.timeLeft);
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.inhibited := Inhibit;
Data.sts.configBad := st.badOrder;
IF HiHi THEN
  Data.sts.activeLevel := 1;
ELSIF LoLo THEN
  Data.sts.activeLevel := 4;
ELSIF Hi THEN
  Data.sts.activeLevel := 2;
ELSIF Lo THEN
  Data.sts.activeLevel := 3;
ELSE
  Data.sts.activeLevel := 0;
END_IF;

END_FUNCTION_BLOCK