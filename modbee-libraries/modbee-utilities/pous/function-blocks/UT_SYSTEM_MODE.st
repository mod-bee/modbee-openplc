(* UT_SYSTEM_MODE — the plant's own mode: Off / Manual / Auto, the auto type
(1..autoTypes), a manual run, and the power-on delay.

The mode is UT_MODE_SELECT's: the Mode pin (0 Off, 1 Manual, 2 Auto; acts
on change; anything else is refused with a warning), cmdMode, or the
selector SwManual / SwAuto per set.modeSource; it comes back after a power
cut per set.powerUp (LAST / OFF). ForceOff holds it Off (the choice is
kept). The auto type comes from the AutoType pin (on change) or
cmdAutoType; Auto1..Auto4 are Auto with that type.

Manual: ManualRun is on while Manual and a run is requested (Run per
set.run.style, Start / cmdStart latch, Stop / cmdStop wins), after the
power-on delay, for at most manualMaxRun. A held Run must be released and
given again before it runs after power-up, a mode change or manualMaxRun
(a held or stale request never starts the plant by itself).
PowerUpHold is TRUE for powerOnDelay after power-up (-> the pumps and the
process Permissive). EndCode says why an Auto run must end now (Off:
SWITCHED_OFF, Manual: SYS_MANUAL; NONE in Auto) -> the run blocks'
Abort / AbortCode. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_SYSTEM_MODE
  VAR_INPUT
    Mode : INT := -1; (* 0 Off, 1 Manual, 2 Auto; acts on change *)
    AutoType : INT := -1; (* 1..autoTypes; acts on change *)
    Run : BOOL; (* manual run request per set.run.style *)
    Start : BOOL R_EDGE; (* manual run on (latched) *)
    Stop : BOOL R_EDGE; (* manual run off (wins) *)
    ForceOff : BOOL; (* holds the plant Off (the choice is kept) *)
    SwManual : BOOL; (* selector *)
    SwAuto : BOOL;
  END_VAR
  VAR_OUTPUT
    IsAuto : BOOL;
    IsManual : BOOL;
    IsOff : BOOL;
    NotOff : BOOL;
    Auto1 : BOOL;
    Auto2 : BOOL;
    Auto3 : BOOL;
    Auto4 : BOOL;
    AutoTypeNow : INT; (* the type in use (0 = invalid setting) *)
    ModeNow : UT_SYS_MODE;
    ManualRun : BOOL;
    PowerUpHold : BOOL;
    EndCode : UT_STOP; (* why an Auto run must end now *)
    Changed : BOOL; (* one scan: the mode or the auto type changed *)
    Warning : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_SYSTEM_MODE_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_SYSTEM_MODE_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    modeSel : UT_MODE_SELECT;
    runIn : UT_RUN_INPUT;
    ok : BOOL;
    cfgId : UT_FAULT;
    tCur : TIME;
    started : BOOL;
    startAt : TIME;
    modeReq : INT;
    modePrev : INT := -1;
    typePrev : INT := -1;
    typeNow : INT;
    typeWas : INT;
    modeRefused : BOOL;
    hStart : BOOL;
    hStop : BOOL;
    blocked : BOOL; (* a held Run must be released first *)
    maxHit : BOOL;
    runOn : BOOL;
    runPrev : BOOL;
    runAt : TIME;
    sysNow : UT_SYS_MODE;
    sysWas : UT_SYS_MODE;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


tCur := TIME();
IF NOT started THEN
  started := TRUE;
  startAt := tCur;
  blocked := TRUE;               (* a Run held at power-up must be released first *)
  modePrev := Mode;
  typePrev := AutoType;
END_IF;
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;

(* the AutoType pin and cmdAutoType act on a new value *)
IF AutoType <> typePrev THEN
  IF AutoType >= 1 AND AutoType <= Data.set.autoTypes THEN
    Data.set.autoType := AutoType;
  END_IF;
  typePrev := AutoType;
END_IF;
IF Data.cmdAutoType >= 0 THEN
  IF Data.cmdAutoType >= 1 AND Data.cmdAutoType <= Data.set.autoTypes THEN
    Data.set.autoType := Data.cmdAutoType;
  ELSE
    Data.sts.refused := UT_F_AUTO_TYPE;
    Data.sts.refusedWhy := UT_F_AUTO_TYPE;
  END_IF;
  Data.cmdAutoType := -1;
END_IF;
ok := UT_SYSTEM_MODE_CHECK(S := Data.set, Id => cfgId);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := cfgId;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_SYSTEM_MODE_CHECK(S := Data.set, Id => cfgId);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

(* the mode: the pin acts on change; 0 / 1 / 2 only *)
modeReq := -1;
IF Mode <> modePrev THEN
  IF Mode >= 0 AND Mode <= 2 THEN
    modeReq := Mode;
    modeRefused := FALSE;
  ELSIF Mode <> -1 THEN
    modeRefused := TRUE;
  END_IF;
  modePrev := Mode;
END_IF;
IF Data.cmdMode = 3 THEN
  Data.cmdMode := -1;            (* OOS is not a plant mode *)
  modeRefused := TRUE;
