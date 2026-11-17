(* FB_SwitchSet — up to four level switches (LL, L, H, HH) on one vessel or line as switch bands, and one plain
contact (a float, a pressure or flow switch, a door), each debounced, with a quality per switch
(DESIGN-0.2.md section 5.4; src-v2 UT_SWITCH_MEAS + UT_DIGITAL_IN). Wire the instance to any I_Measurement pin:
owners read the bands through Band(E_Band.HighHigh) ...; rungs read bLowLow .. bHighHigh and bQ.

Pins: bLL, bL, bH, bHH (TRUE = the level is in that band: wire NOT at the pin for a contact that opens),
bContact, and their qualities bLLGood .. bContactGood (default TRUE: the IO module / comms are healthy)
-> bLowLow, bLow (L or LL), bHigh (H or HH), bHighHigh, bQ (the contact), bGood, plus FB_Object's bError /
bWarning / eErrorId / eState. refData: its record. stConfig: which switches are fitted and the debounce times
(engineering constants, set at the declaration).
A switch follows its input once the input has held its new state for the debounce time (power-up: at once).
A switch whose quality is bad holds its last state; after set.stInputBad it trips (SensorBad, not good).
Disagree (high and low together, HH without H, LL without L) acts per set.stDisagree (default a warning);
the switches are still reported as read. set.bFitted FALSE: not on this site (not good, no fault).
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.
A chattering contact: FB_DigitalIn's chatter check, on each switch before it reaches this block. *)

FUNCTION_BLOCK FB_SwitchSet EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    bLL : BOOL := FALSE;
    bL : BOOL;
    bH : BOOL;
    bHH : BOOL;
    bContact : BOOL;
    bLLGood : BOOL := TRUE;
    bLGood : BOOL := TRUE;
    bHGood : BOOL := TRUE;
    bHHGood : BOOL := TRUE;
    bContactGood : BOOL := TRUE;
    refData : REFERENCE TO ST_SwitchSetData;
    stConfig : ST_SwitchSetConfig; (* engineering constants (set at the declaration) *)
  END_VAR
  VAR_OUTPUT
    bLowLow : BOOL;
    bLow : BOOL; (* L or LL *)
    bHigh : BOOL; (* H or HH *)
    bHighHigh : BOOL;
    bQ : BOOL; (* the plain contact, debounced *)
    bGood : BOOL;
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


PROPERTY PUBLIC fActValue : REAL
  GET
    fActValue := 0.0;             // switches only: no continuous value
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL
  GET
    bIsGood := bGood;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL
  GET
    bHasValue := FALSE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL
  GET
    bIsFitted := bFittedNow;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit
  GET
    eUnit := E_Unit.None;         // switches only: no unit
  END_GET
END_PROPERTY
METHOD PUBLIC Band : BOOL

  VAR_INPUT
    eBand : E_Band;
  END_VAR
  CASE eBand OF
    E_Band.LowLow: Band := bLowLow;
    E_Band.Low: Band := bLow;
    E_Band.High: Band := bHigh;
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
    stD.bState := bIn;
  END_IF;
  IF NOT bInGood OR bIn = stD.bState THEN
    stD.tSince := tNow;
  ELSIF tNow - stD.tSince >= tDelay THEN
    stD.bState := bIn;
    stD.tSince := tNow;
  END_IF;
  Debounce := stD.bState;
END_METHOD

METHOD PRIVATE ProtOk : BOOL
  VAR_INPUT
    stP : REFERENCE TO ST_ProtectionSet;
  END_VAR
  ProtOk := stP.tDelay >= T#0s AND stP.tRecover >= T#0s AND stP.nMaxRetries >= 0;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_SwitchSetSet;
  END_VAR
  SetOk := ProtOk(stP := stS.stDisagree) AND ProtOk(stP := stS.stInputBad);
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bLowLow := FALSE;
  bLow := FALSE;
  bHigh := FALSE;
  bHighHigh := FALSE;
  bQ := FALSE;
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;
bOk := bOk AND stConfig.tDebounce >= T#0s AND stConfig.tContactDebounce >= T#0s
       AND stConfig.tRetryWindow >= T#0s;

bReset := SystemReset();
IF refData.bCmdReset THEN
  bReset := TRUE;
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
END_IF;
bFittedNow := refData.set.bFitted AND (stConfig.bUseLL OR stConfig.bUseL OR stConfig.bUseH OR stConfig.bUseHH
                                       OR stConfig.bUseContact);

(* the switches; one that is not fitted reads FALSE *)
sLL := Debounce(bIn := bLL, bInGood := bLLGood, tDelay := stConfig.tDebounce, stD := stDLL) AND stConfig.bUseLL;
sL := Debounce(bIn := bL, bInGood := bLGood, tDelay := stConfig.tDebounce, stD := stDL) AND stConfig.bUseL;
sH := Debounce(bIn := bH, bInGood := bHGood, tDelay := stConfig.tDebounce, stD := stDH) AND stConfig.bUseH;
sHH := Debounce(bIn := bHH, bInGood := bHHGood, tDelay := stConfig.tDebounce, stD := stDHH) AND stConfig.bUseHH;
bQ := Debounce(bIn := bContact, bInGood := bContactGood, tDelay := stConfig.tContactDebounce, stD := stDContact)
      AND stConfig.bUseContact;
IF NOT bFittedNow THEN
  sLL := FALSE;
  sL := FALSE;
  sH := FALSE;
  sHH := FALSE;
  bQ := FALSE;
END_IF;
bLowLow := sLL;
bLow := sL OR sLL;
bHigh := sH OR sHH;
bHighHigh := sHH;

(* disagree and a bad input *)
bClash := ((sH OR sHH) AND (sL OR sLL)) OR (sHH AND stConfig.bUseH AND NOT sH)
          OR (sLL AND stConfig.bUseL AND NOT sL);
bBad := (stConfig.bUseLL AND NOT bLLGood) OR (stConfig.bUseL AND NOT bLGood) OR (stConfig.bUseH AND NOT bHGood)
        OR (stConfig.bUseHH AND NOT bHHGood) OR (stConfig.bUseContact AND NOT bContactGood);
bTripD := F_Protect(tNow := tNow, bCause := bClash AND bOk AND bFittedNow, bResetReq := bReset,
                    tRetryWindow := stConfig.tRetryWindow, stSet := refData.set.stDisagree,
                    stSts := refData.sts.stDisagree, stWork := stWDisagree);
bTripB := F_Protect(tNow := tNow, bCause := bBad AND bOk AND bFittedNow, bResetReq := bReset,
                    tRetryWindow := stConfig.tRetryWindow, stSet := refData.set.stInputBad,
                    stSts := refData.sts.stInputBad, stWork := stWInputBad);
bSignal := stWDisagree.bSignal OR stWInputBad.bSignal;
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
bWarning := NOT bError AND ((bFittedNow AND ((bBad AND NOT stWInputBad.bSignal)
                                             OR (bClash AND NOT stWDisagree.bSignal)
                                             OR stWDisagree.bBadSetting OR stWInputBad.bBadSetting))
                            OR refData.sts.bRefused);

IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bTripD OR bTripB THEN
  eErrorId := eFirst;
ELSIF bWarning AND bBad THEN
  eErrorId := E_UtError.SensorBad;
ELSIF bWarning AND bClash THEN
  eErrorId := E_UtError.SwitchDisagree;
ELSIF bWarning AND (stWDisagree.bBadSetting OR stWInputBad.bBadSetting) THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
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
refData.sts.bLow := bLow;
refData.sts.bHigh := bHigh;
refData.sts.bHighHigh := bHighHigh;
refData.sts.bContact := bQ;
refData.sts.bGood := bGood;
bFirstScan := FALSE;

END_FUNCTION_BLOCK