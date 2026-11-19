(* FB_ValveMotor EXTENDS FB_Valve — a motorised two-position valve or damper.
Everything of FB_Valve (modes, the safe position, the owner, end switches or travel time, protections, strokes,
actuator in Local, slow stroke, exercise) plus the drive: bOpenOutput drives open, bCloseOutput drives closed, never
together, set.tReversingDeadTime between them (FB_Changeover); the drive stops at the end (its end switch, or the travel
time), or stays on with set.bKeepDriveAtEnd. set.eValveType is not used.
Torque switches (bOpenTorqueTripped / bCloseTorqueTripped, TRUE = tripped: jammed): set.stTorqueFault (default Trip, Retry); a
torque trip stops the drive where it is (the actuator has failed: it is not driven to the safe position). With
set.bSeatedOnCloseTorque the close torque at the end of a close is the seat, not a fault: the valve is closed (also
without a closed switch) until the next command.
Halt (FB_LocalControl's bHaltButton, I_LocalChoice): in Hand the drive stops where it is, the position not known,
until the next open / close command.
Pins added: bOpenTorqueTripped, bCloseTorqueTripped, refMotorisedData (its record). Its settings are kept by the block (a retained
last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_ValveMotor EXTENDS FB_Valve IMPLEMENTS I_LocalChoice
  VAR_INPUT
    bOpenTorqueTripped : BOOL := FALSE; (* the open torque switch tripped *)
    bCloseTorqueTripped : BOOL; (* the close torque switch tripped *)
    refMotorisedData : REFERENCE TO ST_ValveMotorData; (* the motorised valve record *)
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


(* the first bad setting (None: all good) *)
METHOD PRIVATE MotorWhy : E_UtError
  MotorWhy := E_UtError.None;
  IF NOT (refMotorisedData.set.tReversingDeadTime >= T#0s) THEN
    MotorWhy := E_UtError.TimeBad;
  ELSIF NOT (refMotorisedData.set.stTorqueFault.tTripDelay >= T#0s) THEN
    MotorWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refMotorisedData.set.stTorqueFault.tAutoRecoverAfter >= T#0s) THEN
    MotorWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refMotorisedData.set.stTorqueFault.nMaxRetriesBeforeLockout >= 0) THEN
    MotorWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

(* a panel choice (FB_LocalControl bHaltButton): in Hand, stop where it is *)
METHOD PUBLIC Choose : BOOL
  VAR_INPUT
    eLocalChoice : E_LocalChoice;    // the local selection: Low, High, Forward, Reverse, Pos1..Pos3 or Halt
  END_VAR
  Choose := eLocalChoice = E_LocalChoice.Halt;
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
  IF __ISVALIDREF(refMotorisedData) THEN
    bHold := refMotorisedData.set.bKeepDriveAtEnd;
    bTorque := F_Protect(tNow := tNow,
                         bConditionPresent := refData.set.eMode <> E_Mode.OutOfService
                                   AND (bOpenTorqueTripped OR (bCloseTorqueTripped AND NOT (refMotorisedData.set.bSeatedOnCloseTorque AND NOT bWantOpen))),
                         bResetRequest := bResetThisScan, tRetryCountWindow := refData.set.tRetryCountWindow,
                         stSettings := refMotorisedData.set.stTorqueFault, stStatus := refMotorisedData.sts.stTorqueFault, stWorking := stWTorque);
  END_IF;
  bVarTrip := stWTorque.bTripping;    (* to the valve's protections (the next scan) *)
  bVarWarn := stWTorque.bWarning;
  IF stWTorque.bTripping OR stWTorque.bWarning THEN
    eVarError := E_UtError.TorqueSwitch;
  ELSE
    eVarError := E_UtError.None;
  END_IF;
  bDrive := bHold OR (bWantOpen AND NOT bIsOpen) OR (NOT bWantOpen AND NOT bIsClosed);
  IF bHalted OR bTorque OR NOT bActuatorRemote THEN
    bDrive := FALSE;              (* stopped where it is *)
  END_IF;
  IF __ISVALIDREF(refMotorisedData) THEN
    fbCo(bRun := bDrive, bSelectSideB := bWantOpen, bContactorFeedbackFitted := FALSE, tAToBDeadTime := refMotorisedData.set.tReversingDeadTime,
         tBToADeadTime := refMotorisedData.set.tReversingDeadTime);
  ELSE
    fbCo(bRun := FALSE);
  END_IF;
  bOpenOutput := fbCo.bSideBOutput;
  bCloseOutput := fbCo.bSideAOutput;
END_METHOD

IF __ISVALIDREF(refMotorisedData) THEN
  IF bMotorFirst THEN
    IF nKeptMotorLayout = cLayout THEN
      refMotorisedData.set := stKeptMotor;
    ELSE
      stKeptMotor := refMotorisedData.set;
      nKeptMotorLayout := cLayout;
    END_IF;
    bMotorFirst := FALSE;
  ELSIF MotorWhy() = E_UtError.None THEN
    stKeptMotor := refMotorisedData.set;
  ELSE
    refMotorisedData.sts.eSettingRefusedErrorId := MotorWhy();
    refMotorisedData.set := stKeptMotor;
    refMotorisedData.sts.bSettingRefused := TRUE;
  END_IF;
  IF bResetThisScan THEN                  // the equipment's reset clears a refused write
    refMotorisedData.sts.bSettingRefused := FALSE;
    refMotorisedData.sts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
  bSeatUse := refMotorisedData.set.bSeatedOnCloseTorque;
ELSE
  bSeatUse := FALSE;
END_IF;
bSeatMade := bCloseTorqueTripped;

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

IF __ISVALIDREF(refMotorisedData) THEN
  refMotorisedData.sts.bDriving := bOpenOutput OR bCloseOutput;
  refMotorisedData.sts.bHalted := bHalted OR stWTorque.bTripping;
END_IF;

END_FUNCTION_BLOCK