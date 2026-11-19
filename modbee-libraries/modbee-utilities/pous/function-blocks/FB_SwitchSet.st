(* FB_SwitchSet — up to four level switches (LL, L, H, HH) on one vessel or line as switch bands, and one plain
contact (a float, a pressure or flow switch, a door), each debounced, with a quality per switch. Wire the instance
to any I_Measurement pin: owners read the bands through Band(E_Band.HighHigh) ...; rungs read bLowLow .. bHighHigh
and bContactDebounced.

Pins: bLowLowSwitch, bLowSwitch, bHighSwitch, bHighHighSwitch (TRUE = the level is in that band: wire NOT at the pin for a contact that opens),
bContact, and their qualities bLowLowSwitchGood .. bContactGood (default TRUE: the IO module / comms are healthy)
-> bLowLow, bLowOrBelow (L or LL), bHighOrAbove (H or HH), bHighHigh, bContactDebounced (the contact), bGood, plus FB_Object's bError /
bWarning / eErrorId / eState. refData: its record. stConfig: which switches are fitted and the debounce times
(engineering constants, set at the declaration).
A switch follows its input once the input has held its new state for the debounce time (power-up: at once).
A switch whose quality is bad holds its last state; after set.stInputBadFault it trips (SensorBad, not good).
Disagree (high and low together, HH without H, LL without L) acts per set.stSwitchOrderFault (default a warning);
the switches are still reported as read. set.bSensorFitted FALSE: not on this site (not good, no fault).
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.
A chattering contact: FB_DigitalIn's chatter check, on each switch before it reaches this block. *)

FUNCTION_BLOCK FB_SwitchSet EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    bLowLowSwitch : BOOL := FALSE; (* the low-low switch (TRUE = the level is in that band; NOT at the pin for a contact that opens) *)
    bLowSwitch : BOOL; (* the low switch (TRUE = in that band) *)
    bHighSwitch : BOOL; (* the high switch (TRUE = in that band) *)
    bHighHighSwitch : BOOL; (* the high-high switch (TRUE = in that band) *)
    bContact : BOOL; (* a plain contact (a float, a pressure or flow switch, a door) *)
    bLowLowSwitchGood : BOOL := TRUE; (* the low-low switch's input is healthy *)
    bLowSwitchGood : BOOL := TRUE; (* the low switch's input is healthy *)
    bHighSwitchGood : BOOL := TRUE; (* the high switch's input is healthy *)
    bHighHighSwitchGood : BOOL := TRUE; (* the high-high switch's input is healthy *)
    bContactGood : BOOL := TRUE; (* the contact's input is healthy (IO module, comms) *)
    refData : REFERENCE TO ST_SwitchSetData; (* the block's record *)
    stConfig : ST_SwitchSetConfig; (* engineering constants (set at the declaration) *)
  END_VAR
  VAR_OUTPUT
    bLowLow : BOOL; (* the low-low switch / level *)
    bLowOrBelow : BOOL; (* L or LL *)
    bHighOrAbove : BOOL; (* H or HH *)
    bHighHigh : BOOL; (* the high-high switch / level *)
    bGood : BOOL; (* the switches can be trusted *)
    bContactDebounced : BOOL; (* the plain contact, debounced *)
  END_VAR
  VAR RETAIN
    stKept : ST_SwitchSetSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    stDLL : ST_SwitchDebounce;
    stDL : ST_SwitchDebounce;
    stDH : ST_SwitchDebounce;
    stDHH : ST_SwitchDebounce;
    stDContact : ST_SwitchDebounce;
    stWDisagree : ST_ProtectionWork;
    stWInputBad : ST_ProtectionWork;
    bFittedNow : BOOL;
    bTripWas : BOOL;
    eFirst : E_UtError; (* the cause when it tripped (first-out) *)
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bReset : BOOL;
    sLL : BOOL;
    sL : BOOL;
    sH : BOOL;
    sHH : BOOL;
    bClash : BOOL;
    bBad : BOOL;
    bTripD : BOOL;
    bTripB : BOOL;
    bSignal : BOOL;
  END_VAR


PROPERTY PUBLIC fActValue : REAL    // the value in its unit (held at the last good one while bad, when so set)
  GET
    fActValue := 0.0;             // switches only: no continuous value
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL    // the value can be trusted now
  GET
    bIsGood := bGood;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL    // a continuous value (FALSE: switches only)
  GET
    bHasValue := FALSE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL    // the sensor is on this site (FALSE: no value, no bands, no fault)
  GET
    bIsFitted := bFittedNow;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit    // the unit of the value
  GET
    eUnit := E_Unit.None;         // switches only: no unit
  END_GET
END_PROPERTY
METHOD PUBLIC Band : BOOL

  VAR_INPUT
    eBand : E_Band;    // the band asked about (LowLow, Low, High, HighHigh); returns TRUE while the value is in it
  END_VAR
  CASE eBand OF
    E_Band.LowLow: Band := bLowLow;
    E_Band.Low: Band := bLowOrBelow;
    E_Band.High: Band := bHighOrAbove;
    E_Band.HighHigh: Band := bHighHigh;
  ELSE
    Band := FALSE;
  END_CASE;
END_METHOD

(* one switch: follows its input once the input has held for tDelay; a bad quality holds it *)
METHOD PRIVATE Debounce : BOOL
  VAR_INPUT
    bIn : BOOL;
    bInGood : BOOL;
    tDelay : TIME;
  END_VAR
  VAR_IN_OUT
    stD : ST_SwitchDebounce;
  END_VAR
  IF bFirstScan AND bInGood THEN
    stD.bDebouncedState := bIn;
  END_IF;
  IF NOT bInGood OR bIn = stD.bDebouncedState THEN
    stD.tDifferentAt := tNow;
  ELSIF tNow - stD.tDifferentAt >= tDelay THEN
    stD.bDebouncedState := bIn;
    stD.tDifferentAt := tNow;
  END_IF;
  Debounce := stD.bDebouncedState;
END_METHOD

METHOD PRIVATE ProtOk : BOOL
  VAR_INPUT
    stP : REFERENCE TO ST_ProtectionSet;
  END_VAR
  ProtOk := stP.tTripDelay >= T#0s AND stP.tAutoRecoverAfter >= T#0s AND stP.nMaxRetriesBeforeLockout >= 0;
END_METHOD

METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_SwitchSetSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (ProtOk(stP := stS.stSwitchOrderFault)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (ProtOk(stP := stS.stInputBadFault)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_SwitchSetSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bLowLow := FALSE;
  bLowOrBelow := FALSE;
  bHighOrAbove := FALSE;
  bHighHigh := FALSE;
  bContactDebounced := FALSE;
  bGood := FALSE;
  bFittedNow := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();

(* kept settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
bOk := bOk AND stConfig.tLevelSwitchDebounceTime >= T#0s AND stConfig.tContactDebounceTime >= T#0s;

bReset := SystemReset();
IF refData.bCmdResetFaults THEN
  bReset := TRUE;
  refData.bCmdResetFaults := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
bFittedNow := refData.set.bSensorFitted AND (stConfig.bLowLowSwitchFitted OR stConfig.bLowSwitchFitted OR stConfig.bHighSwitchFitted OR stConfig.bHighHighSwitchFitted
                                       OR stConfig.bContactFitted);

(* the switches; one that is not fitted reads FALSE *)
sLL := Debounce(bIn := bLowLowSwitch, bInGood := bLowLowSwitchGood, tDelay := stConfig.tLevelSwitchDebounceTime, stD := stDLL) AND stConfig.bLowLowSwitchFitted;
sL := Debounce(bIn := bLowSwitch, bInGood := bLowSwitchGood, tDelay := stConfig.tLevelSwitchDebounceTime, stD := stDL) AND stConfig.bLowSwitchFitted;
sH := Debounce(bIn := bHighSwitch, bInGood := bHighSwitchGood, tDelay := stConfig.tLevelSwitchDebounceTime, stD := stDH) AND stConfig.bHighSwitchFitted;
sHH := Debounce(bIn := bHighHighSwitch, bInGood := bHighHighSwitchGood, tDelay := stConfig.tLevelSwitchDebounceTime, stD := stDHH) AND stConfig.bHighHighSwitchFitted;
bContactDebounced := Debounce(bIn := bContact, bInGood := bContactGood, tDelay := stConfig.tContactDebounceTime, stD := stDContact)
      AND stConfig.bContactFitted;
IF NOT bFittedNow THEN
  sLL := FALSE;
  sL := FALSE;
  sH := FALSE;
  sHH := FALSE;
  bContactDebounced := FALSE;
END_IF;
bLowLow := sLL;
bLowOrBelow := sL OR sLL;
bHighOrAbove := sH OR sHH;
bHighHigh := sHH;

(* disagree and a bad input *)
bClash := ((sH OR sHH) AND (sL OR sLL)) OR (sHH AND stConfig.bHighSwitchFitted AND NOT sH)
          OR (sLL AND stConfig.bLowSwitchFitted AND NOT sL);
bBad := (stConfig.bLowLowSwitchFitted AND NOT bLowLowSwitchGood) OR (stConfig.bLowSwitchFitted AND NOT bLowSwitchGood) OR (stConfig.bHighSwitchFitted AND NOT bHighSwitchGood)
        OR (stConfig.bHighHighSwitchFitted AND NOT bHighHighSwitchGood) OR (stConfig.bContactFitted AND NOT bContactGood);
bTripD := F_Protect(tNow := tNow, bConditionPresent := bClash AND bOk AND bFittedNow, bResetRequest := bReset,
                    tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stSwitchOrderFault,
                    stStatus := refData.sts.stSwitchOrderFault, stWorking := stWDisagree);
bTripB := F_Protect(tNow := tNow, bConditionPresent := bBad AND bOk AND bFittedNow, bResetRequest := bReset,
                    tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stInputBadFault,
                    stStatus := refData.sts.stInputBadFault, stWorking := stWInputBad);
bSignal := stWDisagree.bSignalling OR stWInputBad.bSignalling;
bGood := bOk AND bFittedNow AND NOT bTripD AND NOT bTripB AND NOT bSignal;

(* errors *)
IF (bTripD OR bTripB) AND NOT bTripWas THEN
  IF bTripB THEN
    eFirst := E_UtError.SensorBad;
  ELSE
    eFirst := E_UtError.SwitchDisagree;
  END_IF;
END_IF;
bTripWas := bTripD OR bTripB;
bError := NOT bOk OR bTripD OR bTripB;
bWarning := NOT bError AND ((bFittedNow AND ((bBad AND NOT stWInputBad.bSignalling)
                                             OR (bClash AND NOT stWDisagree.bSignalling)
                                             OR stWDisagree.bSettingBad OR stWInputBad.bSettingBad))
                            OR refData.sts.bSettingRefused);

IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bTripD OR bTripB THEN
  eErrorId := eFirst;
ELSIF bWarning AND bBad THEN
  eErrorId := E_UtError.SensorBad;
ELSIF bWarning AND bClash THEN
  eErrorId := E_UtError.SwitchDisagree;
ELSIF bWarning AND (stWDisagree.bSettingBad OR stWInputBad.bSettingBad) THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bFittedNow THEN
  eState := E_State.Off;
ELSIF bBad OR bSignal THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;

refData.sts.bLowLow := bLowLow;
refData.sts.bLowOrBelow := bLowOrBelow;
refData.sts.bHighOrAbove := bHighOrAbove;
refData.sts.bHighHigh := bHighHigh;
refData.sts.bContact := bContactDebounced;
refData.sts.bGood := bGood;
bFirstScan := FALSE;

END_FUNCTION_BLOCK