(* UT_IO_MAP_IN — the input side of the IO map: terminals to functions, from
the settings. Call it FIRST in the scan, after your IO code has copied the
hardware into the image, and before any logic.

PINS
ReleaseAll  BOOL           TRUE releases every input force and refuses new
ones (wire: HMI link lost, or the "release all" key)
UnusedOff   BOOL := TRUE   a function not fitted on this site (src NONE)
reads FALSE / 0.0; FALSE: it reads its failSafe
AllOk       BOOL out       every fitted function and fitted module is good
AnyForced   BOOL out       an input or analog value is forced
ConfigBad   BOOL out       a wrong address, a function on a module not fitted,
or a table longer than the kept copy / not matching its settings
TermBits, ForcedBits  DWORD out   the first 32 digital terminals: state, forced
FnBits, OkBits        DWORD out   the first 32 digital functions: q, ok
AnaOkBits             DWORD out   the first 32 analog functions: ok
DigSet / Dig  ARRAY[*] OF UT_IO_DI_SET / UT_IO_DI   digital input functions: settings / live
AnaSet / Ana  ARRAY[*] OF UT_IO_AI_SET / UT_IO_AI   analog input functions: settings / live (raw)
DigImg       ARRAY[*] OF UT_IO_DCH   the digital input terminals (your IO code writes q / bad)
AnaImg       ARRAY[*] OF UT_IO_ACH   the analog input terminals (your IO code writes v / bad)
Mods         ARRAY[*] OF UT_IO_MOD   the module table (shared with UT_IO_MAP_OUT)
Force        ARRAY[*] OF UT_IO_FORCE the force slots (shared with UT_IO_MAP_OUT; never retained)
Data         UT_IO_MAP_DATA          set.forceTime; status, counts

WHAT IT DOES
For each function row it finds the channel (src, module, ch) through the
module table and gives your logic:
q / v   the value. Digital: after the NC setting (q TRUE = active) and
the debounce.
ok      TRUE only when the value came from a good channel (or a force).
fit     the function is mapped on this site (src not NONE, module fitted).
why     the reason when it is not good: UNUSED (not fitted: src NONE),
NOT_FITTED (its module is not fitted on this site), MISSING
(the module is not answering), BAD (the channel is stale or
bad), NO_MODULE / NO_CHANNEL (wrong address).
Wire q / v into a source's In and why into its InQ: a function not mapped
then answers 'not fitted' through the source's plug, and the block using it
skips that protection with no fault.
A function that is not good reads its failSafe value, never an ordinary
OFF, and its ok bit is FALSE: your logic decides what a lost signal means.
When the channel comes back, q follows it at once. With UnusedOff (the
default) a function not fitted on this site (src NONE) reads FALSE (analog
0.0): an option that is not installed reads "not active", while a fitted
one that is lost still reads its failSafe. A module not fitted
(NOT_FITTED) still reads failSafe.

An input channel may feed several functions. The image row's fn shows the
first function on it, for the IO page.

SETTINGS
The block keeps its own copy of DigSet, AnaSet and Data.set (a fixed
table: 32 digital, 8 analog rows). A write the block can't use (a source
number out of range, debounce over 60 s, an analog failSafe that is not a
number, force time 0 or over 10 min) is put back to the kept copy, with
sts.refused. Rows past the kept table still work, but are not kept: the
status is Config: array size.

FORCING (commissioning)
A force slot names a channel (kind DI or AI, src, module, ch), the value
(q for digital, v for analog) and is started with cmdForce. Inputs can be
forced in any mode. The force goes on the terminal, before the NC setting
and before scaling, as a test wire would: an NC function sees a forced ON
as "contact made" (inactive), and a forced analog raw value goes through
UT_ANALOG_IN's checks (force 2.0 mA to test a wire break). The debounce
is skipped while forced. The image keeps the real terminal value; only the
functions see the forced one. A forced channel on a missing module reads
as good while forced; the module still shows MISSING.
Each force ends by itself after set.forceTime (default 5 s, at most
10 min); cmdForce again starts the time again; cmdRelease or ReleaseAll
end it at once. Every force ends at power-up.

