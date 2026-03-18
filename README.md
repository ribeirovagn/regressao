# MarketRegime Zones (v2.13)

MQL5 indicator to classify regime from price statistics, detect ranging zones, project horizontal levels, and display a compact HUD with structural bias, short-term microtrend, strength, step source, and zone energy.

## Feature Summary

- Detects ranging with an objective rule: `|slope_norm| < threshold` and `R2 < InpR2Threshold`.
- Computes linear regression chronologically from the oldest candle in the window to the most recent candle, even though MT5 price arrays are in series mode.
- Builds zones from clusters of ranging candles with three states:
  - active (`Z_ACTIVE`)
  - broken upward (`Z_BREAK_UP`)
  - broken downward (`Z_BREAK_DOWN`)
- Renders zones with duration-based transparency and border width driven by average score.
- Optionally extends the zone until breakout and can draw the zone midline.
- Projects horizontal levels from the most relevant recent zone.
- Shows a draggable HUD with `REGIME`, `BIAS`, `MICROTREND`, `STRENGTH`, `STEP`, `STEP SRC`, and optional `ZONE ENERGY`.
- Falls back to a single `DIR` line when `InpShowBiasAndMicrotrend = false`.
- Fires breakout alerts only when a broken zone exists and trend strength is above the configured minimum.
- Uses anti-spam alerting: each broken zone alerts once, and a new zone can alert again.
- Calculates `ZONE ENERGY` only from price statistics: duration, compression, chop, and edge touches.

## Quick Start

1. Copy `MarketRegime.mq5` to `MQL5/Indicators/` and compile it in MetaEditor.
2. Add the indicator to the desired symbol/timeframe in MT5.
3. Tune regime sensitivity first:

- `InpWindow`
- `InpSlopeNormMode`
- `InpSlopeThresholdMean` or `InpSlopeThresholdStd`
- `InpR2Threshold`

4. Tune zone formation and breakout behavior:

- `InpMinZoneBars`
- `InpGapTolerance`
- `InpExtendUntilBreak`
- `InpBreakMarginPoints`

5. Tune HUD and direction readout:

- `InpShowBiasAndMicrotrend`
- `InpMicrotrendWindow`
- HUD size, alpha, and font inputs

6. Tune alerts if you want breakout notifications:

- `InpEnableBreakAlerts`
- `InpAlertMinStrength`
- popup/sound/push switches
- `InpAlertSoundFile`

7. For zone energy, enable `InpEnableZoneEnergy` and adjust its scales/weights for your symbol and timeframe.

## Parameters (`input`)

### 1) Regression and Regime

| Parameter               | Type                   |           Default | Description                                                           |
| ----------------------- | ---------------------- | ----------------: | --------------------------------------------------------------------- |
| `InpWindow`             | `int`                  |             `240` | Main linear regression window in bars.                                |
| `InpSlopeNormMode`      | `ENUM_SLOPE_NORM_MODE` | `SLOPE_NORM_MEAN` | Slope normalization mode (`MEAN` or `STD`).                           |
| `InpSlopeThresholdMean` | `double`               |          `0.0001` | Slope threshold for `MEAN` mode.                                      |
| `InpSlopeThresholdStd`  | `double`               |            `0.20` | Slope threshold for `STD` mode.                                       |
| `InpR2Threshold`        | `double`               |            `0.05` | Maximum `R2` to classify the window as ranging.                       |
| `InpScoreSlopeWeight`   | `double`               |            `0.85` | Slope weight in the informational score (`R2` weight is `1-weight`).  |

### 2) Zones

