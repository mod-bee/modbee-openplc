(* One level with a setpoint. Good FALSE (or a value that is not a number) holds
the level as it is (a glitch changes nothing); Release (the measurement has
stayed bad past sensorBad's delay) lets go of the value-driven part, so no
stale trip and no frozen "OK" - a switch still acts. *)

FUNCTION UT_LEVEL_RUN : BOOL
  VAR_INPUT
    TNow : TIME;
    In : REAL;
    Good : BOOL := TRUE; (* the value can be trusted *)
    High : BOOL; (* TRUE = high level, FALSE = low level *)
    UseIn : BOOL; (* FALSE: In is not used (only a switch is fitted) *)
    Switch : BOOL; (* a switch (or a band from a switch source) signalling this level *)
    Enable : BOOL; (* FALSE: the condition is treated as absent *)
    Release : BOOL; (* the measurement is bad past its delay: drop the value part *)
    ResetReq : BOOL;
    RetryWindow : TIME;
  END_VAR
  VAR_IN_OUT
    Level : UT_LEVEL; (* settings (read only) *)
    Sts : UT_PROT_STS;
    St : UT_PROT_ST;
  END_VAR
  VAR
    db : REAL;
    prot : UT_PROTECTION; (* a temporary: this function's stack *)
    x : BOOL;
  END_VAR


St.badInput := UseIn AND (NOT Good OR NOT (In = In) OR In > 3.4E38 OR In < -3.4E38);
IF Level.deadband >= 0.0 AND Level.deadband <= 3.4E38 THEN
  db := Level.deadband;
ELSE
  db := 0.0;
END_IF;
IF NOT UseIn OR Release THEN
  St.beyond := FALSE;
ELSIF NOT St.badInput THEN
  IF High THEN
    St.beyond := In > Level.sp OR (St.beyond AND In > Level.sp - db);
  ELSE
    St.beyond := In < Level.sp OR (St.beyond AND In < Level.sp + db);
  END_IF;
END_IF;                          // bad but not released: hold (ride-through)
prot.response := Level.response;
prot.delay := Level.delay;
prot.reset := Level.reset;
prot.recover := Level.recover;
prot.maxRetries := Level.maxRetries;
x := UT_PROT_RUN(TNow := TNow, Cause := (St.beyond OR Switch) AND Enable, ResetReq := ResetReq,
                 RetryWindow := RetryWindow, Prot := prot, Sts := Sts, St := St);
IF Level.response <> UT_RESP_OFF AND UseIn
   AND (NOT (Level.sp = Level.sp) OR Level.sp > 3.4E38 OR Level.sp < -3.4E38
        OR NOT (Level.deadband >= 0.0 AND Level.deadband <= 3.4E38)) THEN
  St.badSetting := TRUE;
END_IF;
UT_LEVEL_RUN := St.trip;

END_FUNCTION