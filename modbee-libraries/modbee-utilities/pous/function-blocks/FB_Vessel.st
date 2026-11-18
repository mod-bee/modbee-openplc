(* FB_Vessel — a tank, sump, silo or pond: its volume, % full, free space, mass and surface area from a level
measurement. Wire the instance to any I_Vessel or I_Measurement pin: its value is the level, its bands are the
level's bands.

Pins: ipLevel (the level measurement, e.g. an FB_AnalogIn) -> fVolume, fPercent (of the full working
volume), bGood, plus FB_Object's bError / bWarning / eErrorId / eState. refData: its record. stConfig: the
shape and the units (engineering constants, set at the declaration).
One shape x stConfig.nTanks identical tanks joined at the bottom (the same level in each):
  Vertical    flat-bottom vertical cylinder: fDiameter, fHeight
  Cone        a hopper (fConeHeight, from fOutletDiameter up to fDiameter) under a cylinder of fHeight
  Horizontal  horizontal cylinder with flat ends: fDiameter, fLength
  Rect        fLength, fWidth, fHeight
  Sphere      fDiameter
  Pond        sloped banks: floor fLength x fWidth, depth fHeight, bank fSlope (horizontal per 1 vertical,
              e.g. 3 for 3:1; 0 = Rect)
  Table       any shape from a level table: wire an FB_Linearise of the level (level -> volume, in eVolumeUnit)
              to fTableVol and, optional, one (level -> area, m2) to fTableArea; stConfig.fTableFull is the
              volume when full, fHeight the level when full
The level unit: stConfig.eLevelUnit when it is set; None (the default) takes the level's own unit
(ipLevel.eUnit), and a level with no unit set reads as Metre. A level unit other than Metre, Cm, Mm or
Percent is BadSetting. The vessel's eUnit is the level unit in use.
Units: the dimensions are in metres. The level, set.fLevelOffset and set.fPctLow / fPctHigh are in the level
unit (Metre, Cm, Mm; Percent = % of the full height). Volumes in eVolumeUnit (M3, Litre,
MegaLitre), the mass in eMassUnit (Kg, Tonne) from fDensity (kg/m3). fFraction: the share of the vessel
(0.5 = half a divided silo). set.fDeadVolume (in eVolumeUnit) is taken off the volume and the full volume.
A level above the top reads full (sts.bOverfull). A bad level holds the outputs (not good, no alarm: the
measurement raises its own); a level that is not fitted makes the vessel not fitted.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Vessel EXTENDS FB_Object IMPLEMENTS I_Vessel
  VAR_INPUT
    ipLevel : I_Measurement; (* required *)
    refData : REFERENCE TO ST_VesselData;
    stConfig : ST_VesselConfig; (* engineering constants (set at the declaration) *)
    fTableVol : REAL; (* Table: the volume at the present level, in eVolumeUnit (an FB_Linearise) *)
    fTableArea : REAL; (* Table: the surface area at the present level, m2 (an FB_Linearise; optional) *)
  END_VAR
  VAR_OUTPUT
    fVolume : REAL; (* in eVolumeUnit, after the dead volume *)
    fPercent : REAL; (* of the full working volume *)
    bGood : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_VesselSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
    cPi : REAL := 3.14159265;
    cBig : REAL := 1.0E30;
  END_VAR
  VAR
    fLevel : REAL; (* the level as read (held while bad) *)
    fFull : REAL; (* full working volume, eVolumeUnit *)
    bFittedNow : BOOL;
    bHaveGood : BOOL;
    eLevelUnitNow : E_Unit; (* the level unit in use *)
    fTVol : REAL;
    fTFull : REAL;
    fTArea : REAL;
    fTTop : REAL;
    bTOver : BOOL;
    fCVol : REAL;
    fCFull : REAL;
    fCArea : REAL;
    fCPct : REAL;
    bCOver : BOOL;
    eCalcWhy : E_UtError; (* why Calc failed (None: it worked) *)
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    eWhy : E_UtError; (* why this scan's write is bad *)
    bHave : BOOL;
    bLvlGood : BOOL;
    fLvl : REAL;
    fVk : REAL;
    fMk : REAL;
  END_VAR


PROPERTY PUBLIC fActValue : REAL
  GET
    fActValue := fLevel;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL
  GET
    bIsGood := bGood;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL
  GET
    bIsFitted := bFittedNow;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActVolume : REAL
  GET
    fActVolume := fVolume;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActPercent : REAL
  GET
    fActPercent := fPercent;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fFullVolume : REAL
  GET
    fFullVolume := fFull;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit
  GET
    eUnit := eLevelUnitNow;
  END_GET
END_PROPERTY
(* the level's own bands *)

METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;
  END_VAR
  IF ipLevel <> NULL THEN
    Band := ipLevel.Band(eBand := eBand);
  ELSE
    Band := FALSE;
  END_IF;
END_METHOD

(* one tank at level fH (m): fTVol, fTFull (m3), fTArea (m2), fTTop (m), bTOver; FALSE: unusable geometry *)
METHOD PRIVATE Tank : BOOL
  VAR_INPUT
    fH : REAL;                    // level from the bottom, m
    fVolK : REAL;                 // m3 to eVolumeUnit (the Table shape's pins are in eVolumeUnit)
  END_VAR
  VAR
    fD : REAL;
    fR : REAL;
    fHt : REAL;
    fL : REAL;
    fW : REAL;
    fCone : REAL;
    fROut : REAL;
    fRAt : REAL;
    fA : REAL;
    fConeFull : REAL;
    fC : REAL;
    fS : REAL;
    fLv : REAL;
    bGeomOk : BOOL;
  END_VAR
  fD := stConfig.fDiameter;
  fR := fD / 2.0;
  fHt := stConfig.fHeight;
  fL := stConfig.fLength;
  fW := stConfig.fWidth;
  fCone := stConfig.fConeHeight;
  fS := stConfig.fSlope;
  CASE stConfig.eShape OF
    E_VesselShape.Vertical:
      bGeomOk := fD > 0.0 AND fD <= cBig AND fHt > 0.0 AND fHt <= cBig;
      fTTop := fHt;
    E_VesselShape.Cone:
      fROut := stConfig.fOutletDiameter / 2.0;
      bGeomOk := fD > 0.0 AND fD <= cBig AND fHt >= 0.0 AND fHt <= cBig AND fCone >= 0.0 AND fCone <= cBig
             AND fROut >= 0.0 AND fROut <= fR AND (fHt > 0.0 OR fCone > 0.0);
      fTTop := fCone + fHt;
    E_VesselShape.Horizontal:
      bGeomOk := fD > 0.0 AND fD <= cBig AND fL > 0.0 AND fL <= cBig;
      fTTop := fD;
    E_VesselShape.Rect:
      bGeomOk := fL > 0.0 AND fL <= cBig AND fW > 0.0 AND fW <= cBig AND fHt > 0.0 AND fHt <= cBig;
      fTTop := fHt;
    E_VesselShape.Sphere:
      bGeomOk := fD > 0.0 AND fD <= cBig;
      fTTop := fD;
    E_VesselShape.Pond:
      bGeomOk := fL > 0.0 AND fL <= cBig AND fW > 0.0 AND fW <= cBig AND fHt > 0.0 AND fHt <= cBig
             AND fS >= 0.0 AND fS <= 100.0;
      fTTop := fHt;
    E_VesselShape.Table:
      bGeomOk := fHt > 0.0 AND fHt <= cBig AND stConfig.fTableFull > 0.0 AND stConfig.fTableFull <= cBig
             AND fVolK > 0.0 AND fTableVol >= 0.0 AND fTableVol <= cBig AND fTableArea >= 0.0 AND fTableArea <= cBig;
      fTTop := fHt;
  ELSE
    bGeomOk := FALSE;
    fTTop := 0.0;
  END_CASE;
  IF NOT bGeomOk OR NOT (ABS(fH) <= 3.4E38) THEN
    fTVol := 0.0;
    fTFull := 0.0;
    fTArea := 0.0;
    bTOver := FALSE;
    Tank := FALSE;
    RETURN;
  END_IF;
  fLv := fH;
  bTOver := fLv > fTTop;
  IF fLv > fTTop THEN fLv := fTTop; END_IF;
  IF fLv < 0.0 THEN fLv := 0.0; END_IF;
  CASE stConfig.eShape OF
    E_VesselShape.Cone:
      fA := cPi * fR * fR;
      fConeFull := cPi * fCone / 3.0 * (fROut * fROut + fROut * fR + fR * fR);
      fTFull := fConeFull + fA * fHt;
      IF fCone > 0.0 AND fLv <= fCone THEN
        fRAt := fROut + (fR - fROut) * fLv / fCone;
        fTVol := cPi * fLv / 3.0 * (fROut * fROut + fROut * fRAt + fRAt * fRAt);
        fTArea := cPi * fRAt * fRAt;
      ELSE
        fTVol := fConeFull + fA * (fLv - fCone);
        fTArea := fA;
      END_IF;
    E_VesselShape.Horizontal:
      fTFull := cPi * fR * fR * fL;
      fC := (fR - fLv) / fR;
      IF fC > 1.0 THEN fC := 1.0; ELSIF fC < -1.0 THEN fC := -1.0; END_IF;
      fTVol := (fR * fR * ACOS(fC) - (fR - fLv) * SQRT(MAX(0.0, 2.0 * fR * fLv - fLv * fLv))) * fL;
      fTArea := 2.0 * SQRT(MAX(0.0, fLv * (fD - fLv))) * fL;
    E_VesselShape.Rect:
      fTFull := fL * fW * fHt;
      fTVol := fL * fW * fLv;
      fTArea := fL * fW;
    E_VesselShape.Sphere:
      fTFull := 4.0 / 3.0 * cPi * fR * fR * fR;
      fTVol := cPi * fLv * fLv * (3.0 * fR - fLv) / 3.0;
      fTArea := cPi * fLv * (fD - fLv);
    E_VesselShape.Table:
      fTFull := stConfig.fTableFull / fVolK;   // m3
      fTVol := MIN(fTableVol / fVolK, fTFull);
      fTArea := fTableArea;
    E_VesselShape.Pond:
      fTFull := fL * fW * fHt + (fL + fW) * fS * fHt * fHt + 4.0 / 3.0 * fS * fS * fHt * fHt * fHt;
      fTVol := fL * fW * fLv + (fL + fW) * fS * fLv * fLv + 4.0 / 3.0 * fS * fS * fLv * fLv * fLv;
      fTArea := (fL + 2.0 * fS * fLv) * (fW + 2.0 * fS * fLv);
  ELSE
    fA := cPi * fR * fR;
    fTFull := fA * fHt;
    fTVol := fA * fLv;
    fTArea := fA;
  END_CASE;
  Tank := TRUE;
END_METHOD

(* the vessel at level fL (in the level unit) with the settings stS: fCVol, fCFull (m3, after the fraction and
   the dead volume), fCArea, fCPct, bCOver; FALSE: a constant or a setting is not usable *)
METHOD PRIVATE Calc : BOOL
  VAR_INPUT
    fL : REAL;
    fVolK : REAL;                 // m3 to eVolumeUnit
    stS : REFERENCE TO ST_VesselSet;

  END_VAR
  VAR
    fDk : REAL;
    fLk : REAL;
    fTop : REAL;
    fH : REAL;
    fDead : REAL;
    fLo : REAL;
    fHi : REAL;
    fN : REAL;
  END_VAR
  (* Calc starts FALSE on every call (a method's result begins at its type's default); eCalcWhy says why *)
  eCalcWhy := E_UtError.ChoiceBad;
  CASE eLevelUnitNow OF
    E_Unit.Metre, E_Unit.Percent: fDk := 1.0;
    E_Unit.Cm: fDk := 0.01;
    E_Unit.Mm: fDk := 0.001;
  ELSE
    RETURN;
  END_CASE;
  eCalcWhy := E_UtError.ValueBad;
  IF NOT (fVolK > 0.0 AND stConfig.nTanks >= 1 AND stConfig.nTanks <= 100
          AND stConfig.fFraction > 0.0 AND stConfig.fFraction <= 1.0
          AND stConfig.fDensity >= 0.0 AND stConfig.fDensity <= 1.0E6) THEN
    RETURN;
  END_IF;
  IF NOT Tank(fH := 0.0, fVolK := fVolK) THEN
    RETURN;
  END_IF;
  fTop := fTTop;
  IF eLevelUnitNow = E_Unit.Percent THEN
    fLk := fTop / 100.0;
  ELSE
    fLk := fDk;
  END_IF;
  IF NOT (stS.fDeadVolume >= 0.0 AND stS.fDeadVolume <= 3.4E38
          AND stS.fLevelOffset * fLk >= -10000.0 AND stS.fLevelOffset * fLk <= 10000.0) THEN
    RETURN;
  END_IF;
  fH := (fL + stS.fLevelOffset) * fLk;
  IF NOT (ABS(fH) <= 3.4E38) THEN
    fH := 0.0;
  END_IF;
  fN := INT_TO_REAL(stConfig.nTanks);
  IF NOT Tank(fH := fH, fVolK := fVolK) THEN
    RETURN;
  END_IF;
  fDead := stS.fDeadVolume / fVolK;

  fCFull := fTFull * fN * stConfig.fFraction - fDead;
  fCVol := fTVol * fN * stConfig.fFraction - fDead;
  IF fCVol < 0.0 THEN
    fCVol := 0.0;
  END_IF;
  IF NOT (fCFull > 0.0) THEN
    eCalcWhy := E_UtError.AboveMax;
    RETURN;                       // the dead volume fills the whole vessel
  END_IF;
  fCArea := fTArea * fN * stConfig.fFraction;
  bCOver := bTOver;
  (* the level as a % of the working range *)
  IF fH < 0.0 THEN fH := 0.0; ELSIF fH > fTop THEN fH := fTop; END_IF;
  IF stS.fPctLow = 0.0 AND stS.fPctHigh = 0.0 THEN
    fLo := 0.0;
    fHi := fTop;
  ELSE
    fLo := (stS.fPctLow + stS.fLevelOffset) * fLk;
    fHi := (stS.fPctHigh + stS.fLevelOffset) * fLk;
    IF NOT (fHi > fLo AND fLo >= -10000.0 AND fHi <= 10000.0) THEN
      eCalcWhy := E_UtError.LimitsBad;
      RETURN;
    END_IF;
  END_IF;
  fCPct := (fH - fLo) / (fHi - fLo) * 100.0;
  IF fCPct < 0.0 THEN
    fCPct := 0.0;
  END_IF;

  eCalcWhy := E_UtError.None;
  Calc := TRUE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bGood := FALSE;
  bFittedNow := FALSE;
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
IF refData.bCmdReset THEN
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;

(* the level *)
bHave := FALSE;
bLvlGood := FALSE;
bFittedNow := FALSE;
fLvl := 0.0;
IF ipLevel <> NULL THEN
  bHave := ipLevel.bHasValue;
  bFittedNow := ipLevel.bIsFitted;
  fLvl := ipLevel.fActValue;
  bLvlGood := bHave AND ipLevel.bIsGood AND ABS(fLvl) <= 3.4E38;
END_IF;
IF stConfig.eLevelUnit <> E_Unit.None THEN
  eLevelUnitNow := stConfig.eLevelUnit;
ELSIF ipLevel <> NULL THEN
  eLevelUnitNow := ipLevel.eUnit;
ELSE
  eLevelUnitNow := E_Unit.None;
END_IF;
IF eLevelUnitNow = E_Unit.None THEN
  eLevelUnitNow := E_Unit.Metre;
END_IF;


(* units *)
CASE stConfig.eVolumeUnit OF
  E_Unit.None, E_Unit.M3: fVk := 1.0;
  E_Unit.Litre: fVk := 1000.0;
  E_Unit.MegaLitre: fVk := 0.001;
ELSE
  fVk := 0.0;
END_CASE;
CASE stConfig.eMassUnit OF
  E_Unit.None, E_Unit.Kg: fMk := 1.0;
  E_Unit.Tonne: fMk := 0.001;
ELSE
  fMk := 0.0;
END_CASE;

(* work it out; a bad write is put back (a bad level: the settings check only, the outputs hold) *)
IF NOT bLvlGood THEN
  fLvl := 0.0;
END_IF;
bOk := fMk > 0.0 AND Calc(fL := fLvl, fVolK := fVk, stS := refData.set);
eWhy := eCalcWhy;
IF bOk THEN
  stKept := refData.set;
ELSIF fMk > 0.0 AND Calc(fL := fLvl, fVolK := fVk, stS := stKept) THEN
  refData.sts.eRefusedWhy := eWhy;
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;

IF bOk AND bLvlGood AND bFittedNow THEN
  fLevel := ipLevel.fActValue;
  bHaveGood := TRUE;
  fVolume := fCVol * fVk;
  fFull := fCFull * fVk;
  fPercent := fCVol / fCFull * 100.0;
  refData.sts.fVolume := fVolume;
  refData.sts.fFullVolume := fFull;
  refData.sts.fPercent := fPercent;
  refData.sts.fFree := (fCFull - fCVol) * fVk;
  refData.sts.fMass := fCVol * stConfig.fDensity * fMk;
  refData.sts.fLevelPercent := fCPct;
  refData.sts.fArea := fCArea;
  refData.sts.bOverfull := bCOver;
END_IF;
bGood := bOk AND bLvlGood AND bFittedNow;

(* errors *)
bError := NOT bOk OR NOT bHave;
bWarning := NOT bError AND refData.sts.bRefused;
IF NOT bHave THEN
  eErrorId := E_UtError.NoMeasurement;
ELSIF NOT bOk THEN
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
ELSIF NOT bHaveGood THEN
  eState := E_State.Waiting;
ELSIF NOT bLvlGood THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
refData.sts.bGood := bGood;
bFirstScan := FALSE;

END_FUNCTION_BLOCK