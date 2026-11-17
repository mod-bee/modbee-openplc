# FB_Vessel — Tank volume

A tank, sump, silo or pond: its volume, % full, free space, mass and surface area from a level measurement, for six shapes and several joined tanks.

Offers `I_Vessel`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipLevel` | `I_Measurement` |  | required. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `refData` | `REFERENCE TO ST_VesselData` |  | Its record (a variable of this type) |
| in | `stConfig` | `ST_VesselConfig` |  | engineering constants (set at the declaration) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fVolume` | `REAL` |  | in eVolumeUnit, after the dead volume |
| out | `fPercent` | `REAL` |  | of the full working volume |
| out | `bGood` | `BOOL` |  | The value can be trusted |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_VesselData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | clear the refused report (cleared by the block) |

**Settings `set`** (`ST_VesselSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fLevelOffset` | `REAL` |  | added to the level (sensor zero above / below the bottom) |
| `fDeadVolume` | `REAL` |  | unusable volume, in eVolumeUnit |
| `fPctLow` | `REAL` |  | sts.fLevelPercent is 0 % at this level; both 0 = the whole height |
| `fPctHigh` | `REAL` |  | sts.fLevelPercent is 100 % at this level |

**Status `sts`** (`ST_VesselSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fVolume` | `REAL` |  | in eVolumeUnit |
| `fFullVolume` | `REAL` |  |  |
| `fPercent` | `REAL` |  | of fFullVolume |
| `fFree` | `REAL` |  | space left |
| `fMass` | `REAL` |  |  |
| `fLevelPercent` | `REAL` |  | the level as a % of fPctLow .. fPctHigh |
| `fArea` | `REAL` |  | water surface, m2 |
| `bGood` | `BOOL` |  | The value can be trusted |
| `bOverfull` | `BOOL` |  | the level is above the top |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |

## Constants `ST_VesselConfig` (pin `stConfig`)

Set once, at the variable's declaration (engineering constants, not changed while running).

**Fields** (`ST_VesselConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eShape` | `E_VesselShape` |  |  |
| `nTanks` | `INT` | `1` | identical tanks joined at the bottom (1..100) |
| `fDiameter` | `REAL` | `1.0` |  |
| `fHeight` | `REAL` | `1.0` | Cone: the cylinder above the cone |
| `fLength` | `REAL` | `1.0` |  |
| `fWidth` | `REAL` | `1.0` |  |
| `fConeHeight` | `REAL` |  |  |
| `fOutletDiameter` | `REAL` |  |  |
| `fSlope` | `REAL` |  | Pond: horizontal per 1 vertical |
| `eLevelUnit` | `E_Unit` |  | Metre, Cm, Mm or Percent; None: the level's own unit |
| `eVolumeUnit` | `E_Unit` | `E_Unit.M3` | M3, Litre or MegaLitre |
| `eMassUnit` | `E_Unit` | `E_Unit.Kg` | Kg or Tonne |
| `fDensity` | `REAL` | `1000.0` | kg/m3 |
| `fFraction` | `REAL` | `1.0` | share of the vessel |

## Lists

- `E_VesselShape`: `Vertical`, `Cone`, `Horizontal`, `Rect`, `Sphere`, `Pond` (default `Vertical`)

## How it works

A tank, sump, silo or pond: its volume, % full, free space, mass and surface area from a level measurement. Wire the instance to any `I_Vessel` or `I_Measurement` pin: its value is the level, its bands are the level's bands.

One shape x `stConfig.nTanks` identical tanks joined at the bottom (the same level in each):

```
  Vertical    flat-bottom vertical cylinder: fDiameter, fHeight
  Cone        a hopper (fConeHeight, from fOutletDiameter up to fDiameter) under a cylinder of fHeight
  Horizontal  horizontal cylinder with flat ends: fDiameter, fLength
  Rect        fLength, fWidth, fHeight
  Sphere      fDiameter
  Pond        sloped banks: floor fLength x fWidth, depth fHeight, bank fSlope (horizontal per 1 vertical,
              e.g. 3 for 3:1; 0 = Rect)
```

The level unit: `stConfig.eLevelUnit` when it is set; None (the default) takes the level's own unit (`ipLevel.eUnit`), and a level with no unit set reads as Metre. A level unit other than Metre, Cm, Mm or Percent is BadSetting. The vessel's `eUnit` is the level unit in use.

Units: the dimensions are in metres. The level, `set.fLevelOffset` and `set.fPctLow` / `fPctHigh` are in the level unit (Metre, Cm, Mm; Percent = % of the full height). Volumes in `eVolumeUnit` (M3, Litre, MegaLitre), the mass in `eMassUnit` (Kg, Tonne) from `fDensity` (kg/m3). `fFraction`: the share of the vessel (0.5 = half a divided silo). `set.fDeadVolume` (in `eVolumeUnit`) is taken off the volume and the full volume.

A level above the top reads full (`sts.bOverfull`). A bad level holds the outputs (not good, no alarm: the measurement raises its own); a level that is not fitted makes the vessel not fitted.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A vertical tank's volume from its level transmitter.

| Pin | Wire |
| --- | --- |
| `ipLevel` | `fbTankLevel` |
| `refData` | `stTank` |
| `stConfig` | `cfgTank` (the shape) |
| `fVolume` | a display |
| `fPercent` | a display |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActValue : REAL`
- property `bIsGood : BOOL`
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `fActVolume : REAL`
- property `fActPercent : REAL`
- property `fFullVolume : REAL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`: the level's own bands

**Back to** [the index](../README.md).
