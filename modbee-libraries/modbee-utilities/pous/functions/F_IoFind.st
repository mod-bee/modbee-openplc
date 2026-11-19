(* F_IoFind — a channel through the module table: Unused (eSource None), NoModule (no module of that kind, source
and number), NoChannel (no such channel, or outside the image nImageFirstRow..nImageLastRow), else Ok with nModuleRow (the module
row) and nImageRow (the image row). The caller then checks the module's fitted / ok and the channel's bad bit. *)

FUNCTION F_IoFind : E_IoQ
  VAR_IN_OUT
    aModules : ARRAY [*] OF ST_IOMODULE; (* the module table *)
  END_VAR
  VAR_INPUT
    eChannelKind : E_IoKind; (* the kind of channel looked for *)
    eSource : E_IoSrc; (* where the channel is: None (not on this site), Board, I2c, Field or Remote *)
    nModuleNumber : USINT; (* the module number within that source (0..127) *)
    nChannel : USINT; (* the channel number on the module *)
    nImageFirstRow : DINT; (* the image's first row *)
    nImageLastRow : DINT; (* the image's last row *)
  END_VAR
  VAR_OUTPUT
    nModuleRow : DINT; (* the module row found *)
    nImageRow : DINT; (* the image row found *)
  END_VAR
  VAR
    nK : DINT;
    bFound : BOOL;
  END_VAR


nModuleRow := 0;
nImageRow := 0;
IF eSource = E_IoSrc.None THEN
  F_IoFind := E_IoQ.Unused;
  RETURN;
END_IF;
FOR nK := LOWER_BOUND(aModules, 1) TO UPPER_BOUND(aModules, 1) DO
  IF NOT bFound AND aModules[nK].eChannelKind = eChannelKind AND aModules[nK].eSource = eSource AND aModules[nK].nModuleNumber = nModuleNumber THEN
    nModuleRow := nK;
    bFound := TRUE;
  END_IF;
END_FOR;
IF NOT bFound THEN
  F_IoFind := E_IoQ.NoModule;
ELSIF nChannel < 1 OR nChannel > aModules[nModuleRow].nChannels THEN
  F_IoFind := E_IoQ.NoChannel;
ELSE
  nImageRow := INT_TO_DINT(aModules[nModuleRow].nFirstImageRow) + USINT_TO_DINT(nChannel) - 1;
  IF nImageRow < nImageFirstRow OR nImageRow > nImageLastRow THEN
    F_IoFind := E_IoQ.NoChannel;
  ELSE
    F_IoFind := E_IoQ.Ok;
  END_IF;
END_IF;

END_FUNCTION