END_IF;
modeSel(SwAuto := SwAuto, SwHand := SwManual, ForceOff := ForceOff OR NOT ok, HandOn := FALSE, HandToOff := FALSE,
        AllowOOS := FALSE, Source := Data.set.modeSource, ModeReq := modeReq, PowerUp := Data.set.powerUp,
        HandPowerUp := UT_HPU_KEEP, HandMax := T#0s, CmdMode := Data.cmdMode, Choice := Data.set.mode);
CASE modeSel.Mode OF
UT_MODE_AUTO: sysNow := UT_SYS_AUTO;
UT_MODE_HAND: sysNow := UT_SYS_MANUAL;
ELSE
  sysNow := UT_SYS_OFF;
END_CASE;
IF ok THEN typeNow := Data.set.autoType; ELSE typeNow := 0; END_IF;
Changed := sysNow <> sysWas OR typeNow <> typeWas;
IF sysNow <> sysWas THEN
  blocked := TRUE;               (* a mode change: a held Run must be released *)
END_IF;
sysWas := sysNow;
typeWas := typeNow;

(* the power-on delay *)
PowerUpHold := tCur - startAt < Data.set.powerOnDelay;
IF PowerUpHold THEN
  Data.det.powerUpLeft := Data.set.powerOnDelay - (tCur - startAt);
ELSE
  Data.det.powerUpLeft := T#0s;
END_IF;

(* the manual run *)
runIn(Run := Run AND NOT blocked, Start := Start OR (Data.cmdStart AND NOT hStart),
      Stop := Stop OR (Data.cmdStop AND NOT hStop) OR maxHit, CmdStart := FALSE, CmdStop := FALSE,
      Drop := sysNow <> UT_SYS_MANUAL OR NOT ok, Linked := FALSE, TargetDone := FALSE, HasTarget := FALSE,
      Set := Data.set.run);
hStart := Data.cmdStart;
Data.cmdStart := FALSE;
hStop := Data.cmdStop;
Data.cmdStop := FALSE;
IF NOT Run THEN
  blocked := FALSE;
  maxHit := FALSE;
END_IF;
runOn := sysNow = UT_SYS_MANUAL AND runIn.Request AND NOT runIn.BadSetting AND NOT PowerUpHold;
IF runOn AND NOT runPrev THEN
  runAt := tCur;
END_IF;
IF runOn AND Data.set.manualMaxRun > T#0s AND tCur - runAt >= Data.set.manualMaxRun THEN
  runOn := FALSE;
  maxHit := TRUE;                (* the request must be released and given again *)
  blocked := Run;
  Data.sts.stopReason := UT_STOP_MAX_RUN;
ELSIF runPrev AND NOT runOn AND NOT maxHit THEN
  IF sysNow <> UT_SYS_MANUAL THEN
    Data.sts.stopReason := UT_STOP_SWITCHED_OFF;
  ELSE
    Data.sts.stopReason := UT_STOP_OPERATOR;
  END_IF;
END_IF;
IF runOn THEN
  Data.det.runTime := tCur - runAt;
  IF Data.set.manualMaxRun > T#0s THEN
    Data.det.timeLeft := Data.set.manualMaxRun - (tCur - runAt);
  ELSE
    Data.det.timeLeft := T#0s;
  END_IF;
ELSE
  Data.det.timeLeft := T#0s;
END_IF;
runPrev := runOn;

(* outputs *)
ModeNow := sysNow;
IsAuto := sysNow = UT_SYS_AUTO;
IsManual := sysNow = UT_SYS_MANUAL;
IsOff := sysNow = UT_SYS_OFF;
NotOff := NOT IsOff;
AutoTypeNow := typeNow;
Auto1 := IsAuto AND typeNow = 1;
Auto2 := IsAuto AND typeNow = 2;
Auto3 := IsAuto AND typeNow = 3;
Auto4 := IsAuto AND typeNow = 4;
ManualRun := runOn;
CASE sysNow OF
UT_SYS_AUTO: EndCode := UT_STOP_NONE;
UT_SYS_MANUAL: EndCode := UT_STOP_SYS_MANUAL;
ELSE
  EndCode := UT_STOP_SWITCHED_OFF;
END_CASE;
Warning := modeRefused OR modeSel.SwFault OR maxHit;

stF := UT_F_NONE;
IF NOT ok THEN
  stCode := UT_ST_CONFIG;
  stF := cfgId;
ELSIF PowerUpHold THEN
  stCode := UT_ST_POWER_ON_DELAY;
ELSIF ForceOff THEN
  stCode := UT_ST_FORCED_OFF;
ELSIF modeRefused THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_MODE_CHOICE;
ELSIF sysNow = UT_SYS_AUTO THEN
  stCode := UT_ST_AUTO;
ELSIF sysNow = UT_SYS_MANUAL AND runOn THEN
  stCode := UT_ST_MANUAL_LOCAL;
ELSIF sysNow = UT_SYS_MANUAL AND maxHit THEN
  stCode := UT_ST_MANUAL_MAX_RUN;
ELSIF sysNow = UT_SYS_MANUAL THEN
  stCode := UT_ST_IDLE_MANUAL;
ELSE
  stCode := UT_ST_OFF;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := NOT ok, Check := NOT IsAuto, OutOfSpec := Warning, Maint := FALSE);
Data.sts.mode := sysNow;
Data.sts.autoType := typeNow;
Data.sts.manualRun := runOn;
Data.sts.powerUpHold := PowerUpHold;
Data.sts.warning := Warning;

END_FUNCTION_BLOCK