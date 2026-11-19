(* FB_Route — the outlet selector (up to 4 outlet valves): which outlet the pumps deliver to, valve first, the
wet-weather divert to storage, an irrigator blocked.
Pins: bLevelPumping (level pumping chooses the route), nRunOutlet (the outlet of a run / the zone watering, 1..4; > 0
also asks for it), bWaterRequested (water wanted: a pump is asked or in Hand), bPumpRunning (never close under it; the
close delay starts when it drops), bSendToStorage (wet weather: FB_IrrDefer), bStorageFull, bIrrigatorTripped (the
irrigator's fail-safe tripped), ipValve1..4 (each outlet's valve, I_Equipment; NULL = not fitted), refData
-> nOutletInUse (in use, 0 none), bRouteProven (proven: -> the pumps' start hold), bRouteLost (-> the pumps' interlock),
bIrrigationOutletInUse, bStorageOutletInUse, nSpeedPreset (the outlet's speed preset; -1 = the speed control's own), plus FB_Object's
outputs.
The outlet in use: nRunOutlet 1..4 (never diverted; outside 0..4 refused, a warning) -> else bLevelPumping ->
set.nLevelPumpingOutlet (an Irrigation outlet: with bSendToStorage or bIrrigatorTripped -> set.nStorageOutlet while it is set,
fitted and not full ("diverted"); with bSendToStorage and no storage it stays, warning NoStorage; with bIrrigatorTripped and
no storage nothing opens: RouteBlocked) -> else set.nRunOutlet (Hand, manual runs, zones that own their valves).
While bWaterRequested OR bPumpRunning OR nRunOutlet > 0 the outlet in use gets Request(open) and every other outlet with a
kind Request(closed), every scan (one owner); kind None is never requested. Valve first: bRouteProven once the outlet
in use is open (its bIsRunning). An outlet change: the old outlet is released set.tValveCloseDelay after the new one is
proven; the last proven outlet is never released under a running pump; the request gone: released tValveCloseDelay
after the pumps stop. bRouteLost: a pump runs and no held outlet is open, or the outlet in use is blocked. Valves
move only in their own Auto (else warning NotAuto); proof in any mode. Every kind None = routing not used,
bRouteProven TRUE. Settings are kept (a retained last-good copy, a bad write put back). *)

