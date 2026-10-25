(* UT_MOTOR_CORE — the shared motor logic with every hook as a pin. Kept in the
library for projects that built their own motor variant on it; the library's
own motors no longer use it: they extend UT_MOTOR, whose body is this logic,
and set its PROTECTED hooks directly.

It is a UT_MOTOR (every UT_MOTOR pin, method and Data field) plus:
in   VarStartDone, VarPlannedGap, VarStartBlock   the variant's start sequence
VarCfgFault, VarCfgHand, VarCfgWarn, VarCfgId the variant's settings check
VarStatus, VarTime                     what the variant's sequence is doing
VarExt                                 the variant's own protections (UT_PROT_EXT_SUM)
VarDriveCleared                        VSD: the fault relay dropped after a reset pulse
VarJog                                 the variant's own jog (e.g. reverse)
VarOwnFb, VarFeedback                  VarFeedback replaces the Feedback pin
out  RunWanted   the motor should run (drive your variant's outputs from it)
Available, HeldNow, CurrentA
OwnerSpeed  the owner's speed (NaN = none)
ModeNow, ResetWanted, HandStarted, FirstScan   this scan's mode, reset want,
Hand start and first scan after power-up
RestartIn, StopReason and RunHours are UT_MOTOR's methods. Current is UT_MOTOR's
plug (UT_I_MEAS), not a REAL: CurrentA gives the amps. The pins are named apart
from UT_MOTOR's hooks (IEC names are case-insensitive: RunReq would be runReq).
The owner links it through UT_MOTOR's Request method. *)

FUNCTION_BLOCK UT_MOTOR_CORE EXTENDS UT_MOTOR
  VAR_INPUT
    VarStartDone : BOOL := TRUE; (* the variant's start sequence is done (delta, speed reached) *)
    VarPlannedGap : BOOL; (* a changeover gap: feedback supervision quiet *)
    VarStartBlock : BOOL; (* may not start now (dead time, drive not ready) *)
    VarCfgFault : BOOL; (* a variant setting refuses every run *)
    VarCfgHand : BOOL; (* ... refuses Hand *)
    VarCfgWarn : BOOL; (* ... warns *)
    VarCfgId : UT_FAULT;
    VarStatus : UT_STATUS := UT_ST_IDLE; (* what the variant's sequence is doing *)
    VarTime : TIME;
    VarExt : UT_PROT_EXT_SUM; (* the variant's protections *)
    VarDriveCleared : BOOL; (* VSD: the fault relay dropped after a reset pulse *)
    VarJog : BOOL; (* the variant's own jog pin *)
    VarOwnFb : BOOL; (* VarFeedback replaces the Feedback pin *)
    VarFeedback : BOOL;
  END_VAR
  VAR_OUTPUT
    RunWanted : BOOL; (* the motor should run: drive your variant's outputs from it *)
    Available : BOOL;
    HeldNow : BOOL; (* an owner holds it off *)
    CurrentA : REAL; (* A (NaN = not measured) *)
    OwnerSpeed : REAL; (* the owner's speed (NaN = none) *)
    ModeNow : UT_MODE; (* the mode this scan *)
    ResetWanted : BOOL; (* this scan's reset want *)
    HandStarted : BOOL; (* one scan: a Hand start *)
    FirstScan : BOOL; (* one scan: the first scan after power-up *)
  END_VAR


vStartDone := VarStartDone;
vPlannedGap := VarPlannedGap;
vStartBlock := VarStartBlock;
vCfgFault := VarCfgFault;
vCfgHand := VarCfgHand;
vCfgWarn := VarCfgWarn;
vCfgId := VarCfgId;
vStatus := VarStatus;
vTime := VarTime;
vTrip := VarExt;
vDriveCleared := VarDriveCleared;
vJog := VarJog;
vOwnFb := VarOwnFb;
vFeedback := VarFeedback;
SUPER();
RunWanted := runReq;
OwnerSpeed := linkSpeed;
ModeNow := curMode;
ResetWanted := resetReq;
HandStarted := handStart;
FirstScan := powerUp;
Available := Data.sts.available;
HeldNow := Data.sts.held;
CurrentA := Data.sts.current;

END_FUNCTION_BLOCK