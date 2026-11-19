(* FB_Cmd — command arbiter for two masters: the local one (panel HMI) and the remote one (SCADA / IoT).
Pins: nLocalCommandBits / nRemoteCommandBits (command bits; a rising edge acts), nLocalModeRequest / nRemoteModeRequest (a mode request, acts on
a change to 0..15), nLocalSelection / nRemoteSelection (a selection, acts on a change to 0 or more), bRemoteAllowed (FALSE:
local control) -> nCommandBits and bCommandBit0..bCommandBit7 (the accepted bits, one scan), nModeRequest / nSelection (the accepted request, one
scan, else -1), bRequestRefused (one scan: a remote request was refused). refData: its record.
Stop / off bits (set.nStopBits) and mode 0 win over everything else in a scan; local wins over remote.
bRemoteAllowed FALSE: remote requests are refused (bRequestRefused, sts.nRemoteRefusedCount), except the stop bits and mode 0
when set.bRemoteStopUnderLocal. set.nLocalOnlyBits bits are never taken from the remote master; set.nRemoteAllowedModeBits says which
mode codes it may ask for; set.bRemoteMaySelect whether it may change the selection. Every value of the settings is
usable: they are kept by the block (restored at power-up), never put back. No errors of its own. *)

FUNCTION_BLOCK FB_Cmd
  VAR_INPUT
    nLocalCommandBits : DWORD; (* command bits (rising edge acts) *)
    nRemoteCommandBits : DWORD; (* command bits from the remote master (a rising bit acts) *)
    nLocalModeRequest : INT := -1; (* mode request (acts on a change to 0..15) *)
    nRemoteModeRequest : INT := -1; (* mode request from the remote master (acts on a change to 0..15) *)
    nLocalSelection : INT := -1; (* selection (auto type, preset, route ...) *)
    nRemoteSelection : INT := -1; (* selection from the remote master *)
    bRemoteAllowed : BOOL := TRUE; (* FALSE: local control *)
    refData : REFERENCE TO ST_CmdData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bCommandBit0 : BOOL; (* command bit 0 accepted (one scan) *)
    bCommandBit1 : BOOL; (* command bit 1 accepted (one scan) *)
    bCommandBit2 : BOOL; (* command bit 2 accepted (one scan) *)
    bCommandBit3 : BOOL; (* command bit 3 accepted (one scan) *)
    bCommandBit4 : BOOL; (* command bit 4 accepted (one scan) *)
    bCommandBit5 : BOOL; (* command bit 5 accepted (one scan) *)
    bCommandBit6 : BOOL; (* command bit 6 accepted (one scan) *)
    bCommandBit7 : BOOL; (* command bit 7 accepted (one scan) *)
    nCommandBits : DWORD; (* accepted bits, one scan *)
    nModeRequest : INT; (* accepted mode request, one scan, else -1 *)
    nSelection : INT; (* accepted selection, one scan, else -1 *)
    bRequestRefused : BOOL; (* one scan: a remote request was refused *)
  END_VAR
  VAR RETAIN
    stKept : ST_CmdSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    bStarted : BOOL;
    nLocPrev : DWORD;
    nRemPrev : DWORD;
    nLocModePrev : INT;
    nRemModePrev : INT;
    nLocSelPrev : INT;
    nRemSelPrev : INT;
  END_VAR
  VAR_TEMP
    nLocEdge : DWORD;
    nRemEdge : DWORD;
    nRemMask : DWORD;
    nRemOk : DWORD;
    nRemBad : DWORD;
    nAll : DWORD;
    nLocMode : INT;
    nRemMode : INT;
    nLocSel : INT;
    nRemSel : INT;
    bModeBad : BOOL;
    bSelBad : BOOL;
    bLocUsed : BOOL;
    bRemUsed : BOOL;
  END_VAR


bRequestRefused := FALSE;
IF NOT __ISVALIDREF(refData) THEN
  nCommandBits := 0;
  nModeRequest := -1;
  nSelection := -1;
  RETURN;
END_IF;
IF NOT bStarted THEN
  bStarted := TRUE;
  (* kept settings: every value is usable, nothing to put back *)
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    nKeptLayout := cLayout;
  END_IF;
  nLocPrev := nLocalCommandBits;
  nRemPrev := nRemoteCommandBits;
  nLocModePrev := nLocalModeRequest;
  nRemModePrev := nRemoteModeRequest;
  nLocSelPrev := nLocalSelection;
  nRemSelPrev := nRemoteSelection;
END_IF;
stKept := refData.set;