| Parameter                        | Type     | Default | Description                                      |
| -------------------------------- | -------- | ------: | ------------------------------------------------ |
| `InpMinZoneBars`                 | `int`    |    `15` | Minimum number of bars required to validate a zone. |
| `InpGapTolerance`                | `int`    |     `1` | Maximum non-ranging bars tolerated inside a cluster. |
| `InpExtendUntilBreak`            | `bool`   |  `true` | Extends the zone until breakout is found.        |
| `InpBreakMarginPoints`           | `double` |    `50` | Margin in points to confirm a breakout.          |
| `InpMaxZonesOnChart`             | `int`    |     `3` | Maximum number of zones in multi-zone mode.      |
| `InpOnlyLastActiveAndLastBroken` | `bool`   |  `true` | Keeps only the last active zone and the last broken zone. |

### 3) Zone Visuals and Arrows

| Parameter           | Type   | Default | Description                               |
| ------------------- | ------ | ------: | ----------------------------------------- |
| `InpKeepArrows`     | `bool` |  `true` | Draws arrows on ranging candles.          |
| `InpDrawMidLine`    | `bool` | `false` | Draws the zone midline.                   |
| `InpAlphaMin`       | `int`  |    `15` | Minimum zone alpha (`0..255`).            |
| `InpAlphaMax`       | `int`  |    `50` | Maximum zone alpha (`0..255`).            |
| `InpAlphaLenScale`  | `int`  |   `120` | Duration scale for alpha interpolation.   |
| `InpBorderMinWidth` | `int`  |     `1` | Minimum zone border width.                |
| `InpBorderMaxWidth` | `int`  |     `4` | Maximum zone border width.                |

### 4) Horizontal Projections

| Parameter                        | Type    |   Default | Description                            |
| -------------------------------- | ------- | --------: | -------------------------------------- |
| `InpDrawProjectionLines`         | `bool`  |    `true` | Enables projection lines.              |
| `InpProjectionCount`             | `int`   |      `10` | Number of levels above and below the zone. |
| `InpProjectionIncludeZoneLevels` | `bool`  |    `true` | Includes the zone `top/mid/bottom`.    |
| `InpProjectionLineWidth`         | `int`   |       `1` | Projection line thickness.             |
| `InpProjectionLineAlpha`         | `int`   |      `10` | Projection line alpha (`0..255`).      |
| `InpProjectionLineColor`         | `color` | `clrGold` | Projection line color.                 |

### 5) HUD and Direction Readout

| Parameter                   | Type     | Default | Description                                            |
| --------------------------- | -------- | ------: | ------------------------------------------------------ |
| `InpEnableTrendHUD`         | `bool`   |  `true` | Enables the HUD.                                       |
| `InpShowTrendDetails`       | `bool`   | `false` | Shows an extra line with `R2/ER/S`.                    |
| `InpShowBiasAndMicrotrend`  | `bool`   |  `true` | Shows separate `BIAS` and `MICROTREND` lines.          |
| `InpMicrotrendWindow`       | `int`    |    `30` | Regression window used for the short-term microtrend.  |
| `InpHUDDraggable`           | `bool`   |  `true` | Allows dragging the HUD on chart.                      |
| `InpHUDXDefault`            | `int`    |    `12` | Default HUD X offset.                                  |
| `InpHUDYDefault`            | `int`    |    `12` | Default HUD Y offset.                                  |
| `InpHUDFontSize`            | `int`    |    `10` | HUD font size.                                         |
| `InpHUDWidth`               | `int`    |   `240` | Minimum HUD panel width.                               |
| `InpHUDHeight`              | `int`    |    `86` | Minimum HUD panel height.                              |
| `InpHUDAlphaMin`            | `int`    |   `170` | Minimum HUD alpha (`0..255`).                          |
| `InpHUDAlphaMax`            | `int`    |   `255` | Maximum HUD alpha (`0..255`).                          |
| `InpBarHeight`              | `int`    |    `10` | Strength bar height at the HUD footer.                 |
| `InpBarMarginX`             | `int`    |    `10` | Reserved compatibility input for bar X margin.         |
| `InpBarMarginBottom`        | `int`    |    `10` | Reserved compatibility input for bar bottom margin.    |
| `InpTrendThreshold`         | `double` |  `0.60` | Threshold to classify regime as `TREND`.               |
| `InpTrendWeightSlope`       | `double` |  `0.40` | Slope weight inside `trend_strength`.                  |
| `InpTrendWeightR2`          | `double` |  `0.40` | `R2` weight inside `trend_strength`.                   |
| `InpTrendWeightER`          | `double` |  `0.20` | Efficiency Ratio weight inside `trend_strength`.       |

