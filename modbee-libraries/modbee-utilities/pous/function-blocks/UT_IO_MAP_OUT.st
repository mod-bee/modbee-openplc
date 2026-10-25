(* UT_IO_MAP_OUT — the output side of the IO map: functions to terminals, from
the settings. Call it LAST in the scan, after all logic, and before your
IO code copies the image to the hardware.

PINS
ForcePermit BOOL           outputs may be forced only while TRUE (wire:
system Off). Dropping it releases every output force
ReleaseAll  BOOL           TRUE releases every output force and refuses new
ones (wire: HMI link lost, or the "release all" key)
AllOk       BOOL out       every fitted function and fitted module is good
AnyForced   BOOL out       an output is forced
ConfigBad   BOOL out       a wrong address, a function on a module not fitted,
two functions on one output, or a table size
TermBits, ForcedBits  DWORD out   the first 32 digital terminals: state, forced
FnBits, OkBits        DWORD out   the first 32 digital functions: q wanted, ok
HeldBits              DWORD out   the first 32 digital functions: held off (holdOff)
DigSet / Dig  ARRAY[*] OF UT_IO_DO_SET / UT_IO_DO   digital output functions: settings / live
AnaSet / Ana  ARRAY[*] OF UT_IO_AO_SET / UT_IO_AO   analog output functions: settings / live
DigImg       ARRAY[*] OF UT_IO_DCH   the digital output terminals (your IO code reads q)
AnaImg       ARRAY[*] OF UT_IO_ACH   the analog output terminals (your IO code reads v)
Mods         ARRAY[*] OF UT_IO_MOD   the module table (shared with UT_IO_MAP_IN)
Force        ARRAY[*] OF UT_IO_FORCE the force slots (shared with UT_IO_MAP_IN; never retained)
Data         UT_IO_MAP_DATA          set.forceTime; status, counts

WHAT IT DOES
The block owns the output image: every scan it first turns every output
channel off (analog: 0.0), then writes each function's q / v to its
channel; a force takes the place of the function's value. So a channel
with no function is off, and a function moved to another channel leaves
nothing behind.
One output channel carries one function: a second function on the same
channel is not written (why = SHARED, a configuration problem).
A function's ok is TRUE when its channel is fitted, answering and good,
so your logic knows the output reached the field (a remote valve over
the radio, an I2C relay module); why says what is wrong otherwise; fit
says it is mapped on this site.
holdOff (per digital function): TRUE holds the output off even while
forced. Wire the motor's HoldOff into it (overload, dry run), so a
commissioning force can never run a tripped motor.

SETTINGS
The block keeps its own copy of DigSet, AnaSet and Data.set (a fixed
table: 32 digital, 4 analog rows). A write the block can't use (a source
number out of range, force time 0 or over 10 min) is put back to the kept
copy, with sts.refused. Rows past the kept table still work, but are not
kept: the status is Config: array size.

FORCING (commissioning)
Outputs can be forced only while ForcePermit is TRUE (system Off); when it
drops, every output force ends (state NOT_PERMITTED). A slot names a
channel (kind DO or AO, src, module, ch), so spare outputs can be tested
too. Each force ends by itself after set.forceTime (default 5 s, at most
10 min); cmdForce again starts the time again; cmdRelease or ReleaseAll
end it at once. Every force ends at power-up.

Status, most important first: Config: array size, Config: IO address,
Config: output used twice, Config: IO not fitted, Warning: IO forced,
Warning: IO module missing, Warning: IO channel bad, Setting, OK. *)

