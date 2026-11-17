(* F_IoAddrUnpack — the address F_IoAddrPack packed (the higher bits are the caller's). *)

FUNCTION F_IoAddrUnpack : BOOL
  VAR_INPUT
    dwAddr : DWORD;
  END_VAR
  VAR_OUTPUT
    eSrc : E_IoSrc;
    nModule : USINT;
    nCh : USINT;
  END_VAR


CASE DWORD_TO_USINT(dwAddr AND DWORD#16#7) OF
  1: eSrc := E_IoSrc.Board;
  2: eSrc := E_IoSrc.I2c;
  3: eSrc := E_IoSrc.Field;
  4: eSrc := E_IoSrc.Remote;
ELSE
  eSrc := E_IoSrc.None;
END_CASE;
nModule := DWORD_TO_USINT(SHR(dwAddr, 3) AND DWORD#16#7F);
nCh := DWORD_TO_USINT(SHR(dwAddr, 10) AND DWORD#16#FF);
F_IoAddrUnpack := TRUE;

END_FUNCTION