Status, most important first: Config: array size, Config: IO address,
Config: IO not fitted, Warning: IO forced (det.forceLeftS), Warning: IO
module missing, Warning: IO channel bad, Setting (the project's own
settings are bad and nothing good was kept: safe values used), OK. *)

FUNCTION_BLOCK UT_IO_MAP_IN
  VAR_INPUT
    ReleaseAll : BOOL; (* TRUE: release every input force now and refuse new ones *)
    UnusedOff : BOOL := TRUE; (* a function not fitted (src NONE) reads FALSE / 0.0, not its failSafe *)
  END_VAR
  VAR_OUTPUT
    AllOk : BOOL; (* every fitted function and fitted module is good *)
    AnyForced : BOOL; (* an input is forced *)
    ConfigBad : BOOL; (* a wrong address, a function on a module not fitted, a table size *)
    TermBits : DWORD; (* the first 32 digital terminals *)
    FnBits : DWORD; (* the first 32 digital functions: q *)
    OkBits : DWORD; (* the first 32 digital functions: ok *)
    ForcedBits : DWORD; (* the first 32 digital terminals: forced *)
    AnaOkBits : DWORD; (* the first 32 analog functions: ok *)
  END_VAR
  VAR RETAIN
    keptMap : UT_IO_MAP_SET;
    keptDig : ARRAY [1..32] OF UT_IO_DI_SET;
    keptAna : ARRAY [1..8] OF UT_IO_AI_SET;
    keptGood : BOOL;
  END_VAR
  VAR_IN_OUT
    DigSet : ARRAY [*] OF UT_IO_DI_SET; (* digital input functions: settings *)
    Dig : ARRAY [*] OF UT_IO_DI; (* digital input functions: live *)
    AnaSet : ARRAY [*] OF UT_IO_AI_SET; (* analog input functions: settings *)
    Ana : ARRAY [*] OF UT_IO_AI; (* analog input functions: live *)
    DigImg : ARRAY [*] OF UT_IO_DCH; (* digital input terminals *)
    AnaImg : ARRAY [*] OF UT_IO_ACH; (* analog input terminals *)
    Mods : ARRAY [*] OF UT_IO_MOD; (* module table *)
    Force : ARRAY [*] OF UT_IO_FORCE; (* force slots *)
    Data : UT_IO_MAP_DATA;
  END_VAR
  VAR
    kp : UT_KEEP;
    tCur : TIME;
    tPrev : TIME;
    stepMs : UINT;
    begun : BOOL;
    ft : TIME; (* the force time in use *)
    setOk : BOOL;
    why : UT_FAULT;
    sizeBad : BOOL;
    nD : DINT; (* digital rows *)
    nA : DINT; (* analog rows *)
    nDk : DINT; (* digital rows kept *)
    nAk : DINT;
    i : DINT;
    j : DINT;
    k : DINT;
    sj : DINT; (* the settings row of function row i *)
    m : DINT; (* module row found *)
    idx : DINT; (* image row found *)
    mLo : DINT;
    mHi : DINT;
    dLo : DINT;
    dHi : DINT;
    aLo : DINT;
    aHi : DINT;
    fLo : DINT;
    fHi : DINT;
    kind : UT_IO_KIND;
    src : UT_IO_SRC;
    modNo : USINT;
    ch : USINT;
    where : UT_IO_Q;
    r : BOOL;
    deb : UINT;
    fs : REAL;
    nForced : INT;
    nBad : INT;
    nAddr : INT;
    nNotFit : INT;
    nMissFn : INT;
    nChBad : INT;
    nMissMod : INT;
    leftMax : UINT;
    st : UT_STATUS;
    fid : UT_FAULT;
  END_VAR


tCur := TIME();
IF begun THEN
  stepMs := DINT_TO_UINT(LIMIT(0, TIME_TO_DINT(tCur - tPrev), 65535));
ELSE
  stepMs := 0;
END_IF;
tPrev := tCur;

sizeBad := UPPER_BOUND(DigSet, 1) - LOWER_BOUND(DigSet, 1) <> UPPER_BOUND(Dig, 1) - LOWER_BOUND(Dig, 1)
           OR UPPER_BOUND(AnaSet, 1) - LOWER_BOUND(AnaSet, 1) <> UPPER_BOUND(Ana, 1) - LOWER_BOUND(Ana, 1);
