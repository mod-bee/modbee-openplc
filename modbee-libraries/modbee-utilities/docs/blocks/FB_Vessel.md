# FB_Vessel — Tank volume

A tank, sump, silo or pond: its volume, % full, free space, mass and surface area from a level measurement, for six shapes and several joined tanks.

Offers `I_Vessel`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fTableVolume` | `REAL` |  | Table: the volume at the present level, in eVolumeUnit (an FB_Linearise) |
| in | `fTableArea` | `REAL` |  | Table: the surface area at the present level, m2 (an FB_Linearise; optional) |
| in | `ipLevel` | `I_Measurement` |  | required. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `refData` | `REFERENCE TO ST_VesselData` |  | the block's record |
| in | `stConfig` | `ST_VesselConfig` |  | engineering constants (set at the declaration) |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fVolume` | `REAL` |  | in eVolumeUnit, after the dead volume |
| out | `bGood` | `BOOL` |  | the volume can be trusted |
| out | `fVolumePct` | `REAL` |  | of the full working volume |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_VesselData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdClearRefused` | `BOOL` |  | clear the refused report (cleared by the block) |

**Settings `set`** (`ST_VesselSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fSensorHeightAboveBottom` | `REAL` |  | added to the level (sensor zero above / below the bottom) |
| `fUnusableVolume` | `REAL` |  | unusable volume, in eVolumeUnit |
| `fLevelAtZeroPct` | `REAL` |  | sts.fLevelPct is 0 % at this level; both 0 = the whole height |
| `fLevelAtFullPct` | `REAL` |  | sts.fLevelPct is 100 % at this level |

**Status `sts`** (`ST_VesselSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fVolume` | `REAL` |  | in eVolumeUnit |
| `fFullVolume` | `REAL` |  | working volume when full |
| `fVolumePct` | `REAL` |  | of fFullVolume |
| `fSpaceLeft` | `REAL` |  | space left |
| `fMass` | `REAL` |  | mass of the contents, in eMassUnit |
| `fLevelPct` | `REAL` |  | the level as a % of fLevelAtZeroPct .. fLevelAtFullPct |
| `fSurfaceArea` | `REAL` |  | water surface, m2 |
| `bGood` | `BOOL` |  | the volume can be trusted |
| `bOverfull` | `BOOL` |  | the level is above the top |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Constants `ST_VesselConfig` (pin `stConfig`)

**Fields** (`ST_VesselConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eShape` | `E_VesselShape` |  | Vertical, Cone, Horizontal, Rect, Sphere or Pond |
| `nTanksJoined` | `INT` | `1` | identical tanks joined at the bottom (1..100) |
| `fDiameter` | `REAL` | `1.0` | diameter (cylinders, sphere) |
| `fHeight` | `REAL` | `1.0` | Cone: the cylinder above the cone |
| `fLength` | `REAL` | `1.0` | length (Horizontal, Rect, Pond) |
| `fWidth` | `REAL` | `1.0` | width (Rect, Pond) |
| `fConeHeight` | `REAL` |  | Cone: the height of the cone |
| `fOutletDiameter` | `REAL` |  | Cone: the diameter at the bottom outlet |
| `fPondSideSlope` | `REAL` |  | Pond: horizontal per 1 vertical |
| `eLevelUnit` | `E_Unit` |  | Metre, Cm, Mm or Percent; None: the level's own unit |
| `eVolumeUnit` | `E_Unit` | `E_Unit.M3` | M3, Litre or MegaLitre |
| `eMassUnit` | `E_Unit` | `E_Unit.Kg` | Kg or Tonne |
| `fDensity` | `REAL` | `1000.0` | kg/m3 |
| `fShareOfVessel` | `REAL` | `1.0` | share of the vessel |
| `fTableFullVolume` | `REAL` |  | Table: the volume when full, in eVolumeUnit (fHeight: the level when full) |

Set once, at the variable's declaration (engineering constants, not changed while running).

## Lists

- `E_VesselShape`: `Vertical`, `Cone`, `Horizontal`, `Rect`, `Sphere`, `Pond`, `Table` (default `Vertical`)

## How it works

A tank, sump, silo or pond: its volume, % full, free space, mass and surface area from a level measurement. Wire the instance to any `I_Vessel` or `I_Measurement` pin: its value is the level, its bands are the level's bands.

One shape x `stConfig.nTanksJoined` identical tanks joined at the bottom (the same level in each):

```
  Vertical    flat-bottom vertical cylinder: fDiameter, fHeight
  Cone        a hopper (fConeHeight, from fOutletDiameter up to fDiameter) under a cylinder of fHeight
  Horizontal  horizontal cylinder with flat ends: fDiameter, fLength
  Rect        fLength, fWidth, fHeight
  Sphere      fDiameter
  Pond        sloped banks: floor fLength x fWidth, depth fHeight, bank fPondSideSlope (horizontal per 1 vertical,
              e.g. 3 for 3:1; 0 = Rect)
  Table       any shape from a level table: wire an FB_Linearise of the level (level -> volume, in eVolumeUnit)
              to fTableVolume and, optional, one (level -> area, m2) to fTableArea; stConfig.fTableFullVolume is the
              volume when full, fHeight the level when full
```

The level unit: `stConfig.eLevelUnit` when it is set; None (the default) takes the level's own unit (`ipLevel.eUnit`), and a level with no unit set reads as Metre. A level unit other than Metre, Cm, Mm or Percent is BadSetting. The vessel's `eUnit` is the level unit in use.

Units: the dimensions are in metres. The level, `set.fSensorHeightAboveBottom` and `set.fLevelAtZeroPct` / `fLevelAtFullPct` are in the level unit (Metre, Cm, Mm; Percent = % of the full height). Volumes in `eVolumeUnit` (M3, Litre, MegaLitre), the mass in `eMassUnit` (Kg, Tonne) from `fDensity` (kg/m3). `fShareOfVessel`: the share of the vessel (0.5 = half a divided silo). `set.fUnusableVolume` (in `eVolumeUnit`) is taken off the volume and the full volume.

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
| `fVolumePct` | a display |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActValue : REAL`: the value in its unit (held at the last good one while bad, when so set)
- property `bIsGood : BOOL`: the value can be trusted now
- property `bHasValue : BOOL`: a continuous value (FALSE: switches only)
- property `bIsFitted : BOOL`: the sensor is on this site (FALSE: no value, no bands, no fault)
- property `fActVolume : REAL`: working volume now
- property `fActVolumePct : REAL`: percent full now
- property `fFullVolume : REAL`: working volume when full
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`: the level's own bands
