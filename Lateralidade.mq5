//+------------------------------------------------------------------+
//|                          Lateralidade_Zonas.mq5 (v2.12)           |
//|   Lateralidade (LR Close) + Zonas (clusters)                      |
//|   - Cor por rompimento: ativo=azul, up=verde, down=vermelho       |
//|   - Linha média da zona (mid)                                     |
//|   - Força: borda mais grossa por score médio                      |
//|   - Transparência proporcional à duração                          |
//|   - Modo "zona ativa": mantém só a última ativa e a última rompida|
//|   - Linhas horizontais (projeção) baseadas na zona mais recente   |
//+------------------------------------------------------------------+
#property copyright "Vagner Ribeiro"
#property link "https://www.mql5.com"
#property version "2.12"
#property strict

#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots 1

#property indicator_label1 "LateralMarker"
#property indicator_type1 DRAW_ARROW
#property indicator_color1 clrLimeGreen
#property indicator_width1 1

//---------------- INPUTS --------------------------------------------
// LR window
input int InpWindow = 180;

// Normalização do slope:
// 0 = b/mean(y)
// 1 = b*(n-1)/stdev(y)
enum ENUM_SLOPE_NORM_MODE
{
  SLOPE_NORM_MEAN = 0,
  SLOPE_NORM_STD = 1
};
input ENUM_SLOPE_NORM_MODE InpSlopeNormMode = SLOPE_NORM_MEAN;

// Thresholds separados por modo
input double InpSlopeThresholdMean = 0.0001; // use com SLOPE_NORM_MEAN
input double InpSlopeThresholdStd = 0.20;    // use com SLOPE_NORM_STD

// Tendência (R²)
input double InpR2Threshold = 0.20;

// Score (informativo)
input double InpScoreSlopeWeight = 0.65; // peso do slope no score 0..1

// Zonas (clusters)
input int InpMinZoneBars = 20;
input int InpGapTolerance = 5;

// Extensão por rompimento
input bool InpExtendUntilBreak = true;
input double InpBreakMarginPoints = 50;

// Visual
input int InpMaxZonesOnChart = 3;
input bool InpKeepArrows = true;
input bool InpDrawMidLine = true;

// Transparência por duração (len)
input int InpAlphaMin = 35;       // 0..255 (mais baixo = mais transparente)
input int InpAlphaMax = 90;       // 0..255 (mais alto = mais sólido)
input int InpAlphaLenScale = 120; // len >= scale tende a usar AlphaMax

// Força (largura da borda por score médio)
input int InpBorderMinWidth = 1;
input int InpBorderMaxWidth = 4;

// Modo "zona ativa": manter só a última zona ativa + última rompida
input bool InpOnlyLastActiveAndLastBroken = true;

// --- PROJEÇÃO DE LINHAS HORIZONTAIS (zona mais recente) ------------
input bool InpDrawProjectionLines = true;
input int InpProjectionCount = 5;                 // N linhas acima e N abaixo
input bool InpProjectionIncludeZoneLevels = true; // desenha top/mid/bottom também
input int InpProjectionLineWidth = 1;
input int InpProjectionLineAlpha = 160;       // 0..255
input color InpProjectionLineColor = clrGold; // cor das linhas

// Debug
input bool InpDebug = false;

// Atualização incremental / redraw

input int InpOnCalculateDelaySeconds = 5; // 0 = sem delay

//---------------- BUFFERS -------------------------------------------
double MarkerBuffer[];    // plot (setas)
double ScoreBuffer[];     // calc
double FlagBuffer[];      // calc (0/1) => usado para zonas
double SlopeNormBuffer[]; // calc
double R2Buffer[];        // calc
double DummyBuffer[];     // calc

//---------------- TYPES --------------------------------------------
enum ENUM_ZONE_STATE
{
  Z_ACTIVE = 0,
  Z_BREAK_UP = 1,
  Z_BREAK_DOWN = 2
};

struct ZoneInfo
{
  bool valid;
  datetime t_left;  // mais antigo (esquerda)
  datetime t_right; // mais recente (direita; pode estender até rompimento)
  double top;
  double bottom;
  double mid;
  int length;
  double avgScore;
  ENUM_ZONE_STATE state;
};

//---------------- HELPERS -------------------------------------------
double Clamp01(const double v) { return (v < 0 ? 0 : (v > 1 ? 1 : v)); }
int ClampInt(const int v, const int lo, const int hi) { return (v < lo ? lo : (v > hi ? hi : v)); }