nD := MIN(UPPER_BOUND(DigSet, 1) - LOWER_BOUND(DigSet, 1), UPPER_BOUND(Dig, 1) - LOWER_BOUND(Dig, 1)) + 1;
nA := MIN(UPPER_BOUND(AnaSet, 1) - LOWER_BOUND(AnaSet, 1), UPPER_BOUND(Ana, 1) - LOWER_BOUND(Ana, 1)) + 1;
nDk := MIN(nD, 32);
nAk := MIN(nA, 8);
sizeBad := sizeBad OR nD > 32 OR nA > 8;

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
  sj := LOWER_BOUND(DigSet, 1) + i - 1;
  src := DigSet[sj].src;
  IF why = UT_F_NONE AND (DigSet[sj].debounceMs > 60000
     OR NOT (src = UT_IOS_NONE OR src = UT_IOS_BOARD OR src = UT_IOS_I2C OR src = UT_IOS_FIELD
             OR src = UT_IOS_REMOTE)) THEN
    why := UT_F_SETTING;
  END_IF;
END_FOR;
FOR i := 1 TO nA DO
  sj := LOWER_BOUND(AnaSet, 1) + i - 1;
  src := AnaSet[sj].src;
  fs := AnaSet[sj].failSafe;
  IF why = UT_F_NONE AND (NOT (fs = fs) OR ABS(fs) > 3.4E38
     OR NOT (src = UT_IOS_NONE OR src = UT_IOS_BOARD OR src = UT_IOS_I2C OR src = UT_IOS_FIELD
             OR src = UT_IOS_REMOTE)) THEN
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
fLo := LOWER_BOUND(Force, 1);
fHi := UPPER_BOUND(Force, 1);

(* 1. the image: nothing forced yet this scan *)
FOR j := dLo TO dHi DO
  DigImg[j].forced := FALSE;
  DigImg[j].fn := 0;
END_FOR;
FOR j := aLo TO aHi DO
  AnaImg[j].forced := FALSE;
  AnaImg[j].fn := 0;
END_FOR;

(* 2. the input modules *)
nMissMod := 0;
FOR k := mLo TO mHi DO
  IF Mods[k].kind = UT_IOK_DI OR Mods[k].kind = UT_IOK_AI THEN
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

(* 3. the force slots for inputs: mark the forced terminals. The image
   keeps the real terminal value; the functions take the forced one *)
nForced := 0;
leftMax := 0;
FOR j := fLo TO fHi DO
  kind := Force[j].kind;
  IF kind = UT_IOK_NONE THEN
    Force[j].active := FALSE;
    Force[j].state := UT_IOQ_UNUSED;
    Force[j].leftS := 0;
    Force[j].forceSeen := Force[j].cmdForce;
    Force[j].releaseSeen := Force[j].cmdRelease;
    Force[j].cmdForce := FALSE;
    Force[j].cmdRelease := FALSE;
  ELSIF kind = UT_IOK_DI OR kind = UT_IOK_AI THEN
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
      IF kind = UT_IOK_DI THEN
        IF idx < dLo OR idx > dHi THEN
          where := UT_IOQ_NO_CHANNEL;
        END_IF;
      ELSIF idx < aLo OR idx > aHi THEN
        where := UT_IOQ_NO_CHANNEL;
      END_IF;
    END_IF;
    IF UT_IO_FORCE_RUN(S := Force[j], Where := where, Permit := TRUE, Release := ReleaseAll OR NOT begun,
                       Now := tCur, ForceTime := ft) THEN
      Force[j].row := DINT_TO_INT(idx);
      IF kind = UT_IOK_DI THEN
        DigImg[idx].forced := TRUE;
      ELSE
        AnaImg[idx].forced := TRUE;
      END_IF;
      nForced := nForced + 1;
      IF Force[j].leftS > leftMax THEN
        leftMax := Force[j].leftS;
      END_IF;
    END_IF;
  END_IF;
END_FOR;

