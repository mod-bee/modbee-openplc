(* FB_Cmd — command arbiter for two masters: the local one (panel HMI) and the remote one (SCADA / IoT)
(src-v2 UT_CMD).
Pins: nLocalCmd / nRemoteCmd (command bits; a rising edge acts), nLocalMode / nRemoteMode (a mode request, acts on
a change to 0..15), nLocalSel / nRemoteSel (a selection, acts on a change to 0 or more), bRemoteEnabled (FALSE:
local control) -> nCmd and bCmd0..bCmd7 (the accepted bits, one scan), nMode / nSel (the accepted request, one
scan, else -1), bRefused (one scan: a remote request was refused). refData: its record.
Stop / off bits (set.nStopMask) and mode 0 win over everything else in a scan; local wins over remote.
bRemoteEnabled FALSE: remote requests are refused (bRefused, sts.nRefusedCount), except the stop bits and mode 0
when set.bRemoteStop. set.nLocalOnlyMask bits are never taken from the remote master; set.nRemoteModes says which
mode codes it may ask for; set.bRemoteSel whether it may change the selection. Every value of the settings is
usable: they are kept by the block (restored at power-up), never put back. No errors of its own. *)

FUNCTION_BLOCK FB_Cmd
  VAR_INPUT
    nLocalCmd : DWORD; (* command bits (rising edge acts) *)
    nRemoteCmd : DWORD;
    nLocalMode : INT := -1; (* mode request (acts on a change to 0..15) *)
    nRemoteMode : INT := -1;
    nLocalSel : INT := -1; (* selection (auto type, preset, route ...) *)
    nRemoteSel : INT := -1;
    bRemoteEnabled : BOOL := TRUE; (* FALSE: local control *)
    refData : REFERENCE TO ST_CmdData;
  END_VAR
  VAR_OUTPUT
    bCmd0 : BOOL;
    bCmd1 : BOOL;
    bCmd2 : BOOL;
    bCmd3 : BOOL;
    bCmd4 : BOOL;
    bCmd5 : BOOL;
    bCmd6 : BOOL;
    bCmd7 : BOOL;
    nCmd : DWORD; (* accepted bits, one scan *)
    nMode : INT; (* accepted mode request, one scan, else -1 *)
    nSel : INT; (* accepted selection, one scan, else -1 *)
    bRefused : BOOL; (* one scan: a remote request was refused *)
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


bRefused := FALSE;
IF NOT __ISVALIDREF(refData) THEN
  nCmd := 0;
  nMode := -1;
  nSel := -1;
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
  nLocPrev := nLocalCmd;
  nRemPrev := nRemoteCmd;
  nLocModePrev := nLocalMode;
  nRemModePrev := nRemoteMode;
  nLocSelPrev := nLocalSel;
  nRemSelPrev := nRemoteSel;
END_IF;
stKept := refData.set;

(* each master's new requests *)
nLocEdge := nLocalCmd AND NOT nLocPrev;
nRemEdge := nRemoteCmd AND NOT nRemPrev;
nLocPrev := nLocalCmd;
nRemPrev := nRemoteCmd;
nLocMode := -1;
IF nLocalMode <> nLocModePrev AND nLocalMode >= 0 THEN
  nLocMode := nLocalMode;
END_IF;
nLocModePrev := nLocalMode;
nRemMode := -1;
IF nRemoteMode <> nRemModePrev AND nRemoteMode >= 0 THEN
  nRemMode := nRemoteMode;
END_IF;
nRemModePrev := nRemoteMode;
nLocSel := -1;
IF nLocalSel <> nLocSelPrev AND nLocalSel >= 0 THEN
  nLocSel := nLocalSel;
END_IF;
nLocSelPrev := nLocalSel;
nRemSel := -1;
IF nRemoteSel <> nRemSelPrev AND nRemoteSel >= 0 THEN
  nRemSel := nRemoteSel;
END_IF;
nRemSelPrev := nRemoteSel;

(* what the remote master may do now *)
IF bRemoteEnabled THEN
  nRemMask := DWORD#16#FFFFFFFF;
ELSIF refData.set.bRemoteStop THEN
  nRemMask := refData.set.nStopMask;
ELSE
  nRemMask := DWORD#0;
END_IF;
nRemMask := nRemMask AND NOT refData.set.nLocalOnlyMask;
nRemOk := nRemEdge AND nRemMask;
nRemBad := nRemEdge AND NOT nRemMask;
bModeBad := FALSE;
IF nRemMode >= 0 THEN
  IF nRemMode > 15 THEN
    bModeBad := TRUE;
  ELSIF (SHR(refData.set.nRemoteModes, nRemMode) AND WORD#1) = WORD#0 THEN
    bModeBad := TRUE;
  ELSIF NOT bRemoteEnabled AND NOT (refData.set.bRemoteStop AND nRemMode = 0) THEN
    bModeBad := TRUE;
  END_IF;
  IF bModeBad THEN
    nRemMode := -1;
  END_IF;
END_IF;
IF nLocMode > 15 THEN
  nLocMode := -1;
END_IF;
bSelBad := nRemSel >= 0 AND NOT (bRemoteEnabled AND refData.set.bRemoteSel);
IF bSelBad THEN
  nRemSel := -1;
END_IF;

(* combine: stop / off wins, then local before remote *)
nAll := nLocEdge OR nRemOk;
IF nLocMode = 0 OR nRemMode = 0 THEN
  nMode := 0;
ELSIF nLocMode >= 0 THEN
  nMode := nLocMode;
ELSE
  nMode := nRemMode;
END_IF;
IF (nAll AND refData.set.nStopMask) <> DWORD#0 OR nMode = 0 THEN
  nAll := nAll AND refData.set.nStopMask;
  IF nMode > 0 THEN
    nMode := -1;
  END_IF;
END_IF;
IF nLocSel >= 0 THEN
  nSel := nLocSel;
ELSE
  nSel := nRemSel;
END_IF;
nCmd := nAll;
bCmd0 := nCmd.0;
bCmd1 := nCmd.1;
bCmd2 := nCmd.2;
bCmd3 := nCmd.3;
bCmd4 := nCmd.4;
bCmd5 := nCmd.5;
bCmd6 := nCmd.6;
bCmd7 := nCmd.7;

(* who gave it *)
bLocUsed := (nLocEdge AND nCmd) <> DWORD#0 OR (nMode >= 0 AND nMode = nLocMode) OR (nSel >= 0 AND nSel = nLocSel);
bRemUsed := (nRemOk AND nCmd) <> DWORD#0 OR (nMode >= 0 AND nMode = nRemMode)
            OR (nSel >= 0 AND nSel = nRemSel AND nLocSel < 0);
IF bLocUsed OR bRemUsed THEN
  IF bLocUsed THEN
    refData.sts.eLastSource := E_CmdFrom.Local;
  ELSE
    refData.sts.eLastSource := E_CmdFrom.Remote;
  END_IF;
  refData.sts.nLastCmd := nCmd;
  refData.sts.nLastMode := nMode;
  refData.sts.nLastSel := nSel;
END_IF;
IF nRemBad <> DWORD#0 OR bModeBad OR bSelBad THEN
  bRefused := TRUE;
  refData.sts.nRefusedCount := refData.sts.nRefusedCount + 1;
END_IF;
refData.sts.bLocalOnly := NOT bRemoteEnabled;

END_FUNCTION_BLOCK