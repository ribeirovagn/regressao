# MarketRegime Zones (v2.13)

Indicador MQL5 para identificar regime de mercado com base em estatística de preço (regressão linear no `close`), detectar zonas de lateralidade, projetar níveis e exibir HUD de leitura rápida.

## Resumo de funcionalidades

- Detecta lateralidade com regra objetiva: `|slope_norm| < threshold` e `R² < InpR2Threshold`.
- Cria zonas por cluster de candles laterais (com tolerância a gaps), com estado:
  - ativa (`Z_ACTIVE`)
  - rompida para cima (`Z_BREAK_UP`)
  - rompida para baixo (`Z_BREAK_DOWN`)
- Renderiza zonas com transparência por duração e borda por score médio.
- Opcionalmente estende zona até rompimento e desenha linha média (`mid`).
- Projeta níveis horizontais a partir da zona mais recente.
- Mostra HUD de regime/direção/força e, quando disponível, `ZONE ENERGY`.
- `ZONE ENERGY` é calculada só com estatística de preço (duração, compressão, chop e toques nas bordas).

## Como usar (rápido)

1. Copie `Lateralidade.mq5` para `MQL5/Indicators/` (ou mantenha na sua pasta atual) e compile no MetaEditor.
2. No MT5, adicione o indicador no gráfico/timeframe desejado.
3. Ajuste primeiro:
- `InpWindow`, `InpSlopeNormMode`, `InpSlopeThresholdMean/Std`, `InpR2Threshold`
4. Ajuste a formação das zonas:
- `InpMinZoneBars`, `InpGapTolerance`, `InpExtendUntilBreak`, `InpBreakMarginPoints`
5. Ajuste visual/HUD:
- parâmetros de transparência, largura de borda, projeções e HUD
6. Para energia da zona:
- ative `InpEnableZoneEnergy` e ajuste escalas/pesos conforme ativo e timeframe

## Parâmetros (`input`)

### 1) Regressão e regime

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---:|---|
| `InpWindow` | `int` | `180` | Janela (barras) da regressão linear. |
| `InpSlopeNormMode` | `ENUM_SLOPE_NORM_MODE` | `SLOPE_NORM_MEAN` | Modo de normalização do slope (`MEAN` ou `STD`). |
| `InpSlopeThresholdMean` | `double` | `0.0001` | Threshold de slope no modo `MEAN`. |
| `InpSlopeThresholdStd` | `double` | `0.20` | Threshold de slope no modo `STD`. |
| `InpR2Threshold` | `double` | `0.20` | R² máximo para classificar lateralidade. |
| `InpScoreSlopeWeight` | `double` | `0.65` | Peso do slope no score (peso de R² = `1 - peso`). |

### 2) Zonas

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---:|---|
| `InpMinZoneBars` | `int` | `20` | Mínimo de barras para validar zona. |
| `InpGapTolerance` | `int` | `5` | Máximo de barras não laterais dentro do cluster. |
| `InpExtendUntilBreak` | `bool` | `true` | Estende zona até rompimento. |
| `InpBreakMarginPoints` | `double` | `50` | Margem (pontos) para confirmar rompimento. |
| `InpMaxZonesOnChart` | `int` | `3` | Máximo de zonas no modo múltiplo. |
| `InpOnlyLastActiveAndLastBroken` | `bool` | `true` | Mostra só última ativa + última rompida. |

### 3) Visual da zona e setas

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---:|---|
| `InpKeepArrows` | `bool` | `true` | Mostra setas nos candles laterais. |
| `InpDrawMidLine` | `bool` | `true` | Desenha linha média da zona. |
| `InpAlphaMin` | `int` | `35` | Alpha mínimo da zona (`0..255`). |
| `InpAlphaMax` | `int` | `90` | Alpha máximo da zona (`0..255`). |
| `InpAlphaLenScale` | `int` | `120` | Escala de duração para interpolação de alpha. |
| `InpBorderMinWidth` | `int` | `1` | Largura mínima da borda da zona. |
| `InpBorderMaxWidth` | `int` | `4` | Largura máxima da borda da zona. |

