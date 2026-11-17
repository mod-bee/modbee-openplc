(* nBits with bit nBit (0..31) set to bValue; nBit outside 0..31 leaves it as is *)

FUNCTION F_BitPut : DWORD
  VAR_INPUT
    nBits : DWORD;
    nBit : SINT;
    bValue : BOOL;
  END_VAR

IF nBit < 0 OR nBit > 31 THEN
  F_BitPut := nBits;
ELSIF bValue THEN
  F_BitPut := nBits OR SHL(DWORD#1, nBit);
ELSE
  F_BitPut := nBits AND NOT SHL(DWORD#1, nBit);
END_IF;

END_FUNCTION