FUNCTION_BLOCK FB_Route EXTENDS FB_Object
  VAR_INPUT
    bLevelPumping : BOOL := FALSE; (* level pumping chooses the route *)
    nRunOutlet : INT; (* the outlet of a run or the zone watering, 1..4; above 0 also asks for it *)
    bWaterRequested : BOOL; (* water wanted: a pump is asked or in Hand *)
    bPumpRunning : BOOL; (* a pump runs: never close under it; the close delay starts when it drops *)
    bSendToStorage : BOOL; (* wet weather (FB_IrrDefer.bSendToStorage) *)
    bStorageFull : BOOL; (* the storage is full: no divert to it *)
    bIrrigatorTripped : BOOL; (* the irrigator's fail-safe tripped *)
    ipValve1 : I_Equipment; (* outlet 1's valve *)
    ipValve2 : I_Equipment; (* outlet 2's valve *)
    ipValve3 : I_Equipment; (* outlet 3's valve *)
    ipValve4 : I_Equipment; (* outlet 4's valve *)
    refData : REFERENCE TO ST_RouteData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    nOutletInUse : INT; (* the outlet in use (0 = none) *)
    bRouteProven : BOOL; (* the route is proven open: to the pumps' start hold *)
    bRouteLost : BOOL; (* to the pumps' interlock *)
    bIrrigationOutletInUse : BOOL; (* the outlet in use is an irrigation outlet *)
    bStorageOutletInUse : BOOL; (* the outlet in use is the storage *)
    nSpeedPreset : INT := -1; (* the outlet's speed preset; -1 = the speed control's own *)
  END_VAR
  VAR RETAIN
    stKept : ST_RouteSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    nHoldMask : BYTE;
    nPrevMask : BYTE;
    tRelSince : TIME;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    aV : ARRAY [1..4] OF I_EQUIPMENT;
    aFitted : ARRAY [1..4] OF BOOL;
    aIsOpen : ARRAY [1..4] OF BOOL;
    nK : INT;
    bUsed : BOOL;
    nOut : INT;
    bPurposeBad : BOOL;
    bStOk : BOOL;
    bDiverted : BOOL;
    bNoStorage : BOOL;
    bBlocked : BOOL;
    bRefusedNo : BOOL;
    bRequesting : BOOL;
    nReqMask : BYTE;
    nBit : BYTE;
    bOutProven : BOOL;
    bRelCond : BOOL;
    bAnyHeldOpen : BOOL;
    bNotAuto : BOOL;
    bOutFault : BOOL;
    bOtherFault : BOOL;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_RouteSet;
  END_VAR
  VAR
    nI : INT;
  END_VAR
  SetWhy := E_UtError.None;
  IF stS.nLevelPumpingOutlet > 4 OR stS.nRunOutlet > 4 OR stS.nStorageOutlet > 4 THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF stS.tValveCloseDelay < T#0s OR stS.tValveCloseDelay > T#10m THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
  FOR nI := 1 TO 4 DO
    IF SetWhy <> E_UtError.None THEN
      ;
    ELSIF NOT (stS.aOutlets[nI].eOutletKind = E_OutletKind.None OR stS.aOutlets[nI].eOutletKind = E_OutletKind.Irrigation
               OR stS.aOutlets[nI].eOutletKind = E_OutletKind.Storage OR stS.aOutlets[nI].eOutletKind = E_OutletKind.Other) THEN
      SetWhy := E_UtError.ChoiceBad;
    ELSIF stS.aOutlets[nI].nSpeedPreset < -1 THEN
      SetWhy := E_UtError.BelowMin;
    ELSIF stS.aOutlets[nI].nSpeedPreset > 2 THEN
      SetWhy := E_UtError.AboveMax;
    END_IF;
  END_FOR;
  IF SetWhy = E_UtError.None AND stS.nStorageOutlet >= 1 AND stS.nStorageOutlet <= 4 THEN
    IF stS.aOutlets[stS.nStorageOutlet].eOutletKind <> E_OutletKind.Storage THEN
      SetWhy := E_UtError.ChoiceBad;       // the storage outlet is not of kind Storage
    END_IF;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_RouteSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bRouteProven := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
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
IF SystemReset() THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* the outlets *)
aV[1] := ipValve1;
aV[2] := ipValve2;
aV[3] := ipValve3;
aV[4] := ipValve4;
bUsed := FALSE;
FOR nK := 1 TO 4 DO
  aFitted[nK] := aV[nK] <> NULL;
  aIsOpen[nK] := FALSE;
  IF aV[nK] <> NULL THEN
    aIsOpen[nK] := aV[nK].bIsRunning;   (* a valve "runs" while open *)
  END_IF;
  IF refData.set.aOutlets[nK].eOutletKind <> E_OutletKind.None THEN
    bUsed := TRUE;
  END_IF;
END_FOR;

(* which outlet *)
nOut := 0;
bPurposeBad := FALSE;
bDiverted := FALSE;
bNoStorage := FALSE;
bRefusedNo := FALSE;
bStOk := FALSE;
IF refData.set.nStorageOutlet >= 1 AND refData.set.nStorageOutlet <= 4 THEN
  bStOk := refData.set.aOutlets[refData.set.nStorageOutlet].eOutletKind = E_OutletKind.Storage
           AND aFitted[refData.set.nStorageOutlet];
END_IF;
IF nRunOutlet >= 1 AND nRunOutlet <= 4 THEN
  nOut := nRunOutlet;
ELSIF nRunOutlet <> 0 THEN
  bRefusedNo := TRUE;             (* e.g. zone 5 on a 4-outlet route *)
ELSIF bLevelPumping THEN
  nOut := USINT_TO_INT(refData.set.nLevelPumpingOutlet);
  IF nOut >= 1 AND nOut <= 4 THEN
    IF refData.set.aOutlets[nOut].eOutletKind = E_OutletKind.Irrigation AND (bSendToStorage OR bIrrigatorTripped) THEN
      IF bStOk AND NOT bStorageFull THEN
        nOut := USINT_TO_INT(refData.set.nStorageOutlet);
        bDiverted := TRUE;
      ELSIF bSendToStorage AND NOT bIrrigatorTripped THEN
        bNoStorage := TRUE;       (* an overflow is the worse breach: stay *)
      END_IF;
    END_IF;
  END_IF;
ELSE
  nOut := USINT_TO_INT(refData.set.nRunOutlet);
END_IF;
IF nOut > 4 THEN
  nOut := 0;
  bPurposeBad := TRUE;
END_IF;
IF nOut >= 1 AND bUsed THEN
  IF refData.set.aOutlets[nOut].eOutletKind = E_OutletKind.None OR NOT aFitted[nOut] THEN
    bPurposeBad := TRUE;
  END_IF;
END_IF;
bBlocked := FALSE;
IF nOut >= 1 AND NOT bPurposeBad THEN
  bBlocked := refData.set.aOutlets[nOut].eOutletKind = E_OutletKind.Irrigation AND bIrrigatorTripped;
END_IF;
IF NOT bUsed THEN
  nOut := 0;
END_IF;

(* the requests: the outlet in use open, the others held until the release *)
bRequesting := bWaterRequested OR bPumpRunning OR nRunOutlet > 0;
bOutProven := FALSE;
IF nOut >= 1 AND NOT bPurposeBad AND NOT bBlocked THEN
  bOutProven := aIsOpen[nOut];
END_IF;
nReqMask := BYTE#0;
IF bRequesting AND nOut >= 1 AND NOT bPurposeBad AND NOT bBlocked THEN
  nReqMask := SHL(BYTE#1, nOut - 1);
END_IF;
IF nReqMask <> nPrevMask THEN
  tRelSince := tNow;              (* the delay counts from the request ending, not from the opening *)
  nPrevMask := nReqMask;
END_IF;
bRelCond := (bRequesting AND bOutProven) OR (NOT bRequesting AND NOT bPumpRunning) OR bBlocked
            OR (bRequesting AND nOut = 0);
IF NOT bRelCond THEN
  tRelSince := tNow;
END_IF;
IF bRelCond AND tNow - tRelSince >= refData.set.tValveCloseDelay THEN
  nHoldMask := BYTE#0;
END_IF;
nHoldMask := nHoldMask AND NOT nReqMask;
bAnyHeldOpen := FALSE;
bNotAuto := FALSE;
bOutFault := FALSE;
bOtherFault := FALSE;
refData.sts.nFaultedOutlet := 0;
refData.sts.nProvenOpenBits := BYTE#0;
FOR nK := 1 TO 4 DO
  nBit := SHL(BYTE#1, nK - 1);
  IF aIsOpen[nK] THEN
    refData.sts.nProvenOpenBits := refData.sts.nProvenOpenBits OR nBit;
  END_IF;
  IF refData.set.aOutlets[nK].eOutletKind <> E_OutletKind.None AND aFitted[nK] THEN
    aV[nK].Request(bRun := ((nReqMask OR nHoldMask) AND nBit) <> BYTE#0, bHoldOff := FALSE);
    IF ((nReqMask OR nHoldMask) AND nBit) <> BYTE#0 AND aIsOpen[nK] THEN
      bAnyHeldOpen := TRUE;
    END_IF;
    IF nK = nOut AND bRequesting AND NOT aV[nK].bIsAuto THEN
      bNotAuto := TRUE;
    END_IF;
    IF nK = nOut AND aV[nK].bIsFaulted THEN
      bOutFault := TRUE;
      refData.sts.nFaultedOutlet := INT_TO_USINT(nK);
    ELSIF nK <> nOut AND aV[nK].bIsFaulted THEN
      bOtherFault := TRUE;
    END_IF;
  END_IF;
END_FOR;
nHoldMask := nHoldMask OR nReqMask;   (* what is requested now is held until a release *)

(* proof *)
IF NOT bUsed THEN
  bRouteProven := TRUE;
ELSIF bRefusedNo OR bPurposeBad OR bBlocked OR NOT bOk THEN
  bRouteProven := FALSE;
ELSIF nOut = 0 THEN
  bRouteProven := TRUE;
ELSE
  bRouteProven := bOutProven;
END_IF;
bRouteLost := bUsed AND bPumpRunning AND nOut >= 1 AND (bBlocked OR NOT bAnyHeldOpen);

(* outputs *)
nOutletInUse := nOut;
bIrrigationOutletInUse := FALSE;
bStorageOutletInUse := FALSE;
nSpeedPreset := -1;
refData.sts.eOutletKindInUse := E_OutletKind.None;
IF nOut >= 1 THEN
  refData.sts.eOutletKindInUse := refData.set.aOutlets[nOut].eOutletKind;
  bIrrigationOutletInUse := refData.set.aOutlets[nOut].eOutletKind = E_OutletKind.Irrigation;
  bStorageOutletInUse := refData.set.aOutlets[nOut].eOutletKind = E_OutletKind.Storage;
  nSpeedPreset := SINT_TO_INT(refData.set.aOutlets[nOut].nSpeedPreset);
END_IF;
IF (nHoldMask AND NOT nReqMask) <> BYTE#0 AND bRelCond AND refData.set.tValveCloseDelay > tNow - tRelSince THEN
  refData.sts.tTimeLeft := refData.set.tValveCloseDelay - (tNow - tRelSince);
ELSE
  refData.sts.tTimeLeft := T#0s;
END_IF;
refData.sts.nOutletInUse := INT_TO_USINT(nOut);
refData.sts.nOpenRequestedBits := nHoldMask;
refData.sts.bRouteProven := bRouteProven;
refData.sts.bRouteLost := bRouteLost;
refData.sts.bOpening := bRequesting AND nOut >= 1 AND NOT bOutProven;
refData.sts.bClosing := (nHoldMask AND NOT nReqMask) <> BYTE#0;
refData.sts.bDivertedToStorage := bDiverted;
refData.sts.bNoStorageAvailable := bNoStorage;
refData.sts.bRouteBlocked := bBlocked OR (bLevelPumping AND bIrrigatorTripped AND NOT bDiverted AND nRunOutlet = 0);

(* errors *)
bError := bUsed AND (bOutFault OR bPurposeBad OR bRouteLost OR NOT bOk);
bWarning := NOT bError AND (bNoStorage OR bNotAuto OR bOtherFault OR bRefusedNo OR refData.sts.bRouteBlocked
                            OR refData.sts.bSettingRefused);
IF NOT bOk OR bPurposeBad THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bRouteLost THEN
  eErrorId := E_UtError.RouteLost;
ELSIF bOutFault THEN
  eErrorId := E_UtError.ConditionOut;
ELSIF refData.sts.bRouteBlocked THEN
  eErrorId := E_UtError.RouteBlocked;
ELSIF bRefusedNo THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bNoStorage THEN
  eErrorId := E_UtError.NoStorage;
ELSIF bNotAuto THEN
  eErrorId := E_UtError.NotAuto;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bUsed OR NOT bRequesting THEN
  eState := E_State.Idle;
ELSIF NOT bRouteProven THEN
  eState := E_State.Starting;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK