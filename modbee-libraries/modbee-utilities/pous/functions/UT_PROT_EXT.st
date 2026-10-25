(* UT_PROT_EXT — adds one of a variant's own protections (a motor's speed
deviation, a changeover, a drive not ready; a valve's torque ...) into the
summary its base block reads (private). The variant clears the summary at
the start of its scan (UT_PROT_EXT_CLEAR), runs each protection through
UT_PROT_RUN, then adds it here; the base shows the first one tripping. *)

FUNCTION UT_PROT_EXT : BOOL
  VAR_INPUT
    Bit : DWORD; (* its faultCode bit *)
    Id : UT_FAULT; (* its name *)
    Reset : UT_RESET_MODE; (* its reset mode (the settings) *)
  END_VAR
  VAR_IN_OUT
    St : UT_PROT_ST; (* its engine state (after UT_PROT_RUN this scan) *)
    Sts : UT_PROT_STS; (* its status *)
    Sum : UT_PROT_EXT_SUM;
  END_VAR


IF St.trip THEN
  IF Sum.trip = 0 THEN
    Sum.tripId := Id;
    Sum.tripStatus := UT_PROT_STATUS(Reset := Reset, Sts := Sts);
    Sum.tripTime := Sts.timeLeft;
  END_IF;
  Sum.trip := Sum.trip OR Bit;
END_IF;
IF St.warn THEN
  IF Sum.warn = 0 THEN
    Sum.warnId := Id;
  END_IF;
  Sum.warn := Sum.warn OR Bit;
END_IF;
IF Sts.tripped THEN
  Sum.tripped := Sum.tripped OR Bit;
END_IF;
IF St.badSetting AND Sum.cfgId = UT_F_NONE THEN
  Sum.cfgId := Id;
END_IF;
Sum.resetDone := Sum.resetDone OR St.reset;
Sum.locked := Sum.locked OR Sts.locked;
UT_PROT_EXT := St.trip;

END_FUNCTION