# Using library blocks in Ladder and FBD

## 1. Give every block its own always-true rung
A block from an installed library takes rung power on **EN**. On a false rung the
block isn't called, so its timers stop and its outputs **hold their last value**.
A motor's `Run` would stay on.

```
WRONG  |--[ AutoRun ]-----------[ UT_MOTOR  EN ]--|     block frozen when AutoRun is FALSE
RIGHT  |------------------------[ UT_MOTOR  EN ]--|     AutoCmd := AutoRun  (named pin)
```

## 2. Wire signals to named pins
Rung power only enables the block; it doesn't drive any pin. Put every signal
on the pin it belongs to: `AutoCmd := AutoRun`, `Feedback := %IX0.3`.

## 3. Read and write record members with contacts and coils
Record members work like any other variable:

```
|--[ Pump1.running ]--------------------------( Lamp_P1_Run )--|
|--[ Pump1.fltDryRun ]------------------------( Alarm_DryRun )--|
|--[ LowFloat ]-------------------------------( Steps[1].feedback )--|
```

## 4. Group slots
Sequencer steps and interlock conditions are filled with one coil each and read
with one contact each:

```
|--[ Conveyor2.Running ]--------------------( Steps[2].feedback )--|
|--[ Steps[2].cmd ]-------------------------( Conveyor2_Auto )-----|
```

## 5. Don't write `grpXxx` fields
Group blocks write those. Anything you write there is overwritten next scan.

## 6. Analog I/O
Until generic (ANY) pins arrive, a raw `%IW` value needs a `UINT_TO_REAL` block in
front of `UT_ANALOG_IN`. `UT_ANALOG_OUT` provides `OutRaw : UINT`, which connects
straight to `%QW`.