uchar ComputeAlphaByLen(const int len)
{
  int aMin = ClampInt(InpAlphaMin, 0, 255);
  int aMax = ClampInt(InpAlphaMax, 0, 255);
  if (aMax < aMin)
  {
    int t = aMin;
    aMin = aMax;
    aMax = t;
  }

  int scale = MathMax(InpAlphaLenScale, 1);
  double t = (double)len / (double)scale;
  if (t > 1.0)
    t = 1.0;
  int alpha = (int)MathRound(aMin + (aMax - aMin) * t);
  alpha = ClampInt(alpha, 0, 255);
  return (uchar)alpha;
}

int ComputeBorderWidthByScore(const double avgScore)
{
  int wMin = MathMax(InpBorderMinWidth, 1);
  int wMax = MathMax(InpBorderMaxWidth, wMin);

  double s = Clamp01(avgScore);
  int w = (int)MathRound(wMin + (wMax - wMin) * s);
  return ClampInt(w, wMin, wMax);
}

double GetSlopeThreshold()
{
  if (InpSlopeNormMode == SLOPE_NORM_MEAN)
    return (InpSlopeThresholdMean > 0.0 ? InpSlopeThresholdMean : 0.0001);
  return (InpSlopeThresholdStd > 0.0 ? InpSlopeThresholdStd : 0.20);
}

void DeleteByPrefix(const string prefix)
{
  int total = ObjectsTotal(0, 0, -1);
  for (int i = total - 1; i >= 0; --i)
  {
    string name = ObjectName(0, i, 0, -1);
    if (StringFind(name, prefix) == 0)
      ObjectDelete(0, name);
  }
}

string ZoneRectName(const int idx, const datetime t1, const datetime t2)
{
  return StringFormat("LZ_RECT_%d_%I64d_%I64d", idx, (long)t1, (long)t2);
}
string ZoneMidName(const int idx, const datetime t1, const datetime t2)
{
  return StringFormat("LZ_MID_%d_%I64d_%I64d", idx, (long)t1, (long)t2);
}

color ZoneBaseColor(const ENUM_ZONE_STATE st)
{
  if (st == Z_BREAK_UP)
    return clrLimeGreen;
  if (st == Z_BREAK_DOWN)
    return clrTomato;
  return clrDodgerBlue; // ativo
}

void DrawZone(const int idx, const ZoneInfo &z)
{
  if (!z.valid)
    return;

  uchar alpha = ComputeAlphaByLen(z.length);
  int width = ComputeBorderWidthByScore(z.avgScore);
  color base = ZoneBaseColor(z.state);
  color c = ColorToARGB(base, alpha);

  string rect = ZoneRectName(idx, z.t_left, z.t_right);

  if (ObjectCreate(0, rect, OBJ_RECTANGLE, 0, z.t_left, z.top, z.t_right, z.bottom))
  {
    ObjectSetInteger(0, rect, OBJPROP_COLOR, c);
    ObjectSetInteger(0, rect, OBJPROP_BACK, true);
    ObjectSetInteger(0, rect, OBJPROP_FILL, true);
    ObjectSetInteger(0, rect, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, rect, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, rect, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, rect, OBJPROP_HIDDEN, true);
  }

  if (InpDrawMidLine)
  {
    string mid = ZoneMidName(idx, z.t_left, z.t_right);
    if (ObjectCreate(0, mid, OBJ_TREND, 0, z.t_left, z.mid, z.t_right, z.mid))
    {
      ObjectSetInteger(0, mid, OBJPROP_COLOR, ColorToARGB(clrSilver, ClampInt(alpha + 40, 0, 255)));
      ObjectSetInteger(0, mid, OBJPROP_WIDTH, MathMax(1, width));
      ObjectSetInteger(0, mid, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, mid, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, mid, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, mid, OBJPROP_BACK, true);
      ObjectSetInteger(0, mid, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, mid, OBJPROP_HIDDEN, true);
    }
  }
}