FUNCTION_BLOCK UT_IO_MAP_OUT
  VAR_INPUT
    ForcePermit : BOOL := FALSE; (* outputs may be forced only while TRUE (system Off); unwired: never *)
    ReleaseAll : BOOL; (* TRUE: release every output force now and refuse new ones *)
  END_VAR
  VAR_OUTPUT
    AllOk : BOOL; (* every fitted function and fitted module is good *)
    AnyForced : BOOL; (* an output is forced *)
    ConfigBad : BOOL; (* a wrong address, a module not fitted, two functions on one output, a table size *)
    TermBits : DWORD; (* the first 32 digital terminals *)
    FnBits : DWORD; (* the first 32 digital functions: q wanted *)
    OkBits : DWORD; (* the first 32 digital functions: ok *)
    ForcedBits : DWORD; (* the first 32 digital terminals: forced *)
    HeldBits : DWORD; (* the first 32 digital functions: held off *)
  END_VAR
  VAR RETAIN
    keptMap : UT_IO_MAP_SET;
    keptDig : ARRAY [1..32] OF UT_IO_DO_SET;
    keptAna : ARRAY [1..4] OF UT_IO_AO_SET;
    keptGood : BOOL;
  END_VAR
  VAR_IN_OUT
    DigSet : ARRAY [*] OF UT_IO_DO_SET; (* digital output functions: settings *)
    Dig : ARRAY [*] OF UT_IO_DO; (* digital output functions: live *)
    AnaSet : ARRAY [*] OF UT_IO_AO_SET; (* analog output functions: settings *)
    Ana : ARRAY [*] OF UT_IO_AO; (* analog output functions: live *)
    DigImg : ARRAY [*] OF UT_IO_DCH; (* digital output terminals *)
    AnaImg : ARRAY [*] OF UT_IO_ACH; (* analog output terminals *)
    Mods : ARRAY [*] OF UT_IO_MOD; (* module table *)
    Force : ARRAY [*] OF UT_IO_FORCE; (* force slots *)
    Data : UT_IO_MAP_DATA;
  END_VAR
  VAR
    kp : UT_KEEP;
    tCur : TIME;
    begun : BOOL;
    ft : TIME; (* the force time in use *)
    setOk : BOOL;
    why : UT_FAULT;
    sizeBad : BOOL;
    nD : DINT;
    nA : DINT;
    nDk : DINT;
    nAk : DINT;
    i : DINT;
    j : DINT;
    k : DINT;
    sj : DINT;
    m : DINT;
    idx : DINT;
    mLo : DINT;
    mHi : DINT;
    dLo : DINT;
    dHi : DINT;
    aLo : DINT;
    aHi : DINT;
    kind : UT_IO_KIND;
    src : UT_IO_SRC;
    modNo : USINT;
    ch : USINT;
    where : UT_IO_Q;
    nForced : INT;
    nBad : INT;
    nAddr : INT;
    nShared : INT;
    nNotFit : INT;
    nMissFn : INT;
    nChBad : INT;
    nMissMod : INT;
    leftMax : UINT;
    st : UT_STATUS;
    fid : UT_FAULT;
  END_VAR


tCur := TIME();
sizeBad := UPPER_BOUND(DigSet, 1) - LOWER_BOUND(DigSet, 1) <> UPPER_BOUND(Dig, 1) - LOWER_BOUND(Dig, 1)
           OR UPPER_BOUND(AnaSet, 1) - LOWER_BOUND(AnaSet, 1) <> UPPER_BOUND(Ana, 1) - LOWER_BOUND(Ana, 1);
nD := MIN(UPPER_BOUND(DigSet, 1) - LOWER_BOUND(DigSet, 1), UPPER_BOUND(Dig, 1) - LOWER_BOUND(Dig, 1)) + 1;
nA := MIN(UPPER_BOUND(AnaSet, 1) - LOWER_BOUND(AnaSet, 1), UPPER_BOUND(Ana, 1) - LOWER_BOUND(Ana, 1)) + 1;
nDk := MIN(nD, 32);
nAk := MIN(nA, 4);
sizeBad := sizeBad OR nD > 32 OR nA > 4;

(* 0. the settings: the kept copy, a bad write put back *)
kp();
IF kp.RestoreSet THEN
  Data.set := keptMap;
  FOR i := 1 TO nDk DO DigSet[LOWER_BOUND(DigSet, 1) + i - 1] := keptDig[i]; END_FOR;
  FOR i := 1 TO nAk DO AnaSet[LOWER_BOUND(AnaSet, 1) + i - 1] := keptAna[i]; END_FOR;
