(* UT_HOA — Hand / Off / Auto for an output with no block of its own (a lamp,
a heater, a fan, a solenoid). Never drive a motor through UT_HOA: use
UT_MOTOR (in Hand the output comes back when Interlock returns unless
handByStart).

Off: the output off. Hand: HandCmd (with handByStart: a Start / cmdStart
latches it, Stop / cmdStop / Interlock drop it). Auto: Run per
set.run.style (HELD / TOGGLE / KEEPALIVE), Start / Stop latch. Interlock
FALSE forces the output off in every mode. The mode (Mode pin on change,
cmdMode, selector per modeSource) is kept in set.mode. handTimeout: Hand ->
Off after this (a selector held in Hand keeps the output off until it is
moved). handPowerUp OFF: a Hand comes back Off after a power cut. *)

FUNCTION_BLOCK UT_HOA
  VAR_INPUT
    Run : BOOL; (* output wanted in Auto, per set.run.style *)
    Start : BOOL R_EDGE; (* Auto latch on; Hand on (handByStart) *)
    Stop : BOOL R_EDGE; (* Auto latch off; Hand off *)
    Mode : INT := -1; (* 0 Off, 1 Hand, 2 Auto; acts on change *)
    HandCmd : BOOL := TRUE; (* output wanted in Hand *)
    SwHand : BOOL;
    SwAuto : BOOL;
    Interlock : BOOL := TRUE; (* FALSE forces the output off in every mode *)
  END_VAR
  VAR_OUTPUT
    Out : BOOL;
    ModeNow : UT_MODE;
    IsOff : BOOL;
    IsHand : BOOL;
    IsAuto : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_HOA_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_HOA_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    modeSel : UT_MODE_SELECT;
    runIn : UT_RUN_INPUT;
    ok : BOOL;
    hStart : BOOL;
    hStop : BOOL;
    cStart : BOOL;
    cStop : BOOL;
    latch : BOOL;
    puHold : BOOL; (* a Hand at power-up with handPowerUp OFF: off until the mode changes *)
    handEnded : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := (Data.set.modeSource = UT_SRC_HMI OR Data.set.modeSource = UT_SRC_SWITCH OR Data.set.modeSource = UT_SRC_REMOTE)
      AND (Data.set.powerUp = UT_PU_LAST OR Data.set.powerUp = UT_PU_OFF)
      AND (Data.set.handPowerUp = UT_HPU_OFF OR Data.set.handPowerUp = UT_HPU_KEEP)
      AND Data.set.handTimeout >= T#0s
      AND (Data.set.run.style = UT_RS_HELD OR Data.set.run.style = UT_RS_TOGGLE
           OR (Data.set.run.style = UT_RS_KEEPALIVE AND Data.set.run.keepAlive > T#0s));
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := TRUE;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
cStart := Data.cmdStart AND NOT hStart;   (* once per request, even when held on *)
hStart := Data.cmdStart;
Data.cmdStart := FALSE;
cStop := Data.cmdStop AND NOT hStop;
hStop := Data.cmdStop;
Data.cmdStop := FALSE;

modeSel(SwAuto := SwAuto, SwHand := SwHand, ForceOff := FALSE, HandOn := ModeNow = UT_MODE_HAND, HandToOff := TRUE,
        AllowOOS := FALSE, Source := Data.set.modeSource, ModeReq := Mode, PowerUp := Data.set.powerUp,
        HandPowerUp := Data.set.handPowerUp, HandMax := MAX(Data.set.handTimeout, T#0s), CmdMode := Data.cmdMode,
        Choice := Data.set.mode);
IF keep.PowerUp AND modeSel.Mode = UT_MODE_HAND AND Data.set.handPowerUp <> UT_HPU_KEEP THEN
  puHold := TRUE;                (* a selector found in Hand: off until it is moved *)
END_IF;
IF modeSel.Mode <> UT_MODE_HAND THEN
  puHold := FALSE;
END_IF;
handEnded := (modeSel.HandUp OR puHold) AND modeSel.Mode = UT_MODE_HAND;
IF handEnded THEN
  ModeNow := UT_MODE_OFF;
ELSE
  ModeNow := modeSel.Mode;
END_IF;

runIn(Run := Run, Start := Start, Stop := Stop, CmdStart := cStart, CmdStop := cStop,
      Drop := ModeNow <> UT_MODE_AUTO OR NOT Interlock, Linked := FALSE, TargetDone := FALSE, HasTarget := FALSE,
      Set := Data.set.run);
IF ModeNow <> UT_MODE_HAND OR NOT Interlock OR Stop OR cStop THEN
  latch := FALSE;
ELSIF Start OR cStart THEN
  latch := TRUE;
END_IF;
CASE ModeNow OF
UT_MODE_HAND:
  Out := HandCmd AND (latch OR NOT Data.set.handByStart);
UT_MODE_AUTO:
  Out := runIn.Request;
ELSE
  Out := FALSE;
END_CASE;
Out := Out AND Interlock;
IsOff := ModeNow = UT_MODE_OFF;
IsHand := ModeNow = UT_MODE_HAND;
IsAuto := ModeNow = UT_MODE_AUTO;
Data.handLeft := modeSel.HandLeft;

stF := UT_F_NONE;
IF handEnded THEN
  stCode := UT_ST_SELECTOR_HAND;   (* a selector held in Hand *)
ELSIF ModeNow = UT_MODE_OFF THEN
  stCode := UT_ST_OFF;
ELSIF NOT Interlock AND ((ModeNow = UT_MODE_HAND AND HandCmd) OR (ModeNow = UT_MODE_AUTO AND (Run OR runIn.Latched))) THEN
  stCode := UT_ST_INTERLOCK;
ELSIF NOT ok OR runIn.BadSetting OR modeSel.BadSetting THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_SETTING;
ELSIF ModeNow = UT_MODE_HAND AND Out THEN
  stCode := UT_ST_RUN_HAND;
ELSIF ModeNow = UT_MODE_AUTO AND Out THEN
  stCode := UT_ST_RUN_AUTO;
ELSIF ModeNow = UT_MODE_HAND THEN
  stCode := UT_ST_IDLE_HAND;
ELSE
  stCode := UT_ST_IDLE_NO_DEMAND;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.mode := ModeNow;
Data.sts.out := Out;
Data.sts.selectorFault := modeSel.SwFault;

END_FUNCTION_BLOCK