HUD behavior:

- `BIAS` uses the main regression from `InpWindow`.
- `MICROTREND` uses the same regression math on `InpMicrotrendWindow`.
- `STEP SRC` shows whether the current `STEP` comes from the active zone, the last broken zone, or neither.
- If `InpEnableZoneEnergy = true` and no active zone is available, the HUD shows `ZONE ENERGY: N/A`.

### 6) Break Alerts

| Parameter              | Type     | Default       | Description                                            |
| ---------------------- | -------- | ------------: | ------------------------------------------------------ |
| `InpEnableBreakAlerts` | `bool`   |        `true` | Master switch for breakout alerts.                     |
| `InpEnablePopupAlert`  | `bool`   |        `true` | Uses `Alert(...)` when a valid breakout is detected.   |
| `InpEnableSoundAlert`  | `bool`   |        `true` | Uses `PlaySound(...)` when a valid breakout is detected. |
| `InpEnablePushAlert`   | `bool`   |       `false` | Uses `SendNotification(...)` when enabled in MT5.      |
| `InpAlertSoundFile`    | `string` | `"alert.wav"` | Sound file passed to `PlaySound(...)`.                 |
| `InpAlertMinStrength`  | `int`    |          `40` | Minimum trend strength percentage required to alert.   |

Alert behavior:

- Only broken zones can generate alerts.
- The alert fires only if `trend_strength_pct >= InpAlertMinStrength`.
- Each broken zone alerts only once; the same zone is not repeated every tick.
- When a new broken zone appears, it can alert again.

Example message:

`[MRZ] BREAK DOWN | XAUUSD M1 | Price: 5166.41 | Step: 9.51 | Strength: 86 | Energy: 72`

### 7) Zone Energy

| Parameter                        | Type     | Default | Description                                       |
| -------------------------------- | -------- | ------: | ------------------------------------------------- |
| `InpEnableZoneEnergy`            | `bool`   |  `true` | Enables calculation and HUD display of `ZONE ENERGY`. |
| `InpZoneEnergyLenScale`          | `int`    |   `120` | Duration scale for the length component.          |
| `InpZoneEnergyTouchMarginPoints` | `int`    |    `30` | Margin in points to count top/bottom touches.     |
| `InpZoneEnergyTouchScale`        | `int`    |    `12` | Touch normalization scale.                        |
| `InpZoneEnergyWeightLen`         | `double` |  `0.30` | Duration weight.                                  |
| `InpZoneEnergyWeightComp`        | `double` |  `0.35` | Compression weight.                               |
| `InpZoneEnergyWeightChop`        | `double` |  `0.20` | Chop weight (`1 - ER` of the zone).               |
| `InpZoneEnergyWeightTouch`       | `double` |  `0.15` | Edge-touch weight.                                |

> Note: zone-energy weights are automatically normalized if their sum differs from `1`.

### 8) Execution and Debug

| Parameter                    | Type   | Default | Description                                                    |
| ---------------------------- | ------ | ------: | -------------------------------------------------------------- |
| `InpDebug`                   | `bool` | `false` | Enables debug logs in the MT5 Journal.                         |
| `InpOnCalculateDelaySeconds` | `int`  |     `5` | Minimum delay between `OnCalculate` executions (`0` disables). |

## Notes

- The indicator uses only price statistics; it does not depend on classic oscillators or moving averages.
- In `OnInit`, the code clears objects on the current chart with `ObjectsDeleteAll(0, -1, -1)`.
- The HUD remains draggable and automatically adjusts its height from the real number of visible lines.