### 4) Projeções horizontais

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---:|---|
| `InpDrawProjectionLines` | `bool` | `true` | Ativa linhas de projeção. |
| `InpProjectionCount` | `int` | `5` | Níveis acima e abaixo da zona. |
| `InpProjectionIncludeZoneLevels` | `bool` | `true` | Inclui `top/mid/bottom` da zona. |
| `InpProjectionLineWidth` | `int` | `1` | Espessura das linhas de projeção. |
| `InpProjectionLineAlpha` | `int` | `160` | Alpha das linhas de projeção (`0..255`). |
| `InpProjectionLineColor` | `color` | `clrGold` | Cor das projeções. |

### 5) HUD (Trend HUD)

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---:|---|
| `InpEnableTrendHUD` | `bool` | `true` | Habilita HUD. |
| `InpShowTrendDetails` | `bool` | `false` | Mostra linha com `R2/ER/S`. |
| `InpHUDDraggable` | `bool` | `true` | Permite arrastar HUD no gráfico. |
| `InpHUDXDefault` | `int` | `12` | Offset X padrão do HUD. |
| `InpHUDYDefault` | `int` | `12` | Offset Y padrão do HUD. |
| `InpHUDFontSize` | `int` | `10` | Tamanho da fonte do HUD. |
| `InpHUDWidth` | `int` | `240` | Largura mínima do painel HUD. |
| `InpHUDHeight` | `int` | `86` | Altura mínima do painel HUD. |
| `InpHUDAlphaMin` | `int` | `170` | Alpha mínimo do HUD (`0..255`). |
| `InpHUDAlphaMax` | `int` | `255` | Alpha máximo do HUD (`0..255`). |
| `InpBarHeight` | `int` | `10` | Altura da barra de força no rodapé do HUD. |
| `InpBarMarginX` | `int` | `10` | Margem X da barra (reservado/compat). |
| `InpBarMarginBottom` | `int` | `10` | Margem inferior da barra (reservado/compat). |
| `InpTrendThreshold` | `double` | `0.60` | Limiar para classificar regime como TREND. |
| `InpTrendWeightSlope` | `double` | `0.40` | Peso do slope no `trend_strength`. |
| `InpTrendWeightR2` | `double` | `0.40` | Peso do R² no `trend_strength`. |
| `InpTrendWeightER` | `double` | `0.20` | Peso do ER no `trend_strength`. |

### 6) Zone Energy

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---:|---|
| `InpEnableZoneEnergy` | `bool` | `true` | Habilita cálculo e exibição de `ZONE ENERGY`. |
| `InpZoneEnergyLenScale` | `int` | `120` | Escala de duração para componente `EnergyLen`. |
| `InpZoneEnergyTouchMarginPoints` | `int` | `30` | Margem (pontos) para contar toques no topo/fundo. |
| `InpZoneEnergyTouchScale` | `int` | `12` | Escala de normalização dos toques. |
| `InpZoneEnergyWeightLen` | `double` | `0.30` | Peso da duração. |
| `InpZoneEnergyWeightComp` | `double` | `0.35` | Peso da compressão. |
| `InpZoneEnergyWeightChop` | `double` | `0.20` | Peso do chop (1-ER da zona). |
| `InpZoneEnergyWeightTouch` | `double` | `0.15` | Peso dos toques nas bordas. |

> Observação: os pesos de energia são normalizados automaticamente se a soma for diferente de `1`.

### 7) Execução e debug

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---:|---|
| `InpDebug` | `bool` | `false` | Liga logs de debug no Journal. |
| `InpOnCalculateDelaySeconds` | `int` | `5` | Delay mínimo entre execuções do `OnCalculate` (`0` desativa). |

## Notas

- O indicador usa abordagem estatística de preço; não depende de indicadores financeiros clássicos.
- Em `OnInit`, o código remove objetos do gráfico atual (`ObjectsDeleteAll`).
