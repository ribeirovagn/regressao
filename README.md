# Lateralidade.mq5 - Parâmetros

Este indicador detecta lateralidade via regressão linear e desenha zonas no gráfico.  
Resumo dos parâmetros de entrada (`input`):

| Parâmetro | Tipo | Padrão | Resumo |
|---|---|---:|---|
| `InpWindow` | `int` | `50` | Tamanho da janela (em candles) usada na regressão linear. |
| `InpSlopeNormMode` | `ENUM_SLOPE_NORM_MODE` | `SLOPE_NORM_STD` | Modo de normalização do slope (`MEAN` ou `STD`). |
| `InpSlopeThresholdMean` | `double` | `0.0001` | Limite do slope quando o modo é `SLOPE_NORM_MEAN`. |
| `InpSlopeThresholdStd` | `double` | `0.20` | Limite do slope quando o modo é `SLOPE_NORM_STD`. |
| `InpR2Threshold` | `double` | `0.20` | Limite máximo de R² para considerar o trecho como lateral. |
| `InpScoreSlopeWeight` | `double` | `0.65` | Peso do slope no score de lateralidade (0 a 1). |
| `InpMinZoneBars` | `int` | `20` | Quantidade mínima de candles para validar uma zona. |
| `InpGapTolerance` | `int` | `3` | Tolerância de falhas (candles não laterais) dentro do cluster. |
| `InpExtendUntilBreak` | `bool` | `true` | Se `true`, estende a zona até detectar rompimento. |
| `InpBreakMarginPoints` | `double` | `50` | Margem em pontos usada para confirmar rompimento da zona. |
| `InpMaxZonesOnChart` | `int` | `20` | Máximo de zonas desenhadas quando o modo "somente últimas" está desativado. |
| `InpKeepArrows` | `bool` | `true` | Mantém setas nos candles identificados como laterais. |
| `InpDrawMidLine` | `bool` | `true` | Desenha a linha média (mid) dentro de cada zona. |
| `InpAlphaMin` | `int` | `35` | Transparência mínima (0 a 255) das zonas. |
| `InpAlphaMax` | `int` | `90` | Transparência máxima (0 a 255) das zonas. |
| `InpAlphaLenScale` | `int` | `120` | Escala de duração para interpolar transparência por tamanho da zona. |
| `InpBorderMinWidth` | `int` | `1` | Largura mínima da borda da zona. |
| `InpBorderMaxWidth` | `int` | `4` | Largura máxima da borda da zona (conforme score médio). |
| `InpOnlyLastActiveAndLastBroken` | `bool` | `true` | Mostra apenas a última zona ativa e a última zona rompida. |
| `InpDrawProjectionLines` | `bool` | `true` | Liga/desliga linhas horizontais de projeção da zona mais recente. |
| `InpProjectionCount` | `int` | `5` | Número de níveis projetados acima e abaixo da zona. |
| `InpProjectionIncludeZoneLevels` | `bool` | `true` | Inclui também os níveis base da zona (`top`, `mid`, `bottom`). |
| `InpProjectionLineWidth` | `int` | `1` | Espessura das linhas de projeção. |
| `InpProjectionLineAlpha` | `int` | `160` | Transparência (0 a 255) das linhas de projeção. |
| `InpProjectionLineColor` | `color` | `clrGold` | Cor das linhas de projeção. |
| `InpDebug` | `bool` | `false` | Ativa logs de debug no Journal. |
| `InpUpdateOnlyOnNewBar` | `bool` | `true` | Declarado para controle de atualização, mas atualmente não é usado na lógica. |
| `InpRedrawNow` | `bool` | `false` | Declarado para forçar redraw, mas atualmente não é usado na lógica. |

