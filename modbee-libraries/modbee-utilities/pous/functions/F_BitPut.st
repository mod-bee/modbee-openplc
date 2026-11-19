(* nBits with bit nBitNumber (0..31) set to bValue; nBitNumber outside 0..31 leaves it as is *)

FUNCTION F_BitPut : DWORD
  VAR_INPUT
    nBits : DWORD; (* the word to change *)
    nBitNumber : SINT; (* which bit, 0..31 *)
    bValue : BOOL; (* the value to put in it *)
  END_VAR

IF nBitNumber < 0 OR nBitNumber > 31 THEN
  F_BitPut := nBits;
ELSIF bValue THEN
  F_BitPut := nBits OR SHL(DWORD#1, nBitNumber);
ELSE
  F_BitPut := nBits AND NOT SHL(DWORD#1, nBitNumber);
END_IF;

END_FUNCTION