(* 4. the digital input functions *)
nBad := 0;
nAddr := 0;
nNotFit := 0;
nMissFn := 0;
nChBad := 0;
FnBits := 0;
OkBits := 0;
FOR i := 1 TO nD DO
  sj := LOWER_BOUND(DigSet, 1) + i - 1;
  j := LOWER_BOUND(Dig, 1) + i - 1;
  src := DigSet[sj].src;
  idx := 0;
  m := mLo - 1;
  IF src = UT_IOS_NONE THEN
    where := UT_IOQ_UNUSED;
  ELSE
    modNo := DigSet[sj].module;
    ch := DigSet[sj].ch;
    FOR k := mLo TO mHi DO
      IF m < mLo AND Mods[k].kind = UT_IOK_DI AND Mods[k].src = src AND Mods[k].module = modNo THEN
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
      ELSE
        Mods[m].used := Mods[m].used + 1;
        IF DigImg[idx].fn = 0 AND i <= 255 THEN
          DigImg[idx].fn := DINT_TO_USINT(i);
        END_IF;
        IF DigImg[idx].forced THEN
          where := UT_IOQ_FORCED;
        ELSIF NOT Mods[m].fitted THEN
          where := UT_IOQ_NOT_FITTED;
        ELSIF NOT Mods[m].ok THEN
          where := UT_IOQ_MISSING;
        ELSIF DigImg[idx].bad THEN
          where := UT_IOQ_BAD;
        ELSE
          where := UT_IOQ_OK;
        END_IF;
      END_IF;
    END_IF;
  END_IF;
  IF where = UT_IOQ_OK OR where = UT_IOQ_FORCED THEN
    r := DigImg[idx].q;
    IF where = UT_IOQ_FORCED THEN
      FOR k := fLo TO fHi DO
        IF Force[k].active AND Force[k].kind = UT_IOK_DI AND INT_TO_DINT(Force[k].row) = idx THEN
          r := Force[k].q;
        END_IF;
      END_FOR;
    END_IF;
    r := r XOR DigSet[sj].nc;
    deb := MIN(DigSet[sj].debounceMs, 60000);
    IF where = UT_IOQ_FORCED OR NOT Dig[j].ok THEN
      Dig[j].q := r;                  (* forced, or the channel just came back: no debounce *)
      Dig[j].raw := r;
      Dig[j].left := 0;
    ELSE
      IF r <> Dig[j].raw THEN
        Dig[j].raw := r;
        Dig[j].left := deb;
      ELSIF Dig[j].left > stepMs THEN
        Dig[j].left := Dig[j].left - stepMs;
      ELSE
        Dig[j].left := 0;
      END_IF;
      IF Dig[j].left > deb THEN
        Dig[j].left := deb;           (* the debounce was shortened *)
      END_IF;
      IF Dig[j].left = 0 THEN
        Dig[j].q := Dig[j].raw;
      END_IF;
    END_IF;
    Dig[j].ok := TRUE;
  ELSIF where = UT_IOQ_UNUSED AND UnusedOff THEN
    Dig[j].q := FALSE;              (* not fitted on this site: not active *)
    Dig[j].ok := FALSE;
  ELSE
    Dig[j].q := DigSet[sj].failSafe;
    Dig[j].ok := FALSE;
    IF where <> UT_IOQ_UNUSED THEN
      nBad := nBad + 1;
    END_IF;
  END_IF;
  Dig[j].why := where;
  Dig[j].fit := where <> UT_IOQ_UNUSED AND where <> UT_IOQ_NOT_FITTED;
  CASE where OF
  UT_IOQ_NO_MODULE, UT_IOQ_NO_CHANNEL: nAddr := nAddr + 1;
  UT_IOQ_NOT_FITTED: nNotFit := nNotFit + 1;
  UT_IOQ_MISSING: nMissFn := nMissFn + 1;
  UT_IOQ_BAD: nChBad := nChBad + 1;
  END_CASE;
  IF i <= 32 THEN
    FnBits := UT_BIT_PUT(Bits := FnBits, Bit := DINT_TO_SINT(i - 1), Value := Dig[j].q);
    OkBits := UT_BIT_PUT(Bits := OkBits, Bit := DINT_TO_SINT(i - 1), Value := Dig[j].ok);
  END_IF;
