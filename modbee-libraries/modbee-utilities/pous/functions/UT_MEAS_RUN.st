(* A measurement's four levels, its switches or band inputs, and its sensorBad
protection. A level's switch is the mapped HighSwitch / LowSwitch pin or its
band input (from a UT_I_MEAS: IsHiHi ...). Analog setpoints in use must be in
order (HH >= H > L >= LL): badOrder, the owner's config fault. SIGNAL levels
set hiHi .. loLo without trip / warn. *)

FUNCTION UT_MEAS_RUN : BOOL
  VAR_INPUT
    TNow : TIME;
    In : REAL;
    Good : BOOL := TRUE;
    HasValue : BOOL := TRUE; (* the source has a continuous value (FALSE: a switch-only plug) *)
    Fitted : BOOL := TRUE; (* FALSE: the plug's sensor is not on this site: no value, bands or fault from it (the switch pins still count) *)
    Linked : BOOL; (* a measurement plug is wired: it gives the value / bands (Meas.installed still decides whether this owner checks it) *)
    Inhibit : BOOL := FALSE; (* every check off, no fault (the owner is inhibited) *)
    HighSwitch : BOOL;
    LowSwitch : BOOL;
    BandHH : BOOL;
    BandH : BOOL;
    BandL : BOOL;
    BandLL : BOOL;
    Running : BOOL;
    Masked : BOOL;
    ResetReq : BOOL;
    RetryWindow : TIME;
  END_VAR
  VAR_IN_OUT
    Meas : UT_MEAS; (* settings (read only) *)
    Sts : UT_MEAS_STS;
    St : UT_MEAS_ST;
  END_VAR
  VAR
    analog : BOOL;
    switches : BOOL;
    highOn : BOOL;
    lowOn : BOOL;
    check : BOOL;
    checkLow : BOOL;
    isGood : BOOL;
    inst : BOOL;
    release : BOOL;
    x : BOOL;
  END_VAR


inst := Meas.installed;         (* the owner's choice: one plug can be wired to several owners *)
(* the value is checked when the settings choose a transmitter and the source has one (a plug: fitted, with a value) *)
analog := (Meas.sensor = UT_SENSOR_ANALOG OR Meas.sensor = UT_SENSOR_BOTH) AND HasValue AND Fitted;
switches := Meas.sensor = UT_SENSOR_SWITCH OR Meas.sensor = UT_SENSOR_BOTH;
highOn := switches AND HighSwitch;
lowOn := switches AND LowSwitch;
check := inst AND NOT Inhibit AND (Running OR NOT Meas.onlyWhenRunning);
checkLow := check AND NOT (Meas.maskAtStart AND Masked);
isGood := Good AND (NOT analog OR (In = In AND In <= 3.4E38 AND In >= -3.4E38));

(* the measurement stays bad: its own protection; levels ride through until it acts *)
x := UT_PROT_RUN(TNow := TNow, Cause := inst AND Fitted AND NOT Inhibit AND NOT isGood, ResetReq := ResetReq,
                 RetryWindow := RetryWindow, Prot := Meas.sensorBad, Sts := Sts.sensorBad, St := St.sb);
release := Sts.sensorBad.active;
St.goodHeld := inst AND Fitted AND NOT Inhibit AND NOT isGood AND NOT release;

x := UT_LEVEL_RUN(TNow := TNow, In := In, Good := isGood, High := TRUE, UseIn := analog,
                  Switch := (highOn AND Meas.highSwitch = UT_LVL_HIHI) OR BandHH, Enable := check,
                  Release := release, ResetReq := ResetReq, RetryWindow := RetryWindow,
                  Level := Meas.hiHi, Sts := Sts.hiHi, St := St.hh);
x := UT_LEVEL_RUN(TNow := TNow, In := In, Good := isGood, High := TRUE, UseIn := analog,
                  Switch := (highOn AND Meas.highSwitch = UT_LVL_HI) OR BandH, Enable := check,
                  Release := release, ResetReq := ResetReq, RetryWindow := RetryWindow,
                  Level := Meas.hi, Sts := Sts.hi, St := St.h);
x := UT_LEVEL_RUN(TNow := TNow, In := In, Good := isGood, High := FALSE, UseIn := analog,
                  Switch := (lowOn AND Meas.lowSwitch = UT_LVL_LO) OR BandL, Enable := checkLow,
                  Release := release, ResetReq := ResetReq, RetryWindow := RetryWindow,
                  Level := Meas.lo, Sts := Sts.lo, St := St.l);
x := UT_LEVEL_RUN(TNow := TNow, In := In, Good := isGood, High := FALSE, UseIn := analog,
                  Switch := (lowOn AND Meas.lowSwitch = UT_LVL_LOLO) OR BandLL, Enable := checkLow,
                  Release := release, ResetReq := ResetReq, RetryWindow := RetryWindow,
                  Level := Meas.loLo, Sts := Sts.loLo, St := St.ll);

(* the analog setpoints in use must be in order: HH >= H > L >= LL *)
St.badOrder := FALSE;
IF inst AND analog THEN
  IF Meas.hiHi.response <> UT_RESP_OFF AND Meas.hi.response <> UT_RESP_OFF AND Meas.hiHi.sp < Meas.hi.sp THEN St.badOrder := TRUE; END_IF;
  IF Meas.hi.response <> UT_RESP_OFF AND Meas.lo.response <> UT_RESP_OFF AND Meas.hi.sp <= Meas.lo.sp THEN St.badOrder := TRUE; END_IF;
  IF Meas.hiHi.response <> UT_RESP_OFF AND Meas.lo.response <> UT_RESP_OFF AND Meas.hiHi.sp <= Meas.lo.sp THEN St.badOrder := TRUE; END_IF;
  IF Meas.lo.response <> UT_RESP_OFF AND Meas.loLo.response <> UT_RESP_OFF AND Meas.lo.sp < Meas.loLo.sp THEN St.badOrder := TRUE; END_IF;
  IF Meas.hi.response <> UT_RESP_OFF AND Meas.loLo.response <> UT_RESP_OFF AND Meas.hi.sp <= Meas.loLo.sp THEN St.badOrder := TRUE; END_IF;
  IF Meas.hiHi.response <> UT_RESP_OFF AND Meas.loLo.response <> UT_RESP_OFF AND Meas.hiHi.sp <= Meas.loLo.sp THEN St.badOrder := TRUE; END_IF;
END_IF;
Sts.badOrder := St.badOrder;

St.trip := St.hh.trip OR St.h.trip OR St.l.trip OR St.ll.trip OR St.sb.trip;
St.warn := St.hh.warn OR St.h.warn OR St.l.warn OR St.ll.warn OR St.sb.warn;
St.hiHi := St.hh.trip OR St.hh.warn OR St.hh.sig;
St.hi := St.h.trip OR St.h.warn OR St.h.sig;
St.lo := St.l.trip OR St.l.warn OR St.l.sig;
St.loLo := St.ll.trip OR St.ll.warn OR St.ll.sig;
St.reset := St.hh.reset OR St.h.reset OR St.l.reset OR St.ll.reset OR St.sb.reset;
St.badInput := inst AND Fitted AND NOT Inhibit AND NOT isGood;
St.badSetting := inst AND (St.hh.badSetting OR St.h.badSetting OR St.l.badSetting
                                     OR St.ll.badSetting OR St.sb.badSetting);
IF analog THEN
  Sts.value := In;
END_IF;
Sts.good := NOT inst OR NOT Fitted OR isGood;
UT_MEAS_RUN := St.trip;

END_FUNCTION