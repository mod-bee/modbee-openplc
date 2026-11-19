(* F_IoAddrUnpack — the address F_IoAddrPack packed (the higher bits are the caller's). *)

FUNCTION F_IoAddrUnpack : BOOL
  VAR_INPUT
    nPackedAddress : DWORD; (* the packed address *)
  END_VAR
  VAR_OUTPUT
    eSource : E_IoSrc; (* where the channel is: None (not on this site), Board, I2c, Field or Remote *)
    nModuleNumber : USINT; (* the module number within that source (0..127) *)
    nChannel : USINT; (* the channel number on the module *)
  END_VAR


CASE DWORD_TO_USINT(nPackedAddress AND DWORD#16#7) OF
  1: eSource := E_IoSrc.Board;
  2: eSource := E_IoSrc.I2c;
  3: eSource := E_IoSrc.Field;
  4: eSource := E_IoSrc.Remote;
ELSE
  eSource := E_IoSrc.None;
END_CASE;
nModuleNumber := DWORD_TO_USINT(SHR(nPackedAddress, 3) AND DWORD#16#7F);
nChannel := DWORD_TO_USINT(SHR(nPackedAddress, 10) AND DWORD#16#FF);
F_IoAddrUnpack := TRUE;

END_FUNCTION