END_IF;
why := UT_CHECK_TIME(Value := Data.set.forceTime, MinValue := T#1ms, MaxValue := T#10m);
IF why <> UT_F_NONE THEN
  why := UT_F_FORCE_TIME;
END_IF;
FOR i := 1 TO nD DO
  src := DigSet[LOWER_BOUND(DigSet, 1) + i - 1].src;
  IF why = UT_F_NONE AND NOT (src = UT_IOS_NONE OR src = UT_IOS_BOARD OR src = UT_IOS_I2C
                              OR src = UT_IOS_FIELD OR src = UT_IOS_REMOTE) THEN
    why := UT_F_SETTING;
  END_IF;
END_FOR;
FOR i := 1 TO nA DO
  src := AnaSet[LOWER_BOUND(AnaSet, 1) + i - 1].src;
  IF why = UT_F_NONE AND NOT (src = UT_IOS_NONE OR src = UT_IOS_BOARD OR src = UT_IOS_I2C
                              OR src = UT_IOS_FIELD OR src = UT_IOS_REMOTE) THEN
    why := UT_F_SETTING;
  END_IF;
END_FOR;
setOk := why = UT_F_NONE;
IF NOT setOk AND keptGood AND NOT kp.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := why;
  Data.set := keptMap;
  FOR i := 1 TO nDk DO DigSet[LOWER_BOUND(DigSet, 1) + i - 1] := keptDig[i]; END_FOR;
  FOR i := 1 TO nAk DO AnaSet[LOWER_BOUND(AnaSet, 1) + i - 1] := keptAna[i]; END_FOR;
  setOk := TRUE;
END_IF;
IF kp.SaveSet AND (setOk OR NOT keptGood) THEN
  keptMap := Data.set;
  FOR i := 1 TO nDk DO keptDig[i] := DigSet[LOWER_BOUND(DigSet, 1) + i - 1]; END_FOR;
  FOR i := 1 TO nAk DO keptAna[i] := AnaSet[LOWER_BOUND(AnaSet, 1) + i - 1]; END_FOR;
  keptGood := setOk;
END_IF;
ft := Data.set.forceTime;
IF ft <= T#0s THEN
  ft := T#5s;
ELSIF ft > T#10m THEN
  ft := T#10m;
END_IF;

mLo := LOWER_BOUND(Mods, 1);
mHi := UPPER_BOUND(Mods, 1);
dLo := LOWER_BOUND(DigImg, 1);
dHi := UPPER_BOUND(DigImg, 1);
aLo := LOWER_BOUND(AnaImg, 1);
aHi := UPPER_BOUND(AnaImg, 1);

(* 1. every output channel off; nothing forced, no function yet *)
FOR j := dLo TO dHi DO
  DigImg[j].q := FALSE;
  DigImg[j].forced := FALSE;
  DigImg[j].fn := 0;
END_FOR;
FOR j := aLo TO aHi DO
  AnaImg[j].v := 0.0;
  AnaImg[j].forced := FALSE;
  AnaImg[j].fn := 0;
END_FOR;

(* 2. the output modules *)
nMissMod := 0;
FOR k := mLo TO mHi DO
  IF Mods[k].kind = UT_IOK_DO OR Mods[k].kind = UT_IOK_AO THEN
    Mods[k].used := 0;
    IF NOT Mods[k].fitted THEN
      Mods[k].state := UT_IOQ_NOT_FITTED;
    ELSIF NOT Mods[k].ok THEN
      Mods[k].state := UT_IOQ_MISSING;
      nMissMod := nMissMod + 1;
    ELSE
      Mods[k].state := UT_IOQ_OK;
    END_IF;
  END_IF;
END_FOR;

(* 3. the force slots for outputs: the forced value goes on the terminal *)
nForced := 0;
leftMax := 0;
FOR j := LOWER_BOUND(Force, 1) TO UPPER_BOUND(Force, 1) DO
  kind := Force[j].kind;
  IF kind = UT_IOK_DO OR kind = UT_IOK_AO THEN
    src := Force[j].src;
    modNo := Force[j].module;
    ch := Force[j].ch;
    m := mLo - 1;
    FOR k := mLo TO mHi DO
      IF m < mLo AND Mods[k].kind = kind AND Mods[k].src = src AND Mods[k].module = modNo THEN
        m := k;
      END_IF;
    END_FOR;
    idx := 0;
    IF m < mLo THEN
      where := UT_IOQ_NO_MODULE;
    ELSIF ch < 1 OR ch > Mods[m].count THEN
      where := UT_IOQ_NO_CHANNEL;
    ELSE
      idx := INT_TO_DINT(Mods[m].first) + USINT_TO_DINT(ch) - 1;
      where := UT_IOQ_OK;
      IF kind = UT_IOK_DO THEN
        IF idx < dLo OR idx > dHi THEN
          where := UT_IOQ_NO_CHANNEL;
        END_IF;
      ELSIF idx < aLo OR idx > aHi THEN
        where := UT_IOQ_NO_CHANNEL;
      END_IF;
    END_IF;
    IF UT_IO_FORCE_RUN(S := Force[j], Where := where, Permit := ForcePermit, Release := ReleaseAll OR NOT begun,
                       Now := tCur, ForceTime := ft) THEN
      Force[j].row := DINT_TO_INT(idx);
      IF kind = UT_IOK_DO THEN
        DigImg[idx].q := Force[j].q;
        DigImg[idx].forced := TRUE;
      ELSE
        AnaImg[idx].v := Force[j].v;
        AnaImg[idx].forced := TRUE;
      END_IF;
      nForced := nForced + 1;
      IF Force[j].leftS > leftMax THEN
        leftMax := Force[j].leftS;
      END_IF;
    END_IF;
  END_IF;
END_FOR;

(* 4. the functions: q / v to the channel unless forced; holdOff beats both *)
nBad := 0;
nAddr := 0;
nShared := 0;
nNotFit := 0;
nMissFn := 0;
nChBad := 0;
FnBits := 0;
OkBits := 0;
HeldBits := 0;
FOR i := 1 TO nD DO
  sj := LOWER_BOUND(DigSet, 1) + i - 1;
  j := LOWER_BOUND(Dig, 1) + i - 1;
  src := DigSet[sj].src;
  m := mLo - 1;
  idx := 0;
  Dig[j].out := FALSE;
  IF src = UT_IOS_NONE THEN
    where := UT_IOQ_UNUSED;
  ELSE
    modNo := DigSet[sj].module;
    ch := DigSet[sj].ch;
    FOR k := mLo TO mHi DO
      IF m < mLo AND Mods[k].kind = UT_IOK_DO AND Mods[k].src = src AND Mods[k].module = modNo THEN
        m := k;
      END_IF;
    END_FOR;
    IF m < mLo THEN
      where := UT_IOQ_NO_MODULE;
    ELSIF ch < 1 OR ch > Mods[m].count THEN
      where := UT_IOQ_NO_CHANNEL;
    ELSE
      idx := INT_TO_DINT(Mods[m].first) + USINT_TO_DINT(ch) - 1;
      IF idx < dLo OR idx > dHi THEN
        where := UT_IOQ_NO_CHANNEL;
      ELSIF DigImg[idx].fn <> 0 THEN
        where := UT_IOQ_SHARED;
      ELSE
        Mods[m].used := Mods[m].used + 1;
        DigImg[idx].fn := DINT_TO_USINT(MIN(i, 255));
        IF NOT Mods[m].fitted THEN
          where := UT_IOQ_NOT_FITTED;
        ELSIF NOT Mods[m].ok THEN
          where := UT_IOQ_MISSING;
        ELSIF DigImg[idx].bad THEN
          where := UT_IOQ_BAD;
        ELSE
          where := UT_IOQ_OK;
        END_IF;
        IF NOT DigImg[idx].forced THEN
          DigImg[idx].q := Dig[j].q;
        END_IF;
        IF Dig[j].holdOff THEN
          DigImg[idx].q := FALSE;
        END_IF;
        Dig[j].out := DigImg[idx].q;
      END_IF;
    END_IF;
  END_IF;
  Dig[j].ok := where = UT_IOQ_OK;
  Dig[j].fit := where <> UT_IOQ_UNUSED AND where <> UT_IOQ_NOT_FITTED;
  IF NOT Dig[j].ok AND where <> UT_IOQ_UNUSED THEN
    nBad := nBad + 1;
  END_IF;
  CASE where OF
  UT_IOQ_NO_MODULE, UT_IOQ_NO_CHANNEL: nAddr := nAddr + 1;
  UT_IOQ_SHARED: nShared := nShared + 1;
  UT_IOQ_NOT_FITTED: nNotFit := nNotFit + 1;
  UT_IOQ_MISSING: nMissFn := nMissFn + 1;
  UT_IOQ_BAD: nChBad := nChBad + 1;
  END_CASE;
  IF m >= mLo AND where <> UT_IOQ_NO_CHANNEL AND where <> UT_IOQ_SHARED THEN
    IF DigImg[idx].forced THEN
      IF Dig[j].holdOff THEN
        where := UT_IOQ_BLOCKED;
      ELSE
        where := UT_IOQ_FORCED;
      END_IF;
    END_IF;
  END_IF;
  Dig[j].why := where;
  IF i <= 32 THEN
    FnBits := UT_BIT_PUT(Bits := FnBits, Bit := DINT_TO_SINT(i - 1), Value := Dig[j].q);
    OkBits := UT_BIT_PUT(Bits := OkBits, Bit := DINT_TO_SINT(i - 1), Value := Dig[j].ok);
    HeldBits := UT_BIT_PUT(Bits := HeldBits, Bit := DINT_TO_SINT(i - 1), Value := Dig[j].holdOff);
  END_IF;
END_FOR;

FOR i := 1 TO nA DO
  sj := LOWER_BOUND(AnaSet, 1) + i - 1;
  j := LOWER_BOUND(Ana, 1) + i - 1;
  src := AnaSet[sj].src;
  m := mLo - 1;
  idx := 0;
  Ana[j].out := 0.0;
  IF src = UT_IOS_NONE THEN
    where := UT_IOQ_UNUSED;
  ELSE
    modNo := AnaSet[sj].module;
    ch := AnaSet[sj].ch;
    FOR k := mLo TO mHi DO
      IF m < mLo AND Mods[k].kind = UT_IOK_AO AND Mods[k].src = src AND Mods[k].module = modNo THEN
        m := k;
      END_IF;
    END_FOR;
    IF m < mLo THEN
      where := UT_IOQ_NO_MODULE;
    ELSIF ch < 1 OR ch > Mods[m].count THEN
      where := UT_IOQ_NO_CHANNEL;
    ELSE
      idx := INT_TO_DINT(Mods[m].first) + USINT_TO_DINT(ch) - 1;
      IF idx < aLo OR idx > aHi THEN
        where := UT_IOQ_NO_CHANNEL;
      ELSIF AnaImg[idx].fn <> 0 THEN
        where := UT_IOQ_SHARED;
      ELSE
        Mods[m].used := Mods[m].used + 1;
        AnaImg[idx].fn := DINT_TO_USINT(MIN(i, 255));
        IF NOT Mods[m].fitted THEN
          where := UT_IOQ_NOT_FITTED;
        ELSIF NOT Mods[m].ok THEN
          where := UT_IOQ_MISSING;
        ELSIF AnaImg[idx].bad THEN
          where := UT_IOQ_BAD;
        ELSE
          where := UT_IOQ_OK;
        END_IF;
        IF NOT AnaImg[idx].forced THEN
          AnaImg[idx].v := Ana[j].v;
        END_IF;
        Ana[j].out := AnaImg[idx].v;
      END_IF;
    END_IF;
  END_IF;
  Ana[j].ok := where = UT_IOQ_OK;
  Ana[j].fit := where <> UT_IOQ_UNUSED AND where <> UT_IOQ_NOT_FITTED;
  IF NOT Ana[j].ok AND where <> UT_IOQ_UNUSED THEN
    nBad := nBad + 1;
  END_IF;
  CASE where OF
  UT_IOQ_NO_MODULE, UT_IOQ_NO_CHANNEL: nAddr := nAddr + 1;
  UT_IOQ_SHARED: nShared := nShared + 1;
  UT_IOQ_NOT_FITTED: nNotFit := nNotFit + 1;
  UT_IOQ_MISSING: nMissFn := nMissFn + 1;
  UT_IOQ_BAD: nChBad := nChBad + 1;
  END_CASE;
  IF m >= mLo AND where <> UT_IOQ_NO_CHANNEL AND where <> UT_IOQ_SHARED THEN
    IF AnaImg[idx].forced THEN
      where := UT_IOQ_FORCED;
    END_IF;
  END_IF;
  Ana[j].why := where;
END_FOR;

(* 5. the terminals for the IO page *)
TermBits := 0;
ForcedBits := 0;
FOR j := dLo TO MIN(dHi, dLo + 31) DO
  TermBits := UT_BIT_PUT(Bits := TermBits, Bit := DINT_TO_SINT(j - dLo), Value := DigImg[j].q);
  ForcedBits := UT_BIT_PUT(Bits := ForcedBits, Bit := DINT_TO_SINT(j - dLo), Value := DigImg[j].forced);
END_FOR;

(* 6. status *)
begun := TRUE;
AnyForced := nForced > 0;
ConfigBad := sizeBad OR nAddr > 0 OR nShared > 0 OR nNotFit > 0;
AllOk := nBad = 0 AND nMissMod = 0;
Data.sts.forcedCount := nForced;
Data.det.forceLeftS := leftMax;
Data.sts.badCount := nBad;
Data.sts.missingCount := nMissMod;
fid := UT_F_NONE;
IF sizeBad THEN
  st := UT_ST_CONFIG;
  fid := UT_F_ARRAY_SIZE;
ELSIF nAddr > 0 THEN
  st := UT_ST_CONFIG;
  fid := UT_F_IO_ADDRESS;
ELSIF nShared > 0 THEN
  st := UT_ST_CONFIG;
  fid := UT_F_IO_SHARED;
ELSIF nNotFit > 0 THEN
  st := UT_ST_CONFIG;
  fid := UT_F_IO_NOT_FITTED;
ELSIF nForced > 0 THEN
  st := UT_ST_WARNING;
  fid := UT_F_IO_FORCED;
ELSIF nMissMod > 0 OR nMissFn > 0 THEN
  st := UT_ST_WARNING;
  fid := UT_F_IO_MISSING;
ELSIF nChBad > 0 THEN
  st := UT_ST_WARNING;
  fid := UT_F_IO_BAD;
ELSIF NOT setOk THEN
  st := UT_ST_WARN_SETTING;
  fid := why;
ELSE
  st := UT_ST_OK;
END_IF;
IF st <> Data.sts.statusCode OR fid <> Data.sts.faultId OR LEN(Data.sts.statusText) = 0 THEN
  Data.sts.statusText := UT_STATUS_TEXT(st, fid);
END_IF;
Data.sts.statusCode := st;
Data.sts.faultId := fid;
Data.sts.ne107 := UT_NE107_RUN(Fault := ConfigBad, Check := AnyForced,
                               OutOfSpec := NOT AllOk OR NOT setOk, Maint := FALSE);

END_FUNCTION_BLOCK