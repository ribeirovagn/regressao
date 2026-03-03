# Lateralidade.mq5

Indicador de lateralidade para MT5 baseado em regressão linear no `close`, com detecção e renderização de zonas de consolidação.

## Funcionalidades

- Detecta lateralidade com regra objetiva: `|slope_norm| < threshold` e `R² < InpR2Threshold`.
- Suporta dois modos de normalização do slope:
  - `SLOPE_NORM_MEAN`: `b / mean(y)`
  - `SLOPE_NORM_STD`: `b * (n-1) / stdev(y)`
- Calcula score de lateralidade (`0..1`) combinando slope e R² com peso configurável.
- Agrupa candles laterais em zonas com:
  - tamanho mínimo (`InpMinZoneBars`)
  - tolerância de gaps (`InpGapTolerance`)
- Estende zonas até o rompimento (opcional), classificando estado:
  - ativa (`Z_ACTIVE`)
  - rompida para cima (`Z_BREAK_UP`)
  - rompida para baixo (`Z_BREAK_DOWN`)
- Renderiza zonas com:
  - retângulo preenchido
  - transparência proporcional à duração da zona
  - largura da borda proporcional ao score médio
  - linha média opcional (`mid`)
- Dois modos de exibição:
  - apenas última zona ativa + última rompida
  - múltiplas zonas (limitadas por `InpMaxZonesOnChart`)
- Projeção de linhas horizontais baseada na zona mais recente (top/mid/bottom + níveis acima/abaixo).
- Setas opcionais nos candles classificados como laterais.
- Ao iniciar, apaga todos os objetos existentes no gráfico.
- Permite limitar a frequência de execução do `OnCalculate` com delay em segundos.

## Parâmetros (`input`)

| Parâmetro | Tipo | Padrão | Resumo |
|---|---|---:|---|
| `InpWindow` | `int` | `180` | Tamanho da janela (candles) usada na regressão linear. |
| `InpSlopeNormMode` | `ENUM_SLOPE_NORM_MODE` | `SLOPE_NORM_MEAN` | Modo de normalização do slope (`MEAN` ou `STD`). |
| `InpSlopeThresholdMean` | `double` | `0.0001` | Limite do slope normalizado no modo `SLOPE_NORM_MEAN`. |
| `InpSlopeThresholdStd` | `double` | `0.20` | Limite do slope normalizado no modo `SLOPE_NORM_STD`. |
| `InpR2Threshold` | `double` | `0.20` | Limite máximo de R² para considerar lateralidade. |
| `InpScoreSlopeWeight` | `double` | `0.65` | Peso do slope no score (0..1). O peso de R² é `1 - InpScoreSlopeWeight`. |
| `InpMinZoneBars` | `int` | `20` | Número mínimo de candles para validar uma zona. |
| `InpGapTolerance` | `int` | `5` | Quantidade máxima de candles não laterais permitida dentro do cluster. |
| `InpExtendUntilBreak` | `bool` | `true` | Se ativo, estende a zona até detectar rompimento. |
| `InpBreakMarginPoints` | `double` | `50` | Margem (em pontos) para confirmar rompimento acima/abaixo da zona. |
| `InpMaxZonesOnChart` | `int` | `3` | Máximo de zonas desenhadas no modo de múltiplas zonas. |
| `InpKeepArrows` | `bool` | `true` | Exibe setas nos candles laterais. |
| `InpDrawMidLine` | `bool` | `true` | Desenha a linha média da zona. |
| `InpAlphaMin` | `int` | `35` | Alpha mínimo (0..255) para preenchimento das zonas. |
| `InpAlphaMax` | `int` | `90` | Alpha máximo (0..255) para preenchimento das zonas. |
| `InpAlphaLenScale` | `int` | `120` | Escala de duração para interpolação de transparência. |
| `InpBorderMinWidth` | `int` | `1` | Espessura mínima da borda da zona. |
| `InpBorderMaxWidth` | `int` | `4` | Espessura máxima da borda da zona. |
| `InpOnlyLastActiveAndLastBroken` | `bool` | `true` | Mostra apenas a última zona ativa e a última rompida. |
| `InpDrawProjectionLines` | `bool` | `true` | Habilita linhas de projeção horizontais da zona mais recente. |
| `InpProjectionCount` | `int` | `5` | Número de níveis acima e abaixo da zona. |
| `InpProjectionIncludeZoneLevels` | `bool` | `true` | Inclui níveis base da zona (`top`, `mid`, `bottom`). |
| `InpProjectionLineWidth` | `int` | `1` | Espessura das linhas de projeção. |
| `InpProjectionLineAlpha` | `int` | `160` | Transparência (0..255) das linhas de projeção. |
| `InpProjectionLineColor` | `color` | `clrGold` | Cor das linhas de projeção. |
| `InpDebug` | `bool` | `false` | Ativa logs de debug no Journal. |
| `InpOnCalculateDelaySeconds` | `int` | `5` | Delay mínimo (em segundos) entre execuções do `OnCalculate` (`0` desativa). |
