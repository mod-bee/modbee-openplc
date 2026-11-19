(* F_IoAddrPack — an IO channel address packed into one DWORD, for the IO maps' kept copies:
bits 0..2 the source (E_IoSrc: None 0, Board 1, I2c 2, Field 3, Remote 4), bits 3..9 the module (0..127),
bits 10..17 the channel (0..255). The caller checks the module is at most 127 (F_IoAddrOk). *)

FUNCTION F_IoAddrPack : DWORD
  VAR_INPUT
    eSource : E_IoSrc; (* where the channel is: None (not on this site), Board, I2c, Field or Remote *)
    nModuleNumber : USINT; (* the module number within that source (0..127) *)
    nChannel : USINT; (* the channel number on the module *)
  END_VAR
  VAR
    nSrc : DWORD;
  END_VAR


CASE eSource OF
  E_IoSrc.Board: nSrc := 1;
  E_IoSrc.I2c: nSrc := 2;
  E_IoSrc.Field: nSrc := 3;
  E_IoSrc.Remote: nSrc := 4;
ELSE
  nSrc := 0;
END_CASE;
F_IoAddrPack := nSrc OR SHL(USINT_TO_DWORD(nModuleNumber) AND DWORD#16#7F, 3) OR SHL(USINT_TO_DWORD(nChannel), 10);

END_FUNCTION