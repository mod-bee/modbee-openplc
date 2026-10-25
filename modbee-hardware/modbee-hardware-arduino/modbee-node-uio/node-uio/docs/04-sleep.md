# 04 - Sleep and power

## The two kinds

**Light sleep** returns where it left off. The program carries on with its
variables intact and the scan resumes. Everything holds its state.

**Deep sleep** does not return. The board restarts from the beginning, and
`WAKE_CAUSE` is what tells you it had been asleep rather than freshly powered.
It draws far less.

## Waking

Give the block a timer, a set of inputs, or both:

```
sleeper(TRIGGER := bGoToSleep,
        MODE := UIO_DEEP_SLEEP,
        SECONDS := 300,
        EN_WAKE_DI01 := TRUE);
```

Each `EN_WAKE_DInn` pin arms one input as a wake source. Set as many as you like
— the board wakes when any armed input goes high — and use them with the timer
or instead of it.

With neither a timer nor an input the board would have no way back, so the
request is refused and `STATUS` says `UIO_INVALID_ARGUMENT`.

After waking, `WAKE_CAUSE` reads `UIO_WAKE_TIMER` or `UIO_WAKE_INPUT`. On a
normal power-up it reads `UIO_WAKE_RESET`, which is how a program tells the two
apart.

## What happens to the outputs

**DO01 to DO04 can hold a level, and you say which.** `DO01_IN_SLEEP` to
`DO04_IN_SLEEP` are driven just before sleeping and latched there, so a valve
can stay open or a heater stay off — whichever the machine needs rather than
whichever it happened to be.

**DO05 to DO08 cannot.** They are GPIO 33 to 36, outside the part's RTC domain,
and drop when it sleeps whatever they were set to. No setting changes that; it
is what the silicon does, so plan for those four going off.

That split is the thing to design around. If something must stay energised
through a sleep, wire it to DO01 to DO04.

Light sleep keeps every pin as it was anyway, and the four `DO0n_IN_SLEEP` pins
are still applied, so the same wiring behaves the same way in both modes.

## Before sleeping

Deep sleep restarts the program, so anything you want on the other side has to
be a retained variable. See [05 Retained variables](05-retained-variables.md).
`SLEEP` saves the retained values just before a deep sleep, the way a PLC stop
does, so a change made in the last scan is kept; the sleep starts once that save
is done, about 10 to 50 ms later.

Light sleep keeps every variable in RAM, so it saves nothing extra. A change the
store is still holding is saved after the board wakes, which means a power cut
during a long light sleep can lose it.

## Turning the radio off

Sleep is not the only saving, and often not the first one to reach for. The
radio costs power whenever it is on, and a board that only needs to be reachable
occasionally can leave it off.

Clearing `ENABLE` on the `NETWORK` block powers the radio down rather than just
disconnecting. Setting it again brings it back. Nothing else in the program has
to change: blocks that need a network simply report that there is none.

`WIFI_SLEEP` does the deciding, and the button is what the board gives you to
ask with:

```
  btn();
  wifiSleep(ENABLE := TRUE, WAKE := btn.SHORT_PRESS, AWAKE := T#5m);
  net(ENABLE := wifiSleep.RADIO_ON, SSID := 'plant', PASSWORD := 'secret');
```

Press the button, the network comes up for five minutes, then powers down.
`AWAKE_LEFT` counts it down if you want to show that somewhere.

`WAKE` takes any signal, not only the button — a shift starting, a fault, a
level switch. And `WAKE_EVERY` brings the radio back on its own that often,
for a board that should phone home whether or not anyone is there.

If the radio was brought up by something else — Modbus TCP in the firmware, or a
protocol library — clearing `ENABLE` leaves it alone. Only what this block
started is this block's to stop.

## The status LED

The board drives the LED beside the antenna on its own: green once the converters
answer, red when they do not. That happens with no blocks placed, so an
unattended board still shows whether it came up.

Nothing in this library lets a program take it over. If that would be useful,
say so — the underlying call exists, it simply is not on a pin.
