# MarketRegime Zones (v2.13)

MQL5 indicator to identify market regime based on price statistics (linear regression on `close`), detect ranging zones, project levels, and display a quick-read HUD.

## Feature Summary

- Detects ranging using an objective rule: `|slope_norm| < threshold` and `R² < InpR2Threshold`.
- Builds zones from clusters of ranging candles (with gap tolerance), with state:
  - active (`Z_ACTIVE`)
  - broken upward (`Z_BREAK_UP`)
  - broken downward (`Z_BREAK_DOWN`)
- Renders zones with duration-based transparency and border width by average score.
- Optionally extends the zone until breakout and draws the midline (`mid`).
- Projects horizontal levels from the most recent zone.
- Shows a regime/direction/strength HUD and, when available, `ZONE ENERGY`.
- `ZONE ENERGY` is calculated only from price statistics (duration, compression, chop, and edge touches).

## Quick Start

1. Copy `MarketRegime.mq5` to `MQL5/Indicators/` (or keep it in your current folder) and compile in MetaEditor.
2. In MT5, add the indicator to the desired chart/timeframe.
3. Tune first:

- `InpWindow`, `InpSlopeNormMode`, `InpSlopeThresholdMean/Std`, `InpR2Threshold`

4. Tune zone formation:

- `InpMinZoneBars`, `InpGapTolerance`, `InpExtendUntilBreak`, `InpBreakMarginPoints`

5. Tune visuals/HUD:

- transparency parameters, border width, projections, and HUD

6. For zone energy:

- enable `InpEnableZoneEnergy` and adjust scales/weights for your instrument and timeframe

## Parameters (`input`)

### 1) Regression and Regime

| Parameter               | Type                   |           Default | Description                                          |
| ----------------------- | ---------------------- | ----------------: | ---------------------------------------------------- |
| `InpWindow`             | `int`                  |             `180` | Linear regression window (bars).                     |
| `InpSlopeNormMode`      | `ENUM_SLOPE_NORM_MODE` | `SLOPE_NORM_MEAN` | Slope normalization mode (`MEAN` or `STD`).          |
| `InpSlopeThresholdMean` | `double`               |          `0.0001` | Slope threshold in `MEAN` mode.                      |
| `InpSlopeThresholdStd`  | `double`               |            `0.20` | Slope threshold in `STD` mode.                       |
| `InpR2Threshold`        | `double`               |            `0.20` | Maximum R² to classify as ranging.                   |
| `InpScoreSlopeWeight`   | `double`               |            `0.65` | Slope weight in score (R² weight = `1 - weight`).    |

### 2) Zones

| Parameter                        | Type     | Default | Description                                         |
| -------------------------------- | -------- | ------: | --------------------------------------------------- |
| `InpMinZoneBars`                 | `int`    |    `20` | Minimum bars required to validate a zone.           |
| `InpGapTolerance`                | `int`    |     `5` | Maximum non-ranging bars inside a cluster.          |
| `InpExtendUntilBreak`            | `bool`   |  `true` | Extends the zone until breakout.                    |
| `InpBreakMarginPoints`           | `double` |    `50` | Margin (points) to confirm breakout.                |
| `InpMaxZonesOnChart`             | `int`    |     `3` | Maximum number of zones in multi-zone mode.         |
| `InpOnlyLastActiveAndLastBroken` | `bool`   |  `true` | Shows only last active zone + last broken zone.     |

### 3) Zone Visuals and Arrows

| Parameter           | Type   | Default | Description                                   |
| ------------------- | ------ | ------: | --------------------------------------------- |
| `InpKeepArrows`     | `bool` |  `true` | Shows arrows on ranging candles.              |
| `InpDrawMidLine`    | `bool` |  `true` | Draws the zone midline.                       |
| `InpAlphaMin`       | `int`  |    `35` | Minimum zone alpha (`0..255`).                |
| `InpAlphaMax`       | `int`  |    `90` | Maximum zone alpha (`0..255`).                |
| `InpAlphaLenScale`  | `int`  |   `120` | Duration scale for alpha interpolation.       |
| `InpBorderMinWidth` | `int`  |     `1` | Minimum zone border width.                    |
| `InpBorderMaxWidth` | `int`  |     `4` | Maximum zone border width.                    |

### 4) Horizontal Projections

