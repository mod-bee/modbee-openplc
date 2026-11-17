(* F_IoFind — a channel through the module table: Unused (eSrc None), NoModule (no module of that kind, source
and number), NoChannel (no such channel, or outside the image nImgLo..nImgHi), else Ok with nMod (the module
row) and nIdx (the image row). The caller then checks the module's fitted / ok and the channel's bad bit. *)

FUNCTION F_IoFind : E_IoQ
  VAR_IN_OUT
    aMods : ARRAY [*] OF ST_IOMODULE;
  END_VAR
  VAR_INPUT
    eKind : E_IoKind;
    eSrc : E_IoSrc;
    nModule : USINT;
    nCh : USINT;
    nImgLo : DINT;
    nImgHi : DINT;
  END_VAR
  VAR_OUTPUT
    nMod : DINT;
    nIdx : DINT;
  END_VAR
  VAR
    nK : DINT;
    bFound : BOOL;
  END_VAR


nMod := 0;
nIdx := 0;
IF eSrc = E_IoSrc.None THEN
  F_IoFind := E_IoQ.Unused;
  RETURN;
END_IF;
FOR nK := LOWER_BOUND(aMods, 1) TO UPPER_BOUND(aMods, 1) DO
  IF NOT bFound AND aMods[nK].eKind = eKind AND aMods[nK].eSrc = eSrc AND aMods[nK].nModule = nModule THEN
    nMod := nK;
    bFound := TRUE;
  END_IF;
END_FOR;
IF NOT bFound THEN
  F_IoFind := E_IoQ.NoModule;
ELSIF nCh < 1 OR nCh > aMods[nMod].nCount THEN
  F_IoFind := E_IoQ.NoChannel;
ELSE
  nIdx := INT_TO_DINT(aMods[nMod].nFirst) + USINT_TO_DINT(nCh) - 1;
  IF nIdx < nImgLo OR nIdx > nImgHi THEN
    F_IoFind := E_IoQ.NoChannel;
  ELSE
    F_IoFind := E_IoQ.Ok;
  END_IF;
END_IF;

END_FUNCTION