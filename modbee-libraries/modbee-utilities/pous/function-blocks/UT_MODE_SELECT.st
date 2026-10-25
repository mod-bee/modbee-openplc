(* UT_MODE_SELECT — Off / Hand / Auto / Out of service, from the HMI, a
selector switch, or both (local / remote), with the Hand timer and the
power-up rules. Used inside every motor, valve, UT_HOA, pump, dose, zone
program and system mode; usable on its own.

Source  UT_SRC_HMI     the operator's choice (Choice): CmdMode / ModeReq
UT_SRC_SWITCH  the selector: SwHand, SwAuto, neither = Off
UT_SRC_REMOTE  the selector's Off and Hand act locally; its Auto
hands control to the operator's choice

Choice is the kept operator choice: the owner's Data.set.mode (a standalone
UT_MODE_SELECT wires it to a RETAIN variable). It is written only when the
operator changes it. CmdMode (0 Off, 1 Hand, 2 Auto, 3 OOS) acts once when a
new value arrives and is set back to -1; ModeReq (a pin) acts on change. An
invalid code is ignored. Both selector contacts made at once: Off, SwFault.

Power-up (PowerUp): LAST = the mode comes back; OFF = the choice goes to Off
and a selector found in Hand or Auto is held at Off until it is moved.
HandPowerUp OFF: a Hand choice comes back as Off (KEEP: as Hand; a motor
still needs a fresh Start). ForceOff holds Off; the choice is kept.

Hand timer: while Mode is Hand and HandOn, HandMax (0 = none) counts;
reached: HandUp, and with HandToOff the choice goes back to Off. Garbage
Source / Choice: Off and BadSetting; garbage PowerUp / HandPowerUp act as
OFF with BadSetting. *)