| Parameter                        | Type    |   Default | Description                                |
| -------------------------------- | ------- | --------: | ------------------------------------------ |
| `InpDrawProjectionLines`         | `bool`  |    `true` | Enables projection lines.                  |
| `InpProjectionCount`             | `int`   |       `5` | Levels above and below the zone.           |
| `InpProjectionIncludeZoneLevels` | `bool`  |    `true` | Includes zone `top/mid/bottom`.            |
| `InpProjectionLineWidth`         | `int`   |       `1` | Projection line thickness.                 |
| `InpProjectionLineAlpha`         | `int`   |     `160` | Projection line alpha (`0..255`).          |
| `InpProjectionLineColor`         | `color` | `clrGold` | Projection line color.                     |

### 5) HUD (Trend HUD)

| Parameter             | Type     | Default | Description                                  |
| --------------------- | -------- | ------: | -------------------------------------------- |
| `InpEnableTrendHUD`   | `bool`   |  `true` | Enables HUD.                                 |
| `InpShowTrendDetails` | `bool`   | `false` | Shows an extra line with `R2/ER/S`.          |
| `InpHUDDraggable`     | `bool`   |  `true` | Allows dragging the HUD on chart.            |
| `InpHUDXDefault`      | `int`    |    `12` | Default HUD X offset.                        |
| `InpHUDYDefault`      | `int`    |    `12` | Default HUD Y offset.                        |
| `InpHUDFontSize`      | `int`    |    `10` | HUD font size.                               |
| `InpHUDWidth`         | `int`    |   `240` | Minimum HUD panel width.                     |
| `InpHUDHeight`        | `int`    |    `86` | Minimum HUD panel height.                    |
| `InpHUDAlphaMin`      | `int`    |   `170` | Minimum HUD alpha (`0..255`).                |
| `InpHUDAlphaMax`      | `int`    |   `255` | Maximum HUD alpha (`0..255`).                |
| `InpBarHeight`        | `int`    |    `10` | Strength bar height at HUD footer.           |
| `InpBarMarginX`       | `int`    |    `10` | Bar X margin (reserved/compat).              |
| `InpBarMarginBottom`  | `int`    |    `10` | Bar bottom margin (reserved/compat).         |
| `InpTrendThreshold`   | `double` |  `0.60` | Threshold to classify regime as TREND.       |
| `InpTrendWeightSlope` | `double` |  `0.40` | Slope weight in `trend_strength`.            |
| `InpTrendWeightR2`    | `double` |  `0.40` | R² weight in `trend_strength`.               |
| `InpTrendWeightER`    | `double` |  `0.20` | ER weight in `trend_strength`.               |

### 6) Zone Energy

| Parameter                        | Type     | Default | Description                                        |
| -------------------------------- | -------- | ------: | -------------------------------------------------- |
| `InpEnableZoneEnergy`            | `bool`   |  `true` | Enables calculation and display of `ZONE ENERGY`.  |
| `InpZoneEnergyLenScale`          | `int`    |   `120` | Duration scale for `EnergyLen` component.          |
| `InpZoneEnergyTouchMarginPoints` | `int`    |    `30` | Margin (points) to count top/bottom touches.       |
| `InpZoneEnergyTouchScale`        | `int`    |    `12` | Touch normalization scale.                         |
| `InpZoneEnergyWeightLen`         | `double` |  `0.30` | Duration weight.                                   |
| `InpZoneEnergyWeightComp`        | `double` |  `0.35` | Compression weight.                                |
| `InpZoneEnergyWeightChop`        | `double` |  `0.20` | Chop weight (1-ER of the zone).                    |
| `InpZoneEnergyWeightTouch`       | `double` |  `0.15` | Edge-touch weight.                                 |

> Note: energy weights are automatically normalized if their sum is different from `1`.

### 7) Execution and Debug

| Parameter                    | Type   | Default | Description                                                    |
| ---------------------------- | ------ | ------: | -------------------------------------------------------------- |
| `InpDebug`                   | `bool` | `false` | Enables debug logs in Journal.                                 |
| `InpOnCalculateDelaySeconds` | `int`  |     `5` | Minimum delay between `OnCalculate` executions (`0` disables). |

## Notes

- The indicator uses a price-statistics approach; it does not depend on classic financial indicators.
- In `OnInit`, the code removes objects from the current chart (`ObjectsDeleteAll`).