//---------------- PROJECTION LINES ----------------------------------
void DrawHLine(const string name, const double price, const color c, const int width)
{
  if (ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
  {
    ObjectSetInteger(0, name, OBJPROP_COLOR, c);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }
}

void DrawProjectionFromZone(const ZoneInfo &z)
{
  if (!InpDrawProjectionLines || !z.valid)
    return;

  const double step = (z.top - z.bottom);
  if (step <= 0.0)
    return;

  const int cnt = MathMax(1, InpProjectionCount);
  const int w = MathMax(1, InpProjectionLineWidth);
  const uchar a = (uchar)ClampInt(InpProjectionLineAlpha, 0, 255);

  const color c = ColorToARGB(InpProjectionLineColor, a);

  int idx = 0;

  if (InpProjectionIncludeZoneLevels)
  {
    DrawHLine(StringFormat("LZ_LVL_%d_TOP", idx++), z.top, c, w);
    DrawHLine(StringFormat("LZ_LVL_%d_MID", idx++), z.mid, c, w);
    DrawHLine(StringFormat("LZ_LVL_%d_BOT", idx++), z.bottom, c, w);
  }

  for (int k = 1; k <= cnt; ++k)
  {
    DrawHLine(StringFormat("LZ_LVL_%d_UP_%d", idx++, k), z.top + step * k, c, w);
    DrawHLine(StringFormat("LZ_LVL_%d_DN_%d", idx++, k), z.bottom - step * k, c, w);
  }

  if (InpDebug)
    PrintFormat("[LZ] Projection step=%.5f cnt=%d (from zone top=%.5f bot=%.5f)",
                step, cnt, z.top, z.bottom);
}

long HashMix(const long h, const long v)
{
  return (h ^ v) * 1099511628211;
}

long PriceToKey(const double price)
{
  if (_Point > 0.0)
    return (long)MathRound(price / _Point);
  return (long)MathRound(price * 100000000.0);
}

long HashZone(const ZoneInfo &z)
{
  long h = 1469598103934665603;
  if (!z.valid)
    return HashMix(h, -1);

  h = HashMix(h, 1);
  h = HashMix(h, (long)z.t_left);
  h = HashMix(h, (long)z.t_right);
  h = HashMix(h, PriceToKey(z.top));
  h = HashMix(h, PriceToKey(z.bottom));
  h = HashMix(h, (long)z.state);
  h = HashMix(h, (long)z.length);
  return h;
}

long BuildRenderSignature(const ZoneInfo &mostRecent,
                          const ZoneInfo &lastActive,
                          const ZoneInfo &lastBroken,
                          const int drawnCount,
                          const bool hasProjection)
{
  long h = 1469598103934665603;
  h = HashMix(h, HashZone(mostRecent));
  h = HashMix(h, HashZone(lastActive));
  h = HashMix(h, HashZone(lastBroken));
  h = HashMix(h, (long)drawnCount);
  h = HashMix(h, (hasProjection ? 1 : 0));
  h = HashMix(h, (InpOnlyLastActiveAndLastBroken ? 1 : 0));
  return h;
}

//+------------------------------------------------------------------+
int OnInit()
{
  ObjectsDeleteAll(0, -1, -1);

  if (InpWindow < 2)
    return INIT_PARAMETERS_INCORRECT;
  if (InpR2Threshold <= 0.0)
    return INIT_PARAMETERS_INCORRECT;
  if (InpMinZoneBars < 2)
    return INIT_PARAMETERS_INCORRECT;
  if (InpGapTolerance < 0)
    return INIT_PARAMETERS_INCORRECT;
  if (InpOnCalculateDelaySeconds < 0)
    return INIT_PARAMETERS_INCORRECT;

  SetIndexBuffer(0, MarkerBuffer, INDICATOR_DATA);
  SetIndexBuffer(1, ScoreBuffer, INDICATOR_CALCULATIONS);
  SetIndexBuffer(2, FlagBuffer, INDICATOR_CALCULATIONS);
  SetIndexBuffer(3, SlopeNormBuffer, INDICATOR_CALCULATIONS);
  SetIndexBuffer(4, R2Buffer, INDICATOR_CALCULATIONS);
  SetIndexBuffer(5, DummyBuffer, INDICATOR_CALCULATIONS);

  ArraySetAsSeries(MarkerBuffer, true);
  ArraySetAsSeries(ScoreBuffer, true);
  ArraySetAsSeries(FlagBuffer, true);
  ArraySetAsSeries(SlopeNormBuffer, true);
  ArraySetAsSeries(R2Buffer, true);
  ArraySetAsSeries(DummyBuffer, true);

  PlotIndexSetInteger(0, PLOT_ARROW, 233);
  PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -8);
  PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

  IndicatorSetString(INDICATOR_SHORTNAME, "Lateralidade + Zonas (v2.11)");

  return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
  const double eps = 1.0e-12;
  static ulong last_exec_ms = 0;

  const int delay_seconds = MathMax(InpOnCalculateDelaySeconds, 0);
  if (delay_seconds > 0)
  {
    const ulong now_ms = GetTickCount64();
    const ulong delay_ms = (ulong)delay_seconds * 1000ULL;
    if (last_exec_ms != 0 && (now_ms - last_exec_ms) < delay_ms)
      return prev_calculated;
    last_exec_ms = now_ms;
  }

  Print("EXECUTOU MAIS UM CALCULO");

  if (rates_total < InpWindow)
    return rates_total;

  ArraySetAsSeries(time, true);
  ArraySetAsSeries(high, true);
  ArraySetAsSeries(low, true);
  ArraySetAsSeries(close, true);

  const int window = InpWindow;
  const double n = (double)window;
  const int last_valid = rates_total - window;
  if (last_valid < 0)
    return rates_total;

  // limpar região sem janela completa
  for (int i = rates_total - 1; i > last_valid; --i)
  {
    MarkerBuffer[i] = EMPTY_VALUE;
    ScoreBuffer[i] = EMPTY_VALUE;
    FlagBuffer[i] = 0.0;
    SlopeNormBuffer[i] = EMPTY_VALUE;
    R2Buffer[i] = EMPTY_VALUE;
  }

  // pré-somas de x=0..n-1
  const double sum_x = n * (n - 1.0) * 0.5;
  const double sum_x2 = n * (n - 1.0) * (2.0 * n - 1.0) / 6.0;
  const double denom = n * sum_x2 - sum_x * sum_x;
  if (MathAbs(denom) <= eps)
    return prev_calculated;

  const double slope_th = GetSlopeThreshold();
  const double wSlope = Clamp01(InpScoreSlopeWeight);
  const double wR2 = 1.0 - wSlope;

  // 1) calcular LR + R2 + score + flag
  for (int i = last_valid; i >= 0; --i)
  {
    double sum_y = 0.0;
    double sum_xy = 0.0;
    double sum_y2 = 0.0;

    for (int k = 0; k < window; ++k)
    {
      const double y = close[i + k];
      sum_y += y;
      sum_xy += (double)k * y;
      sum_y2 += y * y;
    }

    const double b = (n * sum_xy - sum_x * sum_y) / denom;
    const double mean_y = sum_y / n;
    const double ss_tot = sum_y2 - (sum_y * sum_y) / n;

    // slope norm
    double b_norm = 0.0;
    if (InpSlopeNormMode == SLOPE_NORM_MEAN)
    {
      if (MathAbs(mean_y) > eps)
        b_norm = b / mean_y;
    }
    else // STD
    {
      if (ss_tot > eps && (n - 1.0) > 0.0)
      {
        const double sigma = MathSqrt(ss_tot / (n - 1.0));
        if (sigma > eps)
          b_norm = b * (n - 1.0) / sigma;
      }
    }

    // R²
    double r2 = 0.0;
    if (ss_tot > eps)
    {
      const double a = (sum_y - b * sum_x) / n;
      double ss_res = 0.0;
      for (int k = 0; k < window; ++k)
      {
        const double yhat = a + b * (double)k;
        const double e = close[i + k] - yhat;
        ss_res += e * e;
      }
      r2 = Clamp01(1.0 - (ss_res / ss_tot));
    }

    SlopeNormBuffer[i] = b_norm;
    R2Buffer[i] = r2;

    // Regra dura de lateralidade
    const bool lateral = (MathAbs(b_norm) < slope_th && r2 < InpR2Threshold);
    FlagBuffer[i] = lateral ? 1.0 : 0.0;

    // Score informativo (0..1)
    const double s1 = 1.0 - MathMin(1.0, MathAbs(b_norm) / slope_th);
    const double s2 = 1.0 - MathMin(1.0, r2 / InpR2Threshold);
    const double score = Clamp01(wSlope * s1 + wR2 * s2);
    ScoreBuffer[i] = score;

    // Setas
    if (InpKeepArrows && lateral)
    {
      double offset = (high[i] - low[i]) * 0.25;
      if (offset <= eps)
        offset = MathMax(_Point * 10.0, MathAbs(close[i]) * 0.0001);
      MarkerBuffer[i] = high[i] + offset;
    }
    else
    {
      MarkerBuffer[i] = EMPTY_VALUE;
    }
  }

  // 2) zonas (MAIS RECENTES -> MAIS ANTIGAS)
  DeleteByPrefix("LZ_RECT_");
  DeleteByPrefix("LZ_MID_");
  // (linhas de projeção serão desenhadas depois, com base na zona mais recente)
  // não apagamos aqui para evitar flicker desnecessário; DrawProjectionFromZone apaga com prefixo.

  ZoneInfo lastActive;
  lastActive.valid = false;
  ZoneInfo lastBroken;
  lastBroken.valid = false;

  int zoneCount = 0;

  int i = 0; // mais recente -> mais antigo
  while (i <= last_valid)
  {
    if (FlagBuffer[i] == 1.0)
    {
      int start_recent = i; // mais recente
      int gap = 0;

      while (i <= last_valid)
      {
        if (FlagBuffer[i] == 1.0)
          gap = 0;
        else
          gap++;

        if (gap > InpGapTolerance)
          break;
        i++;
      }

      int end_old = i - gap; // mais antigo
      int length = end_old - start_recent + 1;

      if (length >= InpMinZoneBars)
      {
        double top = -DBL_MAX;
        double bottom = DBL_MAX;
        double sumScore = 0.0;
        int cntScore = 0;

        for (int j = start_recent; j <= end_old; ++j)
        {
          if (high[j] > top)
            top = high[j];
          if (low[j] < bottom)
            bottom = low[j];

          double sc = ScoreBuffer[j];
          if (sc != EMPTY_VALUE)
          {
            sumScore += sc;
            cntScore++;
          }
        }

        ZoneInfo z;
        z.valid = true;
        z.top = top;
        z.bottom = bottom;
        z.mid = (top + bottom) * 0.5;
        z.length = length;
        z.avgScore = (cntScore > 0 ? (sumScore / (double)cntScore) : 0.0);

        // esquerda=mais antigo; direita=mais recente
        z.t_left = time[end_old];
        z.t_right = time[start_recent];

        // estado/rompimento e extensão (para a direita: índices menores)
        z.state = Z_ACTIVE;

        if (InpExtendUntilBreak)
        {
          const double margin = InpBreakMarginPoints * _Point;

          for (int j = start_recent - 1; j >= 0; --j)
          {
            if (close[j] > top + margin)
            {
              z.state = Z_BREAK_UP;
              z.t_right = time[j];
              break;
            }
            if (close[j] < bottom - margin)
            {
              z.state = Z_BREAK_DOWN;
              z.t_right = time[j];
              break;
            }
          }
        }

        // Modo "só última ativa + última rompida" (mais recentes)
        if (InpOnlyLastActiveAndLastBroken)
        {
          if (!lastActive.valid && z.state == Z_ACTIVE)
            lastActive = z;

          if (!lastBroken.valid && z.state != Z_ACTIVE)
            lastBroken = z;

          if (lastActive.valid && lastBroken.valid)
            break;
        }
        else
        {
          DrawZone(zoneCount, z);
          zoneCount++;
          if (zoneCount >= InpMaxZonesOnChart)
            break;
        }

        if (InpDebug)
          PrintFormat("[LZ] len=%d avgScore=%.2f state=%d", z.length, z.avgScore, (int)z.state);
      }
    }
    else
    {
      i++;
    }
  }

  // Render final no modo ativo + PROJEÇÃO DE LINHAS DA ZONA MAIS RECENTE
  if (InpOnlyLastActiveAndLastBroken)
  {
    int idx = 0;
    if (lastActive.valid)
      DrawZone(idx++, lastActive);
    if (lastBroken.valid)
      DrawZone(idx++, lastBroken);

    // zona "mais útil" para projeção: prioriza ativa, senão rompida
    if (lastActive.valid)
      DrawProjectionFromZone(lastActive);
    else if (lastBroken.valid)
      DrawProjectionFromZone(lastBroken);
    else
    {
      // se não há zona, remove linhas antigas
      DeleteByPrefix("LZ_LVL_");
    }
  }
  else
  {
    // Se estiver desenhando várias zonas, usamos a MAIS RECENTE detectada:
    // como o loop é do recente->antigo, a primeira zona desenhada é a mais recente.
    // Para simplificar: aqui removemos linhas (ou você pode implementar armazenando a primeira zona).
    DeleteByPrefix("LZ_LVL_");
  }

  return rates_total;
}
//+------------------------------------------------------------------+
