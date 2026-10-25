# 01 - Getting started

## Step 1: install the library

Install `node-uio` from the ModBee libraries. The board's C++ travels inside
it, so there is nothing to install separately and nothing to keep in step.

Set the target to an ESP32-S3 board in Build Settings.

## Step 2: add the UIO block

Every project needs one `UIO` block, and it must run before anything else that
touches I/O. It brings the board up on its first call, then on every call reads
the inputs and drives the outputs.

That is the whole reason it exists: your program sees one consistent picture of
the inputs for the whole scan, rather than values that change under it.

```
PROGRAM main
  VAR
    board : UIO;
  END_VAR

  board();
END_PROGRAM
```

`READY` goes true once the ADC and the DAC have both answered. If it stays
false, `STATUS` says why.

## Step 3: read an input, drive an output

```
PROGRAM main
  VAR
    board : UIO;
    inputs : DIGITAL_IN;
    outputs : DIGITAL_OUT;
  END_VAR

  board();
  inputs();

  outputs(DO01 := inputs.DI01);
END_PROGRAM
```

Put a 24 V signal on DI01 and DO01 follows it.

The order matters: `UIO` first, then the blocks that read, then your logic, then
the blocks that drive. `DIGITAL_OUT` hands its values to the board, which drives
them on the next `UIO` call.

## Step 4: an analog channel

```
  analog : ANALOG_IN;

  analog(AI01_MODE := UIO_VOLTAGE);
```

`analog.AI01` is now volts, 0.0 to 10.0. On `UIO_CURRENT` it would be
milliamps, 0.0 to 20.0.

Check the channel's solder bridge matches. The mode pin only changes the
arithmetic — a channel bridged for voltage and told `UIO_CURRENT` gives a
confident wrong answer rather than an error. See [03 Analog](03-analog.md).

## Step 5: where to put the blocks

One task is enough to start with. `UIO` first in the program, and everything
else after it.

If you later split the program across two tasks — a fast one for a protocol, a
slower one for the plant logic — keep `UIO` and the I/O blocks together in one
of them. They are not designed to be called from two tasks at once.

## What next

- Every pin, in [02 Block reference](02-block-reference.md).
- Values that survive a power cut, in [05 Retained variables](05-retained-variables.md):
  no blocks, just `RETAIN` and the project's Persistent Storage setting.