(* each master's new requests *)
nLocEdge := nLocalCommandBits AND NOT nLocPrev;
nRemEdge := nRemoteCommandBits AND NOT nRemPrev;
nLocPrev := nLocalCommandBits;
nRemPrev := nRemoteCommandBits;
nLocMode := -1;
IF nLocalModeRequest <> nLocModePrev AND nLocalModeRequest >= 0 THEN
  nLocMode := nLocalModeRequest;
END_IF;
nLocModePrev := nLocalModeRequest;
nRemMode := -1;
IF nRemoteModeRequest <> nRemModePrev AND nRemoteModeRequest >= 0 THEN
  nRemMode := nRemoteModeRequest;
END_IF;
nRemModePrev := nRemoteModeRequest;
nLocSel := -1;
IF nLocalSelection <> nLocSelPrev AND nLocalSelection >= 0 THEN
  nLocSel := nLocalSelection;
END_IF;
nLocSelPrev := nLocalSelection;
nRemSel := -1;
IF nRemoteSelection <> nRemSelPrev AND nRemoteSelection >= 0 THEN
  nRemSel := nRemoteSelection;
END_IF;
nRemSelPrev := nRemoteSelection;

(* what the remote master may do now *)
IF bRemoteAllowed THEN
  nRemMask := DWORD#16#FFFFFFFF;
ELSIF refData.set.bRemoteStopUnderLocal THEN
  nRemMask := refData.set.nStopBits;
ELSE
  nRemMask := DWORD#0;
END_IF;
nRemMask := nRemMask AND NOT refData.set.nLocalOnlyBits;
nRemOk := nRemEdge AND nRemMask;
nRemBad := nRemEdge AND NOT nRemMask;
bModeBad := FALSE;
IF nRemMode >= 0 THEN
  IF nRemMode > 15 THEN
    bModeBad := TRUE;
  ELSIF (SHR(refData.set.nRemoteAllowedModeBits, nRemMode) AND WORD#1) = WORD#0 THEN
    bModeBad := TRUE;
  ELSIF NOT bRemoteAllowed AND NOT (refData.set.bRemoteStopUnderLocal AND nRemMode = 0) THEN
    bModeBad := TRUE;
  END_IF;
  IF bModeBad THEN
    nRemMode := -1;
  END_IF;
END_IF;
IF nLocMode > 15 THEN
  nLocMode := -1;
END_IF;
bSelBad := nRemSel >= 0 AND NOT (bRemoteAllowed AND refData.set.bRemoteMaySelect);
IF bSelBad THEN
  nRemSel := -1;
END_IF;

(* combine: stop / off wins, then local before remote *)
nAll := nLocEdge OR nRemOk;
IF nLocMode = 0 OR nRemMode = 0 THEN
  nModeRequest := 0;
ELSIF nLocMode >= 0 THEN
  nModeRequest := nLocMode;
ELSE
  nModeRequest := nRemMode;
END_IF;
IF (nAll AND refData.set.nStopBits) <> DWORD#0 OR nModeRequest = 0 THEN
  nAll := nAll AND refData.set.nStopBits;
  IF nModeRequest > 0 THEN
    nModeRequest := -1;
  END_IF;
END_IF;
IF nLocSel >= 0 THEN
  nSelection := nLocSel;
ELSE
  nSelection := nRemSel;
END_IF;
nCommandBits := nAll;
bCommandBit0 := nCommandBits.0;
bCommandBit1 := nCommandBits.1;
bCommandBit2 := nCommandBits.2;
bCommandBit3 := nCommandBits.3;
bCommandBit4 := nCommandBits.4;
bCommandBit5 := nCommandBits.5;
bCommandBit6 := nCommandBits.6;
bCommandBit7 := nCommandBits.7;

(* who gave it *)
bLocUsed := (nLocEdge AND nCommandBits) <> DWORD#0 OR (nModeRequest >= 0 AND nModeRequest = nLocMode) OR (nSelection >= 0 AND nSelection = nLocSel);
bRemUsed := (nRemOk AND nCommandBits) <> DWORD#0 OR (nModeRequest >= 0 AND nModeRequest = nRemMode)
            OR (nSelection >= 0 AND nSelection = nRemSel AND nLocSel < 0);
IF bLocUsed OR bRemUsed THEN
  IF bLocUsed THEN
    refData.sts.eLastCommandFrom := E_CmdFrom.Local;
  ELSE
    refData.sts.eLastCommandFrom := E_CmdFrom.Remote;
  END_IF;
  refData.sts.nLastCommandBits := nCommandBits;
  refData.sts.nLastModeRequest := nModeRequest;
  refData.sts.nLastSelection := nSelection;
END_IF;
IF nRemBad <> DWORD#0 OR bModeBad OR bSelBad THEN
  bRequestRefused := TRUE;
  refData.sts.nRemoteRefusedCount := refData.sts.nRemoteRefusedCount + 1;
END_IF;
refData.sts.bLocalControlOnly := NOT bRemoteAllowed;

END_FUNCTION_BLOCK