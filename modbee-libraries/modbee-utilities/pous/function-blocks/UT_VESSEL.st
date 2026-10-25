(* UT_VESSEL — level to volume, percent, mass, free space and water-surface
area, for 1..6 tanks joined at the bottom (one level). Offers the
UT_I_VESSEL plug: GetValue() is the LEVEL (so it plugs into any level pin, with
the level sensor's bands passed through), plus GetVolume(), GetArea(), GetPercent().

Tank 1: set.shape with diameter / height / length / width / coneHeight /
outletDiameter (POND: floor length x width, depth = height, bank slope;
TABLE: volume and area from a UT_LINEARISE table wired to TableVol /
TableArea, tableFull = the volume when full, height = the level when full).
Tanks 2..set.tanks: set.more[n], SAME = as tank 1, or VERTICAL / RECT / POND
with their own dimensions. Each tank is worked out by UT_TANK_CALC at the
one level; the totals add up.

Units: the level, levelOffset and the dimensions are in levelUnit (m, mm or
cm; with % of tank 1's full height the dimensions stay in m). Volumes and
deadVolume in volumeUnit (m3, L, ML); TableVol / tableFull too; TableArea in
volumeUnit per levelUnit. Masses in massUnit, density kg/m3. fraction and
deadVolume apply to the whole set.

The level clamps to each tank (overfull above the top). No Level plug, or
settings that make no vessel: config fault, outputs 0. A bad level: the
outputs hold, levelBad, Good FALSE. A bad write is put back (decision 62). *)

FUNCTION_BLOCK UT_VESSEL IMPLEMENTS UT_I_VESSEL
  VAR_INPUT
    Level : UT_I_MEAS; (* the level sensor (value, health, bands); NULL = config fault *)
    TableVol : REAL; (* TABLE: volume at the level (a UT_LINEARISE's Out) *)
    TableArea : REAL; (* TABLE: its Slope *)
  END_VAR
  VAR_OUTPUT
    Good : BOOL; (* level good, settings valid *)
    Volume : REAL; (* all tanks, in volumeUnit *)
    Percent : REAL; (* of the total volume *)
    Mass : REAL;
    Free : REAL; (* space left *)
    Area : REAL; (* water surface at the level, m2 *)
  END_VAR
  VAR_IN_OUT
    Data : UT_VESSEL_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_VESSEL_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    lvl : REAL;
    lvlGood : BOOL;
    bad : UT_FAULT;
    cVol : REAL; (* m3, after fraction and dead volume *)
    cFull : REAL;
    cArea : REAL;
    cOver : BOOL;
    cPct : REAL;
    cPctBad : BOOL;
    vk : REAL;
    mk : REAL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    zero : REAL;
    mNan : REAL;
    mValue : REAL;
    mGood : BOOL;
    mFault : BOOL;
    mWarn : BOOL;
    mFitted : BOOL;
    mNe : UT_NE107;
    mStatus : UT_STATUS;
    mFaultId : UT_FAULT;
    mUnit : UT_UNIT;
    mHHas : BOOL;
    mHas : BOOL;
    mLHas : BOOL;
    mLLHas : BOOL;
    mHH : BOOL;
    mH : BOOL;
    mL : BOOL;
    mLL : BOOL;
    mVol : REAL;
    mArea : REAL;
    mPct : REAL;
  END_VAR


(* the whole set at level L (in levelUnit): the first bad setting, or UT_F_NONE *)
METHOD PRIVATE Calc : UT_FAULT
  VAR_INPUT
    L : REAL;
  END_VAR
  VAR_IN_OUT
    S : UT_VESSEL_SET;
  END_VAR
  VAR
    g : UT_TANK_GEOM;
    r : UT_TANK_RES;
    dk : REAL;
    lk : REAL;
    h : REAL;
    top1 : REAL;
    n : INT;
    i : INT;
    f : UT_FAULT;
    vol : REAL;
    full : REAL;
    ar : REAL;
    over : BOOL;
    dead : REAL;
    pLo : REAL;
    pHi : REAL;
    x : BOOL;
  END_VAR
  f := UT_F_NONE;
  CASE S.levelUnit OF
  UT_LEVEL_MM: dk := 0.001;
  UT_LEVEL_CM: dk := 0.01;
  ELSE
    dk := 1.0;
  END_CASE;
  n := USINT_TO_INT(S.tanks);
  IF n < 1 OR n > 6 THEN
    Calc := UT_F_TANKS;
    RETURN;
  END_IF;
  IF vk <= 0.0 OR mk <= 0.0 OR NOT (S.levelUnit = UT_LEVEL_M OR S.levelUnit = UT_LEVEL_MM
                                    OR S.levelUnit = UT_LEVEL_CM OR S.levelUnit = UT_LEVEL_PCT) THEN
    Calc := UT_F_UNIT;
    RETURN;
  END_IF;
  (* tank 1's top, for the % level unit *)
  g.shape := S.shape;
  g.diameter := S.diameter * dk;
  g.height := S.height * dk;
  g.length := S.length * dk;
  g.width := S.width * dk;
  g.coneHeight := S.coneHeight * dk;
  g.outletDiameter := S.outletDiameter * dk;
  g.slope := S.slope;
  g.tableFull := S.tableFull / vk;
  x := UT_TANK_CALC(H := 0.0, TableVol := 0.0, TableArea := 0.0, G := g, R := r);
  IF r.bad <> UT_F_NONE THEN
    Calc := r.bad;
    RETURN;
  END_IF;
  top1 := r.top;
  IF S.levelUnit = UT_LEVEL_PCT THEN
    lk := top1 / 100.0;
  ELSE
    lk := dk;
  END_IF;
  IF NOT (S.fraction > 0.0 AND S.fraction <= 1.0) THEN
    f := UT_F_FRACTION;
  ELSIF NOT (S.density >= 0.0 AND S.density <= 1.0E6) THEN
    f := UT_F_DENSITY;
  ELSIF NOT (S.deadVolume >= 0.0 AND S.deadVolume <= 3.4E38) THEN
    f := UT_F_DEAD_VOLUME;
  ELSIF NOT (S.levelOffset * lk >= -10000.0 AND S.levelOffset * lk <= 10000.0) THEN
    f := UT_F_LEVEL_OFFSET;
  END_IF;
  IF f <> UT_F_NONE THEN
    Calc := f;
    RETURN;
  END_IF;
  h := (L + S.levelOffset) * lk;
  IF NOT (h = h) THEN
    h := 0.0;
  END_IF;
  vol := 0.0;
  full := 0.0;
  ar := 0.0;
  over := FALSE;
  FOR i := 1 TO n DO
    IF i > 1 THEN                (* (AND does not short-circuit in IEC: no more[1]) *)
      IF S.more[i].shape <> UT_SHAPE_SAME THEN
        g.shape := S.more[i].shape;
        g.diameter := S.more[i].diameter * dk;
        g.height := S.more[i].height * dk;
        g.length := S.more[i].length * dk;
        g.width := S.more[i].width * dk;
        g.coneHeight := 0.0;
        g.outletDiameter := 0.0;
        g.slope := S.more[i].slope;
        IF NOT (g.shape = UT_SHAPE_VERTICAL OR g.shape = UT_SHAPE_RECT OR g.shape = UT_SHAPE_POND) THEN
          Calc := UT_F_TANKS;
          RETURN;
        END_IF;
      ELSE                       (* SAME: tank 1's geometry *)
        g.shape := S.shape;
        g.diameter := S.diameter * dk;
        g.height := S.height * dk;
        g.length := S.length * dk;
        g.width := S.width * dk;
        g.coneHeight := S.coneHeight * dk;
        g.outletDiameter := S.outletDiameter * dk;
        g.slope := S.slope;
      END_IF;
    END_IF;
    x := UT_TANK_CALC(H := h, TableVol := TableVol / vk, TableArea := TableArea / vk / lk, G := g, R := r);
    IF r.bad <> UT_F_NONE THEN
      Calc := r.bad;
      RETURN;
    END_IF;
    vol := vol + r.volume;
    full := full + r.full;
    ar := ar + r.area;
    over := over OR r.overfull;
  END_FOR;
  dead := S.deadVolume / vk;
  full := full * S.fraction - dead;
  vol := vol * S.fraction - dead;
  IF vol < 0.0 THEN
    vol := 0.0;
  END_IF;
  IF NOT (full > 0.0) THEN
    Calc := UT_F_DEAD_VOLUME;    (* the dead volume fills the whole vessel *)
    RETURN;
  END_IF;
  cVol := vol;
  cFull := full;
  cArea := ar * S.fraction;
  cOver := over;
  (* the level as a % of the working range *)
  cPctBad := FALSE;
  IF h < 0.0 THEN h := 0.0; ELSIF h > top1 THEN h := top1; END_IF;
  IF S.pctLow = 0.0 AND S.pctHigh = 0.0 THEN
    pLo := 0.0;
    pHi := top1;
  ELSE
    pLo := (S.pctLow + S.levelOffset) * lk;
    pHi := (S.pctHigh + S.levelOffset) * lk;
    IF NOT (pHi > pLo AND pLo >= -10000.0 AND pHi <= 10000.0) THEN
      cPctBad := TRUE;
      pLo := 0.0;
      pHi := top1;
    END_IF;
  END_IF;
  cPct := (h - pLo) / (pHi - pLo) * 100.0;
  IF cPct < 0.0 THEN
    cPct := 0.0;
  END_IF;
  Calc := UT_F_NONE;
END_METHOD

METHOD PUBLIC StatusCode : UT_STATUS
  StatusCode := mStatus;
END_METHOD
METHOD PUBLIC FaultId : UT_FAULT
  FaultId := mFaultId;
END_METHOD
METHOD PUBLIC StopReason : UT_STOP
  StopReason := UT_STOP_NONE;
END_METHOD
METHOD PUBLIC HasFault : BOOL
  HasFault := mFault;
END_METHOD
METHOD PUBLIC HasWarning : BOOL
  HasWarning := mWarn;
END_METHOD
METHOD PUBLIC IsLocked : BOOL
  IsLocked := FALSE;
END_METHOD
METHOD PUBLIC IsFitted : BOOL
  IsFitted := mFitted;
END_METHOD
METHOD PUBLIC Ne107 : UT_NE107
  Ne107 := mNe;
END_METHOD
METHOD PUBLIC GetValue : REAL
  GetValue := mValue;               (* the level; NaN when not Good *)
END_METHOD
METHOD PUBLIC GoodNow : BOOL
  GoodNow := mGood;
END_METHOD
METHOD PUBLIC HasValue : BOOL
  HasValue := TRUE;
END_METHOD
METHOD PUBLIC HasBand : BOOL
  VAR_INPUT
    Band : UT_LEVEL_ID;
  END_VAR
  CASE Band OF
  UT_LVL_HIHI: HasBand := mHHas;
  UT_LVL_HI: HasBand := mHas;
  UT_LVL_LO: HasBand := mLHas;
  UT_LVL_LOLO: HasBand := mLLHas;
  ELSE
    HasBand := FALSE;
  END_CASE;
END_METHOD
METHOD PUBLIC IsHiHiNow : BOOL
  IsHiHiNow := mHH;
END_METHOD
METHOD PUBLIC IsHiNow : BOOL
  IsHiNow := mH;
END_METHOD
METHOD PUBLIC IsLoNow : BOOL
  IsLoNow := mL;
END_METHOD
METHOD PUBLIC IsLoLoNow : BOOL
  IsLoLoNow := mLL;
END_METHOD
METHOD PUBLIC Unit : UT_UNIT
  Unit := mUnit;
END_METHOD
METHOD PUBLIC GetVolume : REAL
  GetVolume := mVol;
END_METHOD
METHOD PUBLIC GetArea : REAL
  GetArea := mArea;
END_METHOD
METHOD PUBLIC GetPercent : REAL
  GetPercent := mPct;
END_METHOD

keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.PowerUp THEN
  mNan := zero / zero;
END_IF;

(* the level *)
lvl := 0.0;
lvlGood := FALSE;
mFitted := Level <> NULL;
IF Level <> NULL THEN
  lvl := Level.GetValue();
  lvlGood := Level.GoodNow() AND ABS(lvl) <= 3.4E38;
  mFitted := Level.IsFitted();
  mHHas := Level.HasBand(Band := UT_LVL_HIHI);
  mHas := Level.HasBand(Band := UT_LVL_HI);
  mLHas := Level.HasBand(Band := UT_LVL_LO);
  mLLHas := Level.HasBand(Band := UT_LVL_LOLO);
  mHH := Level.IsHiHiNow();
  mH := Level.IsHiNow();
  mL := Level.IsLoNow();
  mLL := Level.IsLoLoNow();
  mUnit := Level.Unit();
END_IF;

(* units *)
CASE Data.set.volumeUnit OF
UT_VOL_NONE, UT_VOL_M3: vk := 1.0;
UT_VOL_L: vk := 1000.0;
UT_VOL_ML: vk := 0.001;
ELSE
  vk := 0.0;
END_CASE;
CASE Data.set.massUnit OF
UT_MASS_KG: mk := 1.0;
UT_MASS_T: mk := 0.001;
ELSE
  mk := 0.0;
END_CASE;

(* work it out; a bad write is put back and worked out again *)
IF lvlGood THEN
  bad := Calc(L := lvl, S := Data.set);
ELSE
  bad := Calc(L := 0.0, S := Data.set);   (* the settings check; the outputs hold below *)
END_IF;
IF bad <> UT_F_NONE AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := bad;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  CASE Data.set.volumeUnit OF
  UT_VOL_NONE, UT_VOL_M3: vk := 1.0;
  UT_VOL_L: vk := 1000.0;
  UT_VOL_ML: vk := 0.001;
  ELSE
    vk := 0.0;
  END_CASE;
  IF lvlGood THEN
    bad := Calc(L := lvl, S := Data.set);
  ELSE
    bad := Calc(L := 0.0, S := Data.set);
  END_IF;
END_IF;
IF keep.SaveSet AND (bad = UT_F_NONE OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := bad = UT_F_NONE;
END_IF;
IF Level = NULL AND bad = UT_F_NONE THEN
  bad := UT_F_NO_LINK;
END_IF;

Data.sts.configBad := bad <> UT_F_NONE;
Data.sts.levelBad := NOT lvlGood AND bad = UT_F_NONE AND mFitted;
IF bad <> UT_F_NONE THEN
  Data.sts.volume := 0.0;
  Data.sts.totalVolume := 0.0;
  Data.sts.percent := 0.0;
  Data.sts.mass := 0.0;
  Data.sts.totalMass := 0.0;
  Data.sts.free := 0.0;
  Data.sts.area := 0.0;
  Data.sts.levelPct := 0.0;
  Data.sts.overfull := FALSE;
ELSIF lvlGood THEN               (* a bad level holds the outputs *)
  Data.sts.volume := cVol * vk;
  Data.sts.totalVolume := cFull * vk;
  Data.sts.percent := cVol / cFull * 100.0;
  Data.sts.mass := cVol * Data.set.density * mk;
  Data.sts.totalMass := cFull * Data.set.density * mk;
  Data.sts.free := (cFull - cVol) * vk;
  Data.sts.area := cArea;
  Data.sts.levelPct := cPct;
  Data.sts.overfull := cOver;
END_IF;
Good := bad = UT_F_NONE AND lvlGood;
Volume := Data.sts.volume;
Percent := Data.sts.percent;
Mass := Data.sts.mass;
Free := Data.sts.free;
Area := Data.sts.area;

(* status *)
stF := UT_F_NONE;
IF bad <> UT_F_NONE THEN
  stCode := UT_ST_CONFIG;
  stF := bad;
ELSIF NOT mFitted THEN
  stCode := UT_ST_NOT_FITTED;
ELSIF NOT lvlGood THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_LEVEL_BAD;
ELSIF Data.sts.overfull THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_LEVEL_ABOVE_FULL;
ELSIF cPctBad THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_LEVEL_RANGE;
ELSE
  stCode := UT_ST_OK;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.good := Good;
Data.sts.ne107 := UT_NE107_RUN(Fault := (bad <> UT_F_NONE) OR (NOT lvlGood AND mFitted), Check := FALSE,
                               OutOfSpec := Data.sts.overfull OR cPctBad, Maint := FALSE);

(* the plug's answers *)
mGood := Good;
IF Good THEN mValue := lvl; ELSE mValue := mNan; END_IF;
mFault := bad <> UT_F_NONE OR (NOT lvlGood AND mFitted);
mWarn := Data.sts.overfull OR cPctBad;
mNe := Data.sts.ne107;
mStatus := stCode;
mFaultId := stF;
mVol := Volume;
mArea := Area;
mPct := Percent;

END_FUNCTION_BLOCK