FUNCTION_BLOCK UT_MODE_SELECT
  VAR_INPUT
    SwAuto : BOOL; (* selector in Auto *)
    SwHand : BOOL; (* selector in Hand *)
    ForceOff : BOOL; (* TRUE holds the mode at Off (the choice is kept) *)
    HandOn : BOOL; (* what counts for the Hand timer *)
    HandToOff : BOOL; (* HandMax reached: TRUE = back to Off, FALSE = HandUp only *)
    AllowOOS : BOOL := TRUE;
    Source : UT_MODE_SOURCE;
    ModeReq : INT := -1; (* mode request from a pin, acts on change *)
    PowerUp : UT_POWERUP;
    HandPowerUp : UT_HAND_POWERUP := UT_HPU_KEEP;
    HandMax : TIME; (* Hand time limit (0 = none) *)
  END_VAR
  VAR_OUTPUT
    Auto : BOOL;
    Mode : UT_MODE;
    EnteredOff : BOOL; (* one scan: the mode has just changed to Off *)
    Changed : BOOL; (* one scan: the mode has just changed *)
    HeldOff : BOOL; (* Off because of ForceOff or the power-up rule *)
    Remote : BOOL; (* the mode comes from the operator's choice now *)
    SwFault : BOOL; (* both selector contacts made *)
    HandUp : BOOL; (* the Hand limit is reached *)
    BadSetting : BOOL;
    HmiChoice : UT_MODE;
    HandLeft : TIME; (* Hand time left (0 = none counting) *)
  END_VAR
  VAR_IN_OUT
    CmdMode : INT; (* HMI request, set back to -1 *)
    Choice : UT_MODE; (* the kept operator choice *)
  END_VAR
  VAR NON_RETAIN
    started : BOOL; (* FALSE until the first scan after power-up *)
  END_VAR
  VAR
    selector : UT_MODE;
    prevMode : UT_MODE;
    cmdSeen : INT := -1;
    reqSeen : INT := -1;
    puHold : BOOL;
    puSel : UT_MODE;
    req : INT;
    choiceOk : BOOL;
    handSince : TIME;
    handCounting : BOOL;
    tNow : TIME;
  END_VAR


tNow := TIME();
BadSetting := FALSE;
(* requests: the HMI once per new value, the pin on change *)
req := -1;
IF ModeReq <> reqSeen THEN
  req := ModeReq;
END_IF;
reqSeen := ModeReq;
IF CmdMode <> -1 AND CmdMode <> cmdSeen THEN
  req := CmdMode;
END_IF;
cmdSeen := CmdMode;
CmdMode := -1;
CASE req OF
0: Choice := UT_MODE_OFF;
1: Choice := UT_MODE_HAND;
2: Choice := UT_MODE_AUTO;
3: IF AllowOOS THEN Choice := UT_MODE_OOS; END_IF;
END_CASE;

IF SwHand AND NOT SwAuto THEN
  selector := UT_MODE_HAND;
ELSIF SwAuto AND NOT SwHand THEN
  selector := UT_MODE_AUTO;
ELSE
  selector := UT_MODE_OFF;
END_IF;
SwFault := SwHand AND SwAuto;

(* power-up *)
IF NOT started THEN
  started := TRUE;
  IF PowerUp <> UT_PU_LAST THEN  (* OFF, or garbage: the safe side *)
    Choice := UT_MODE_OFF;
    puSel := selector;
    puHold := selector <> UT_MODE_OFF;
  END_IF;
  IF HandPowerUp <> UT_HPU_KEEP AND Choice = UT_MODE_HAND THEN
    Choice := UT_MODE_OFF;
  END_IF;
END_IF;
IF NOT (PowerUp = UT_PU_LAST OR PowerUp = UT_PU_OFF) OR NOT (HandPowerUp = UT_HPU_OFF OR HandPowerUp = UT_HPU_KEEP) THEN
  BadSetting := TRUE;
END_IF;
IF puHold AND selector <> puSel THEN
  puHold := FALSE;
END_IF;

choiceOk := Choice = UT_MODE_OFF OR Choice = UT_MODE_HAND OR Choice = UT_MODE_AUTO
            OR (Choice = UT_MODE_OOS AND AllowOOS);
IF choiceOk THEN
  HmiChoice := Choice;
ELSE
  HmiChoice := UT_MODE_OFF;
  BadSetting := TRUE;
END_IF;
HeldOff := ForceOff;
Remote := FALSE;
CASE Source OF
UT_SRC_SWITCH:
  Mode := selector;
  HeldOff := HeldOff OR (puHold AND selector <> UT_MODE_OFF);
UT_SRC_REMOTE:
  IF selector = UT_MODE_AUTO THEN
    Mode := HmiChoice;
    Remote := TRUE;
  ELSE
    Mode := selector;
    HeldOff := HeldOff OR (puHold AND selector = UT_MODE_HAND);
  END_IF;
UT_SRC_HMI:
  Mode := HmiChoice;
  Remote := TRUE;
ELSE
  Mode := UT_MODE_OFF;
  BadSetting := TRUE;
END_CASE;
IF HeldOff THEN
  Mode := UT_MODE_OFF;
END_IF;

(* the Hand timer *)
HandUp := FALSE;
HandLeft := T#0s;
IF Mode = UT_MODE_HAND AND HandOn AND HandMax > T#0s THEN
  IF NOT handCounting THEN
    handCounting := TRUE;
    handSince := tNow;
  END_IF;
  IF tNow - handSince >= HandMax THEN
    HandUp := TRUE;
    IF HandToOff THEN
      Choice := UT_MODE_OFF;
      IF Source <> UT_SRC_SWITCH AND NOT (Source = UT_SRC_REMOTE AND selector <> UT_MODE_AUTO) THEN
        Mode := UT_MODE_OFF;
      END_IF;
    END_IF;
  ELSE
    HandLeft := HandMax - (tNow - handSince);
  END_IF;
ELSE
  handCounting := FALSE;
END_IF;

Auto := Mode = UT_MODE_AUTO;
Changed := Mode <> prevMode;
EnteredOff := Changed AND Mode = UT_MODE_OFF;
prevMode := Mode;

END_FUNCTION_BLOCK