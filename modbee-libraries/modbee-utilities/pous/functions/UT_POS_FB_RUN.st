(* UT_POS_FB_RUN — position feedback and the position thresholds, once for
UT_VALVE_FLOAT and UT_VALVE_MOD (private). Reads the feedback (fitted,
value, good): outside -5..105 % or not Good -> the posFeedback protection;
|target - feedback| while settled -> the deviation level. The position in
use is the feedback when good, else the variant's estimate (-1 unknown).
IsOpen / IsClosed from the thresholds or the end switches. Both protections
join the core through UT_PROT_EXT (faultCode bits 6 deviation, 7
posFeedback). UT_POS_FB_CHECK checks the pos settings. *)

FUNCTION UT_POS_FB_RUN : REAL
  VAR_INPUT
    TNow : TIME;
    Fitted : BOOL; (* a feedback is linked and fitted *)
    Value : REAL;
    Good : BOOL;
    Target : REAL; (* where it is asked to be, % *)
    Estimate : REAL; (* the variant's estimate, % (-1 unknown) *)
    Settled : BOOL; (* not moving / not ramping: the deviation is supervised *)
    Supervise : BOOL := TRUE; (* FALSE: OOS / simulate *)
    LsOpen : BOOL; (* end switches (in use and made) *)
    LsClosed : BOOL;
    ResetReq : BOOL;
    RetryWindow : TIME;
  END_VAR
  VAR_OUTPUT
    IsOpen : BOOL;
    IsClosed : BOOL;
    FbOk : BOOL;
  END_VAR
  VAR_IN_OUT
    Set : UT_VALVE_POS_SET;
    Sts : UT_VALVE_POS_STS;
    St : UT_POS_FB_ST;
    Sum : UT_PROT_EXT_SUM;
  END_VAR
  VAR
    bad : BOOL;
    pos : REAL;
    x : BOOL;
  END_VAR


bad := Fitted AND (NOT Good OR NOT (Value = Value) OR Value < -5.0 OR Value > 105.0);
FbOk := Fitted AND NOT bad;
x := UT_PROT_RUN(TNow := TNow, Cause := Supervise AND bad, ResetReq := ResetReq, RetryWindow := RetryWindow,
                 Prot := Set.posFeedback, Sts := Sts.posFeedback, St := St.fb);
x := UT_PROT_EXT(Bit := 16#80, Id := UT_F_POS_FEEDBACK, Reset := Set.posFeedback.reset, St := St.fb,
                 Sts := Sts.posFeedback, Sum := Sum);
x := UT_LEVEL_RUN(TNow := TNow, In := ABS(Target - Value), Good := TRUE, High := TRUE, UseIn := TRUE, Switch := FALSE,
                  Enable := Supervise AND FbOk AND Settled AND Target >= 0.0, Release := FALSE, ResetReq := ResetReq,
                  RetryWindow := RetryWindow, Level := Set.deviation, Sts := Sts.deviation, St := St.dev);
x := UT_PROT_EXT(Bit := 16#40, Id := UT_F_POS_DEVIATION, Reset := Set.deviation.reset, St := St.dev,
                 Sts := Sts.deviation, Sum := Sum);
IF FbOk THEN
  pos := LIMIT(0.0, Value, 100.0);
ELSE
  pos := Estimate;
END_IF;
IsOpen := LsOpen OR (pos >= 0.0 AND pos >= Set.openThreshold);
IsClosed := LsClosed OR (pos >= 0.0 AND pos <= Set.closedThreshold);
IF LsOpen AND LsClosed THEN
  IsOpen := FALSE;               (* both made: neither (the core's bothLimits) *)
  IsClosed := FALSE;
END_IF;
Sts.fbOk := FbOk;
IF Fitted THEN
  Sts.feedback := Value;
ELSE
  Sts.feedback := -1.0;
END_IF;
Sts.estimate := Estimate;
UT_POS_FB_RUN := pos;

END_FUNCTION