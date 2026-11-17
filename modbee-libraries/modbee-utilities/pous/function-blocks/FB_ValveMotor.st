(* FB_ValveMotor EXTENDS FB_Valve — a motorised two-position valve or damper.
Everything of FB_Valve (modes, the safe position, the owner, end switches or travel time, protections, strokes,
actuator in Local, slow stroke, exercise) plus the drive: bOpenOut drives open, bCloseOut drives closed, never
together, set.tReversal between them (FB_Changeover); the drive stops at the end (its end switch, or the travel
time), or stays on with set.bDriveHold. set.eType is not used.
Torque switches (bTorqueOpen / bTorqueClose, TRUE = tripped: jammed): set.stTorque (default Trip, Retry); a
torque trip stops the drive where it is (the actuator has failed: it is not driven to the safe position). With
set.bCloseOnTorque the close torque at the end of a close is the seat, not a fault: the valve is closed (also
without a closed switch) until the next command.
Halt (FB_LocalControl's bHalt, I_LocalChoice): in Hand the drive stops where it is, the position not known,
until the next open / close command.
Pins added: bTorqueOpen, bTorqueClose, refMotor (its record). Its settings are kept by the block (a retained
last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_ValveMotor EXTENDS FB_Valve IMPLEMENTS I_LocalChoice
  VAR_INPUT
    refMotor : REFERENCE TO ST_ValveMotorData;
    bTorqueOpen : BOOL; (* the open torque switch tripped *)
    bTorqueClose : BOOL; (* the close torque switch tripped *)
  END_VAR
  VAR RETAIN
    stKeptMotor : ST_ValveMotorSet;
    nKeptMotorLayout : UINT;
  END_VAR
  VAR
    fbCo : FB_Changeover;
    bMotorFirst : BOOL := TRUE;
    stWTorque : ST_ProtectionWork;
    bHaltReq : BOOL; (* Halt asked (Choose) *)
  END_VAR


(* a panel choice (FB_LocalControl bHalt): in Hand, stop where it is *)
METHOD PUBLIC Choose : BOOL
  VAR_INPUT
    eChoice : E_LocalChoice;
  END_VAR
  Choose := eChoice = E_LocalChoice.Halt;
  IF Choose AND __ISVALIDREF(refData) THEN
    IF refData.set.eMode = E_Mode.Hand THEN
      bHaltReq := TRUE;
    END_IF;
  END_IF;
END_METHOD

(* drive toward the position commanded until its end; the torque protection *)
METHOD PROTECTED OVERRIDE Drive
  VAR_INPUT
    bRun : BOOL;
  END_VAR
  VAR
    bDrive : BOOL;
    bHold : BOOL;
    bTorque : BOOL;
  END_VAR
  SUPER^.Drive(bRun := bRun);     // the position commanded (bWantOpen), with the safe position
  bHold := FALSE;
  bTorque := FALSE;
  IF __ISVALIDREF(refMotor) THEN
    bHold := refMotor.set.bDriveHold;
    bTorque := F_Protect(tNow := tNow,
                         bCause := refData.set.eMode <> E_Mode.OutOfService
                                   AND (bTorqueOpen OR (bTorqueClose AND NOT (refMotor.set.bCloseOnTorque AND NOT bWantOpen))),
                         bResetReq := bResetNow, tRetryWindow := refData.set.tRetryWindow,
                         stSet := refMotor.set.stTorque, stSts := refMotor.sts.stTorque, stWork := stWTorque);
  END_IF;
  bVarTrip := stWTorque.bTrip;    (* to the valve's protections (the next scan) *)
  bVarWarn := stWTorque.bWarn;
  IF stWTorque.bTrip OR stWTorque.bWarn THEN
    eVarError := E_UtError.TorqueSwitch;
  ELSE
    eVarError := E_UtError.None;
  END_IF;
  bDrive := bHold OR (bWantOpen AND NOT bIsOpen) OR (NOT bWantOpen AND NOT bIsClosed);
  IF bHalted OR bTorque OR NOT bActRemote THEN
    bDrive := FALSE;              (* stopped where it is *)
  END_IF;
  IF __ISVALIDREF(refMotor) THEN
    fbCo(bRun := bDrive, bWantB := bWantOpen, bUseFb := FALSE, tGapAB := refMotor.set.tReversal,
         tGapBA := refMotor.set.tReversal);
  ELSE
    fbCo(bRun := FALSE);
  END_IF;
  bOpenOut := fbCo.bQB;
  bCloseOut := fbCo.bQA;
END_METHOD

IF __ISVALIDREF(refMotor) THEN
  IF bMotorFirst THEN
    IF nKeptMotorLayout = cLayout THEN
      refMotor.set := stKeptMotor;
    ELSE
      stKeptMotor := refMotor.set;
      nKeptMotorLayout := cLayout;
    END_IF;
    bMotorFirst := FALSE;
  ELSIF refMotor.set.tReversal >= T#0s AND refMotor.set.stTorque.tDelay >= T#0s
        AND refMotor.set.stTorque.tRecover >= T#0s AND refMotor.set.stTorque.nMaxRetries >= 0 THEN
    stKeptMotor := refMotor.set;
  ELSE
    refMotor.set := stKeptMotor;
    refMotor.sts.bRefused := TRUE;
  END_IF;
  bSeatUse := refMotor.set.bCloseOnTorque;
ELSE
  bSeatUse := FALSE;
END_IF;
bSeatMade := bTorqueClose;

(* Halt: Hand only, until the next open / close command or a change of mode *)
IF __ISVALIDREF(refData) THEN
  IF bHaltReq AND refData.set.eMode = E_Mode.Hand THEN
    bHalted := TRUE;
  ELSIF refData.set.eMode <> E_Mode.Hand OR bCmdStartIn OR bCmdStopIn OR refData.bCmdStart OR refData.bCmdStop THEN
    IF bHalted THEN
      tMovedAt := tNow;           (* the move starts again from here *)
    END_IF;
    bHalted := FALSE;
  END_IF;
END_IF;
bHaltReq := FALSE;

SUPER^();                         // the valve: modes, the position commanded, travel, protections

IF __ISVALIDREF(refMotor) THEN
  refMotor.sts.bDriving := bOpenOut OR bCloseOut;
  refMotor.sts.bHalted := bHalted OR stWTorque.bTrip;
END_IF;

END_FUNCTION_BLOCK