END_FOR;

(* 5. the analog input functions *)
AnaOkBits := 0;
FOR i := 1 TO nA DO
  sj := LOWER_BOUND(AnaSet, 1) + i - 1;
  j := LOWER_BOUND(Ana, 1) + i - 1;
  src := AnaSet[sj].src;
  idx := 0;
  m := mLo - 1;
  IF src = UT_IOS_NONE THEN
    where := UT_IOQ_UNUSED;
  ELSE
    modNo := AnaSet[sj].module;
    ch := AnaSet[sj].ch;
    FOR k := mLo TO mHi DO
      IF m < mLo AND Mods[k].kind = UT_IOK_AI AND Mods[k].src = src AND Mods[k].module = modNo THEN
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
      ELSE
        Mods[m].used := Mods[m].used + 1;
        IF AnaImg[idx].fn = 0 AND i <= 255 THEN
          AnaImg[idx].fn := DINT_TO_USINT(i);
        END_IF;
        IF AnaImg[idx].forced THEN
          where := UT_IOQ_FORCED;
        ELSIF NOT Mods[m].fitted THEN
          where := UT_IOQ_NOT_FITTED;
        ELSIF NOT Mods[m].ok THEN
          where := UT_IOQ_MISSING;
        ELSIF AnaImg[idx].bad THEN
          where := UT_IOQ_BAD;
        ELSE
          where := UT_IOQ_OK;
        END_IF;
      END_IF;
    END_IF;
  END_IF;
  IF where = UT_IOQ_OK OR where = UT_IOQ_FORCED THEN
    Ana[j].v := AnaImg[idx].v;
    IF where = UT_IOQ_FORCED THEN
      FOR k := fLo TO fHi DO
        IF Force[k].active AND Force[k].kind = UT_IOK_AI AND INT_TO_DINT(Force[k].row) = idx THEN
          Ana[j].v := Force[k].v;
        END_IF;
      END_FOR;
    END_IF;
    Ana[j].ok := TRUE;
  ELSIF where = UT_IOQ_UNUSED AND UnusedOff THEN
    Ana[j].v := 0.0;                (* not fitted on this site *)
    Ana[j].ok := FALSE;
  ELSE
    fs := AnaSet[sj].failSafe;
    IF NOT (fs = fs) OR ABS(fs) > 3.4E38 THEN
      fs := 0.0;
    END_IF;
    Ana[j].v := fs;
    Ana[j].ok := FALSE;
    IF where <> UT_IOQ_UNUSED THEN
      nBad := nBad + 1;
    END_IF;
  END_IF;
  Ana[j].why := where;
  Ana[j].fit := where <> UT_IOQ_UNUSED AND where <> UT_IOQ_NOT_FITTED;
  CASE where OF
  UT_IOQ_NO_MODULE, UT_IOQ_NO_CHANNEL: nAddr := nAddr + 1;
  UT_IOQ_NOT_FITTED: nNotFit := nNotFit + 1;
  UT_IOQ_MISSING: nMissFn := nMissFn + 1;
  UT_IOQ_BAD: nChBad := nChBad + 1;
  END_CASE;
  IF i <= 32 THEN
    AnaOkBits := UT_BIT_PUT(Bits := AnaOkBits, Bit := DINT_TO_SINT(i - 1), Value := Ana[j].ok);
  END_IF;
END_FOR;

(* 6. the terminals for the IO page *)
TermBits := 0;
ForcedBits := 0;
FOR j := dLo TO MIN(dHi, dLo + 31) DO
  TermBits := UT_BIT_PUT(Bits := TermBits, Bit := DINT_TO_SINT(j - dLo), Value := DigImg[j].q);
  ForcedBits := UT_BIT_PUT(Bits := ForcedBits, Bit := DINT_TO_SINT(j - dLo), Value := DigImg[j].forced);
END_FOR;

(* 7. status *)
begun := TRUE;
AnyForced := nForced > 0;
ConfigBad := sizeBad OR nAddr > 0 OR nNotFit > 0;
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