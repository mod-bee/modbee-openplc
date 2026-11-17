# Using library blocks in Ladder

## 1. Give every block its own always-true rung
A block from an installed library takes rung power on **EN**. On a false rung the
block isn't called, so its timers stop and its outputs **hold their last value**.
A run output would stay on.

```
WRONG  |--[ bAutoRun ]-----------[ FB_Run  EN ]--|     block frozen when bAutoRun is FALSE
RIGHT  |-------------------------[ FB_Run  EN ]--|     bRun := bAutoRun  (named pin)
```

This matters even more for equipment: it stops when its owner's rung stops calling it
(`OwnerLost`), and a part whose rung stops while it acts trips its owner (`PartLost`).

## 2. Wire signals to named pins
Rung power only enables the block; it doesn't drive any pin. Put every signal on the
pin it belongs to: `bFeedback := DI_M1_Aux`, `bOverload := DI_M1_Overload`.

## 3. Wire blocks to blocks by their instance
An `ip…` pin takes another block's **instance**: write the instance name on the pin.
`ipMotor := fbMotor1` on a pump, `ipTarget := fbPump1` on a level control,
`ipLevel := fbSumpLevel` on anything that reads the level, `ipSystem := fbSystem` on
everything. That one wire carries the request, the status and the measurement both
ways: there is nothing else to connect.

## 4. Wire the record to `refData`
Declare one record variable per block (`stPump1 : ST_PumpData`) and write it on the
`refData` pin. Do not declare it RETAIN: the block keeps its settings and totals
itself.

## 5. Read and write record fields with contacts and coils
Record fields work like any other variable:

```
|--[ stPump1.sts.bRunning ]-------------------( DO_P1_Lamp )----|
|--[ fbPump1.bError ]-------------------------( DO_FaultLamp )--|
|--[ DI_HighFloat ]---------------------------( aAlm[2].bIn )---|
```

An HMI command is a coil on the record's `bCmd…` field; the block sets it back.

## 6. Tables
Declare a table as an array of the row type, for example
`aAlm : ARRAY[1..8] OF ST_Alarm`, and write it on the block's in-out pin. Fill each
row's input with one coil, read each row's result with one contact:

```
|--[ fbPump1.bError ]--------------------( aAlm[1].bIn )--------|
|--[ aStep[2].bCmd ]---------------------( bConveyor2Run )------|
|--[ DI_Conveyor2_Running ]--------------( aStep[2].bFeedback )-|
```

## 7. Methods and properties are for ST
Some blocks also have methods and properties (each block page lists them under
"Read from ST"). Ladder never needs them: everything a rung needs is a pin, an output
or a record field.

## 8. Rung order
1. The IO map in ([FB_IoMapIn](blocks/FB_IoMapIn.md)), right after your IO code.
2. The system ([FB_SystemMode](blocks/FB_SystemMode.md)) and the measurements.
3. Parts (protections, level checks, primes, starts limits) before their owners.
4. Zones ([FB_Zone](blocks/FB_Zone.md)) before their program
   ([FB_ZoneSeq](blocks/FB_ZoneSeq.md)).
5. The owners: equipment, then the blocks that drive it.
6. The IO map out ([FB_IoMapOut](blocks/FB_IoMapOut.md)) last.

## 9. Analog I/O
`FB_AnalogIn.fIn` is a REAL: put an `INT_TO_REAL` (or `UINT_TO_REAL`) block in front
of a raw `%IW` value. `FB_AnalogOut.nOutRaw` and `FB_ValveMod.nOutRaw` are UINT and
connect straight to `%QW`.

**Back to** [the index](README.md).
