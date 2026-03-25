//+------------------------------------------------------------------+
//|                          MarketRegime.mq5 (v2.14)           |
//|   MarketRegime (LR Close) + Zones (clusters)                      |
//|   - Breakout color: active=blue, up=green, down=red               |
//|   - Zone midline (mid)                                             |
//|   - Strength: thicker border by average score                      |
//|   - Transparency proportional to duration                          |
//|   - "Active zone" mode: keeps only the last active and last broken |
//|   - Horizontal lines (projection) based on the most recent zone    |
//+------------------------------------------------------------------+
#property copyright "Vagner Ribeiro"
#property link "https://www.mql5.com"
#property version "2.14"
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
input int InpWindow = 240;

// Slope normalization:
// 0 = b/mean(y)
// 1 = b*(n-1)/stdev(y)
enum ENUM_SLOPE_NORM_MODE
{
   SLOPE_NORM_MEAN = 0,
   SLOPE_NORM_STD = 1
};
input ENUM_SLOPE_NORM_MODE InpSlopeNormMode = SLOPE_NORM_MEAN;

// Separate thresholds by mode
input double InpSlopeThresholdMean = 0.0001; // use with SLOPE_NORM_MEAN
input double InpSlopeThresholdStd = 0.20;    // use with SLOPE_NORM_STD

// Trend (R²)
input double InpR2Threshold = 0.05;

// Score (informational)
input double InpScoreSlopeWeight = 0.85; // slope weight in score 0..1

// Zones (clusters)
input int InpMinZoneBars = 15;
input int InpGapTolerance = 1;

// Breakout extension
input bool InpExtendUntilBreak = true;
input double InpBreakMarginPoints = 50;

// Visual
input int InpMaxZonesOnChart = 3;
input bool InpKeepArrows = true;
input bool InpDrawMidLine = false;

// Duration-based transparency (len)
input int InpAlphaMin = 15;       // 0..255 (lower = more transparent)
input int InpAlphaMax = 50;       // 0..255 (higher = more solid)
input int InpAlphaLenScale = 120; // len >= scale tends to use AlphaMax

// Strength (border width by average score)
input int InpBorderMinWidth = 1;
input int InpBorderMaxWidth = 4;

// "Active zone" mode: keep only the last active zone + last broken
input bool InpOnlyLastActiveAndLastBroken = true;

// --- HORIZONTAL LINE PROJECTION (most recent zone) ------------------
input bool InpDrawProjectionLines = true;
input int InpProjectionCount = 10;                // N lines above and N below
input bool InpProjectionIncludeZoneLevels = true; // also draws top/mid/bottom
input int InpProjectionLineWidth = 1;
input int InpProjectionLineAlpha = 10;        // 0..255
input color InpProjectionLineColor = clrGold; // line color

// --- TREND HUD (trend strength) -------------------------------------
input bool InpEnableTrendHUD = true;
input bool InpShowTrendDetails = true;
input bool InpShowBiasAndMicrotrend = true;
input int InpMicrotrendWindow = 30;
input bool InpHUDDraggable = true;
input int InpHUDXDefault = 12;
input int InpHUDYDefault = 12;
input int InpHUDFontSize = 10;
input int InpHUDWidth = 240;
input int InpHUDHeight = 86;
input int InpHUDAlphaMin = 170;
input int InpHUDAlphaMax = 255;
input int InpBarHeight = 10;
input int InpBarMarginX = 10;
input int InpBarMarginBottom = 10;
input double InpTrendThreshold = 0.60;
input double InpTrendWeightSlope = 0.40;
input double InpTrendWeightR2 = 0.40;
input double InpTrendWeightER = 0.20;

// --- TREND EXHAUSTION -----------------------------------------------
input bool InpEnableTrendExhaustion = true;
input int InpExhaustLookback = 20;
input double InpExhaustDistanceScale = 3.0;
input double InpExhaustWeightDistance = 0.45;
input double InpExhaustWeightStrength = 0.30;
input double InpExhaustWeightNoise = 0.25;

// --- BREAK QUALITY ---------------------------------------------------
input bool InpEnableBreakQuality = true;
input double InpBreakQualityWeightStrength = 0.35;
input double InpBreakQualityWeightEnergy = 0.30;
input double InpBreakQualityWeightPenetr = 0.20;
input double InpBreakQualityWeightFresh = 0.15;

// --- ZONE ENERGY (price statistics, no financial indicators) ---------
input bool InpEnableZoneEnergy = true;
input int InpZoneEnergyLenScale = 120;
input int InpZoneEnergyTouchMarginPoints = 30;
input int InpZoneEnergyTouchScale = 12;
input double InpZoneEnergyWeightLen = 0.30;
input double InpZoneEnergyWeightComp = 0.35;
input double InpZoneEnergyWeightChop = 0.20;
input double InpZoneEnergyWeightTouch = 0.15;

// Debug
input bool InpDebug = false;

// Incremental update / redraw

input int InpOnCalculateDelaySeconds = 5; // 0 = no delay

//---------------- BUFFERS -------------------------------------------
double MarkerBuffer[];    // plot (arrows)
double ScoreBuffer[];     // calc
double FlagBuffer[];      // calc (0/1) => used for zones
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

enum ENUM_REGIME_STATE
{
   REGIME_RANGE = 0,
   REGIME_TREND = 1,
   REGIME_MIXED = 2
};

struct ZoneInfo
{
   bool valid;
   datetime t_left;  // oldest (left)
   datetime t_right; // most recent (right; can extend until breakout)
   double top;
   double bottom;
   double mid;
   int length;
   double avgScore;
   double path;
   int touchTop;
   int touchBot;
   ENUM_ZONE_STATE state;
};

//---------------- HELPERS -------------------------------------------
double Clamp01(const double v) { return (v < 0 ? 0 : (v > 1 ? 1 : v)); }
int ClampInt(const int v, const int lo, const int hi) { return (v < lo ? lo : (v > hi ? hi : v)); }
const int HUD_MAX_LINES = 24;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string HUDLineName(const int idx) { return StringFormat("LZ_HUD_LINE_%d", idx); }
bool HUDTextStartsWith(const string txt, const string prefix) { return (StringFind(txt, prefix) == 0); }
bool IsPrimaryHUDLine(const string txt)
{
   return (HUDTextStartsWith(txt, "REGIME:") ||
           HUDTextStartsWith(txt, "BIAS:") ||
           HUDTextStartsWith(txt, "MICROTREND:") ||
           HUDTextStartsWith(txt, "DIR:") ||
           HUDTextStartsWith(txt, "STRENGTH:"));
}
bool IsDetailsHUDLine(const string txt) { return HUDTextStartsWith(txt, "R2:"); }
void AppendHUDLine(string &lines[], const string txt)
{
   const int n = ArraySize(lines);
   ArrayResize(lines, n + 1);
   lines[n] = txt;
}

int g_hud_corner = CORNER_LEFT_UPPER;
int g_hud_x = 12;
int g_hud_y = 12;
bool g_hud_is_dragging = false;
bool g_hud_user_moved = false;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string DirectionToText(const int dir)
{
   if (dir > 0)
      return "UP";
   if (dir < 0)
      return "DOWN";
   return "NEUTRAL";
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int HUDLineCountEstimate()
{
   int lines = 0;
   lines += 1; // title
   lines += 1; // regime
   lines += (InpShowBiasAndMicrotrend ? 2 : 1);
   lines += 1; // strength
   lines += 1; // trend exhaustion
   lines += 1; // break quality
   lines += 1; // step
   lines += 1; // step source
   if (InpEnableZoneEnergy)
      lines += 1;
   if (InpShowTrendDetails)
      lines += 1;
   return lines;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int HUDPanelWidth()
{
   return MathMax(MathMax(0, InpHUDWidth), 250);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int HUDBarHeight()
{
   return MathMax(8, MathMin(MathMax(2, InpBarHeight), 9));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int HUDPanelHeight()
{
   const int PAD_TOP = 10;
   const int LINE_H = 18;
   const int GAP_TEXT_BAR = 10;
   const int PAD_BOTTOM = 12;
   const int BAR_H = HUDBarHeight();
   const int lines = HUDLineCountEstimate();
   const int textBlockH = PAD_TOP + lines * LINE_H;
   const int barBlockH = GAP_TEXT_BAR + BAR_H + PAD_BOTTOM;
   return MathMax(MathMax(0, InpHUDHeight), textBlockH + barBlockH);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int HUDDefaultX(const int panelW)
{
   const int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   if (chartW <= 0)
      return MathMax(0, InpHUDXDefault);
   return MathMax(0, chartW - panelW - MathMax(0, InpHUDXDefault));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int HUDDefaultY()
{
   return MathMax(0, InpHUDYDefault);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ClampHUDPosition(const int panelW, const int panelH)
{
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);

   int maxX = MathMax(0, chartW - panelW - 2);
   int maxY = MathMax(0, chartH - panelH - 2);

   g_hud_x = MathMax(0, MathMin(g_hud_x, maxX));
   g_hud_y = MathMax(0, MathMin(g_hud_y, maxY));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ShiftHUDObjectByDelta(const string name, const int dx, const int dy)
{
   if (ObjectFind(0, name) < 0)
      return;

   const int x = MathMax(0, (int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE) + dx);
   const int y = MathMax(0, (int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE) + dy);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ShiftHUDContentByDelta(const int dx, const int dy)
{
   if (dx == 0 && dy == 0)
      return;

   ShiftHUDObjectByDelta("LZ_HUD_SHADOW", dx, dy);
   ShiftHUDObjectByDelta("LZ_HUD_ACCENT", dx, dy);
   ShiftHUDObjectByDelta("LZ_HUD_BAR_BG", dx, dy);
   ShiftHUDObjectByDelta("LZ_HUD_BAR_FILL", dx, dy);
   for (int i = 0; i < HUD_MAX_LINES; ++i)
      ShiftHUDObjectByDelta(HUDLineName(i), dx, dy);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ApplyHUDPositionToObjects()
{
   if (ObjectFind(0, "LZ_HUD_BG") < 0)
      return;

   const int targetX = MathMax(0, g_hud_x);
   const int targetY = MathMax(0, g_hud_y);
   const int currX = MathMax(0, (int)ObjectGetInteger(0, "LZ_HUD_BG", OBJPROP_XDISTANCE));
   const int currY = MathMax(0, (int)ObjectGetInteger(0, "LZ_HUD_BG", OBJPROP_YDISTANCE));
   const int dx = targetX - currX;
   const int dy = targetY - currY;
   if (dx == 0 && dy == 0)
      return;

   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_XDISTANCE, targetX);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_YDISTANCE, targetY);

   ShiftHUDContentByDelta(dx, dy);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SyncHUDPositionFromObject()
{
   if (ObjectFind(0, "LZ_HUD_BG") < 0)
      return;

   g_hud_corner = CORNER_LEFT_UPPER;
   g_hud_x = MathMax(0, (int)ObjectGetInteger(0, "LZ_HUD_BG", OBJPROP_XDISTANCE));
   g_hud_y = MathMax(0, (int)ObjectGetInteger(0, "LZ_HUD_BG", OBJPROP_YDISTANCE));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int ComputeBorderWidthByScore(const double avgScore)
{
   int wMin = MathMax(InpBorderMinWidth, 1);
   int wMax = MathMax(InpBorderMaxWidth, wMin);

   double s = Clamp01(avgScore);
   int w = (int)MathRound(wMin + (wMax - wMin) * s);
   return ClampInt(w, wMin, wMax);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetSlopeThreshold()
{
   if (InpSlopeNormMode == SLOPE_NORM_MEAN)
      return (InpSlopeThresholdMean > 0.0 ? InpSlopeThresholdMean : 0.0001);
   return (InpSlopeThresholdStd > 0.0 ? InpSlopeThresholdStd : 0.20);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ComputeLRMetricsAtIndex(const int i,
                             const int window,
                             const double &close[],
                             const double eps,
                             double &b_norm,
                             double &r2,
                             double &er)
{
   b_norm = 0.0;
   r2 = 0.0;
   er = 0.0;

   const int total = ArraySize(close);
   if (i < 0 || window < 2 || total <= 0 || (i + window) > total)
      return false;

   const double n = (double)window;
   const double sum_x = n * (n - 1.0) * 0.5;
   const double sum_x2 = n * (n - 1.0) * (2.0 * n - 1.0) / 6.0;
   const double denom = n * sum_x2 - sum_x * sum_x;
   if (MathAbs(denom) <= eps)
      return false;

   double sum_y = 0.0;
   double sum_xy = 0.0;
   double sum_y2 = 0.0;

   for (int k = 0; k < window; ++k)
   {
      const double y = close[i + (window - 1 - k)];
      sum_y += y;
      sum_xy += (double)k * y;
      sum_y2 += y * y;
   }

   const double b = (n * sum_xy - sum_x * sum_y) / denom;
   const double mean_y = sum_y / n;
   const double ss_tot = sum_y2 - (sum_y * sum_y) / n;

   if (InpSlopeNormMode == SLOPE_NORM_MEAN)
   {
      if (MathAbs(mean_y) > eps)
         b_norm = b / mean_y;
   }
   else
   {
      if (ss_tot > eps && (n - 1.0) > 0.0)
      {
         const double sigma = MathSqrt(ss_tot / (n - 1.0));
         if (sigma > eps)
            b_norm = b * (n - 1.0) / sigma;
      }
   }

   if (ss_tot > eps)
   {
      const double a = (sum_y - b * sum_x) / n;
      double ss_res = 0.0;
      for (int k = 0; k < window; ++k)
      {
         const double yhat = a + b * (double)k;
         const double y = close[i + (window - 1 - k)];
         const double e = y - yhat;
         ss_res += e * e;
      }
      r2 = Clamp01(1.0 - (ss_res / ss_tot));
   }

   const double net = MathAbs(close[i] - close[i + window - 1]);
   double path = 0.0;
   for (int k = i; k < i + window - 1; ++k)
      path += MathAbs(close[k] - close[k + 1]);

   if (path > eps)
      er = Clamp01(net / path);

   return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string ZoneRectName(const int idx, const datetime t1, const datetime t2)
{
   return StringFormat("LZ_RECT_%d_%I64d_%I64d", idx, (long)t1, (long)t2);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string ZoneMidName(const int idx, const datetime t1, const datetime t2)
{
   return StringFormat("LZ_MID_%d_%I64d_%I64d", idx, (long)t1, (long)t2);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
color ZoneBaseColor(const ENUM_ZONE_STATE st)
{
   if (st == Z_BREAK_UP)
      return clrLimeGreen;
   if (st == Z_BREAK_DOWN)
      return clrTomato;
   return clrDodgerBlue; // active
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawZone(const int idx, const ZoneInfo &z)
{
   if (!z.valid)
      return;

   uchar alpha = ComputeAlphaByLen(z.length);
   int width = ComputeBorderWidthByScore(z.avgScore);
   color base = ZoneBaseColor(z.state);
   color c = (color)ColorToARGB(base, alpha);

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
         ObjectSetInteger(0, mid, OBJPROP_COLOR, (color)ColorToARGB(clrSilver, (uchar)ClampInt(alpha + 40, 0, 255)));
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawProjectionFromZone(const ZoneInfo &z)
{
   if (!InpDrawProjectionLines || !z.valid)
      return;

   DeleteByPrefix("LZ_LVL_");

   const double step = (z.top - z.bottom);
   if (step <= 0.0)
      return;

   const int cnt = MathMax(1, InpProjectionCount);
   const int w = MathMax(1, InpProjectionLineWidth);
   const uchar a = (uchar)ClampInt(InpProjectionLineAlpha, 0, 255);

   const color cMid = (color)ColorToARGB(InpProjectionLineColor, a);
   const color cUp = (color)ColorToARGB(clrLimeGreen, a);
   const color cDn = (color)ColorToARGB(clrDarkOrange, a);

   int idx = 0;

   if (InpProjectionIncludeZoneLevels)
   {
      DrawHLine(StringFormat("LZ_LVL_%d_TOP", idx++), z.top, cUp, w);
      DrawHLine(StringFormat("LZ_LVL_%d_MID", idx++), z.mid, cMid, w);
      DrawHLine(StringFormat("LZ_LVL_%d_BOT", idx++), z.bottom, cDn, w);
   }

   for (int k = 1; k <= cnt; ++k)
   {
      DrawHLine(StringFormat("LZ_LVL_%d_UP_%d", idx++, k), z.top + step * k, cUp, w);
      DrawHLine(StringFormat("LZ_LVL_%d_DN_%d", idx++, k), z.bottom - step * k, cDn, w);
   }

   if (InpDebug)
      PrintFormat("[LZ] Projection step=%.5f cnt=%d (from zone top=%.5f bot=%.5f)",
                  step, cnt, z.top, z.bottom);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double ComputeEfficiencyRatio(const double &close[], const int window)
{
   if (window < 2)
      return 0.0;

   const double net = MathAbs(close[0] - close[window - 1]);
   double path = 0.0;
   for (int k = 0; k < window - 1; ++k)
      path += MathAbs(close[k] - close[k + 1]);

   if (path <= 0.0)
      return 0.0;

   return Clamp01(net / path);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void NormalizeWeights3(double &w1,
                       double &w2,
                       double &w3)
{
   w1 = MathMax(0.0, w1);
   w2 = MathMax(0.0, w2);
   w3 = MathMax(0.0, w3);

   double wSum = w1 + w2 + w3;
   if (wSum <= 0.0)
   {
      w1 = (1.0 / 3.0);
      w2 = (1.0 / 3.0);
      w3 = (1.0 / 3.0);
      return;
   }

   w1 /= wSum;
   w2 /= wSum;
   w3 /= wSum;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void NormalizeWeights4(double &w1,
                       double &w2,
                       double &w3,
                       double &w4)
{
   w1 = MathMax(0.0, w1);
   w2 = MathMax(0.0, w2);
   w3 = MathMax(0.0, w3);
   w4 = MathMax(0.0, w4);

   double wSum = w1 + w2 + w3 + w4;
   if (wSum <= 0.0)
   {
      w1 = 0.25;
      w2 = 0.25;
      w3 = 0.25;
      w4 = 0.25;
      return;
   }

   w1 /= wSum;
   w2 /= wSum;
   w3 /= wSum;
   w4 /= wSum;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double ComputeTrendStrengthFromMetrics(const double b_norm,
                                       const double r2,
                                       const double er,
                                       const double slope_threshold)
{
   const double slope01 = Clamp01((slope_threshold > 0.0) ? (MathAbs(b_norm) / slope_threshold) : 0.0);

   double wSlope = MathMax(0.0, InpTrendWeightSlope);
   double wR2 = MathMax(0.0, InpTrendWeightR2);
   double wER = MathMax(0.0, InpTrendWeightER);
   NormalizeWeights3(wSlope, wR2, wER);

   return Clamp01(wSlope * slope01 + wR2 * Clamp01(r2) + wER * Clamp01(er));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ComputeZoneEnergyFromZone(const ZoneInfo &z,
                               const double zoneNetClose,
                               const double eps,
                               double &zoneEnergy01,
                               int &zoneEnergyPct)
{
   zoneEnergy01 = 0.0;
   zoneEnergyPct = 0;
   if (!InpEnableZoneEnergy || !z.valid)
      return false;

   double wLen = InpZoneEnergyWeightLen;
   double wComp = InpZoneEnergyWeightComp;
   double wChop = InpZoneEnergyWeightChop;
   double wTouch = InpZoneEnergyWeightTouch;
   NormalizeWeights4(wLen, wComp, wChop, wTouch);

   const int lenScale = MathMax(1, InpZoneEnergyLenScale);
   const int touchScale = MathMax(1, InpZoneEnergyTouchScale);
   const double len01 = Clamp01((double)z.length / (double)lenScale);
   const double range = MathMax(0.0, z.top - z.bottom);
   const double path = MathMax(z.path, eps);
   const double compression01 = Clamp01(1.0 - (range / path));
   const double er_zone = Clamp01(zoneNetClose / path);
   const double chop01 = Clamp01(1.0 - er_zone);
   const int touches = z.touchTop + z.touchBot;
   const double touches01 = Clamp01((double)touches / (double)touchScale);

   zoneEnergy01 = Clamp01(wLen * len01 + wComp * compression01 + wChop * chop01 + wTouch * touches01);
   zoneEnergyPct = ClampInt((int)MathRound(zoneEnergy01 * 100.0), 0, 100);
   return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void EnsureHUDObjectsCreated()
{
   if (ObjectFind(0, "LZ_HUD_SHADOW") < 0)
      ObjectCreate(0, "LZ_HUD_SHADOW", OBJ_RECTANGLE_LABEL, 0, 0, 0);

   bool bgCreated = false;
   if (ObjectFind(0, "LZ_HUD_BG") < 0)
   {
      ObjectCreate(0, "LZ_HUD_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      bgCreated = true;
   }

   if (ObjectFind(0, "LZ_HUD_ACCENT") < 0)
      ObjectCreate(0, "LZ_HUD_ACCENT", OBJ_RECTANGLE_LABEL, 0, 0, 0);

   if (ObjectFind(0, "LZ_HUD_BAR_BG") < 0)
      ObjectCreate(0, "LZ_HUD_BAR_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);

   if (ObjectFind(0, "LZ_HUD_BAR_FILL") < 0)
      ObjectCreate(0, "LZ_HUD_BAR_FILL", OBJ_RECTANGLE_LABEL, 0, 0, 0);

   // Cleanup of legacy old text/bar objects to avoid placeholders.
   ObjectDelete(0, "LZ_HUD_TXT");
   ObjectDelete(0, "LZ_HUD_TITLE");
   ObjectDelete(0, "LZ_HUD_LINE1");
   ObjectDelete(0, "LZ_HUD_LINE2");
   ObjectDelete(0, "LZ_HUD_LINE3");
   ObjectDelete(0, "LZ_HUD_LINE4");
   ObjectDelete(0, "LZ_HUD_LINE5");
   ObjectDelete(0, "LZ_HUD_DETAILS");
   ObjectDelete(0, "LZ_HUD_EBAR_BG");
   ObjectDelete(0, "LZ_HUD_EBAR_FILL");

   if (bgCreated)
   {
      const int panelW = HUDPanelWidth();
      const int panelH = HUDPanelHeight();
      g_hud_corner = CORNER_LEFT_UPPER;
      if (!g_hud_user_moved)
      {
         g_hud_x = HUDDefaultX(panelW);
         g_hud_y = HUDDefaultY();
      }
      ClampHUDPosition(panelW, panelH);
      ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_XDISTANCE, g_hud_x);
      ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_YDISTANCE, g_hud_y);
   }

   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_SELECTABLE, InpHUDDraggable);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteTrendHUD()
{
   ObjectDelete(0, "LZ_HUD_SHADOW");
   ObjectDelete(0, "LZ_HUD_BG");
   ObjectDelete(0, "LZ_HUD_ACCENT");
   ObjectDelete(0, "LZ_HUD_BAR_BG");
   ObjectDelete(0, "LZ_HUD_BAR_FILL");
   for (int i = 0; i < HUD_MAX_LINES; ++i)
      ObjectDelete(0, HUDLineName(i));

   // Defensive cleanup of legacy names.
   ObjectDelete(0, "LZ_HUD_TXT");
   ObjectDelete(0, "LZ_HUD_TITLE");
   ObjectDelete(0, "LZ_HUD_LINE1");
   ObjectDelete(0, "LZ_HUD_LINE2");
   ObjectDelete(0, "LZ_HUD_LINE3");
   ObjectDelete(0, "LZ_HUD_LINE4");
   ObjectDelete(0, "LZ_HUD_LINE5");
   ObjectDelete(0, "LZ_HUD_DETAILS");
   ObjectDelete(0, "LZ_HUD_EBAR_BG");
   ObjectDelete(0, "LZ_HUD_EBAR_FILL");
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RenderTrendHUD(const ENUM_REGIME_STATE regime,
                    const int biasDir,
                    const int microDir,
                    const double strength01,
                    const bool hasTrendExhaustion,
                    const int trendExhaustionPct,
                    const bool hasBreakQuality,
                    const int breakQualityPct,
                    const double hud_step,
                    const string hudStepSource,
                    const double r2,
                    const double er,
                    const double slope01,
                    const bool hasZoneEnergy,
                    const int zoneEnergyPct)
{
   EnsureHUDObjectsCreated();

   if (InpHUDDraggable && !g_hud_is_dragging && g_hud_user_moved)
      SyncHUDPositionFromObject();

   const int corner = CORNER_LEFT_UPPER;
   const int fontSize = MathMax(7, InpHUDFontSize);
   const int titleFontSize = MathMax(6, fontSize - 1);
   const int detailFontSize = MathMax(6, fontSize - 1);
   const int PAD_X = 12;
   const int PAD_TOP = 10;
   const int LINE_H = 18;
   const int PAD_BOTTOM = 12;
   const int GAP_TEXT_BAR = 10;
   const int BAR_H = HUDBarHeight();
   const int SHADOW_OFFSET = 2;
   const int ACCENT_H = 2;

   int aMin = ClampInt(InpHUDAlphaMin, 0, 255);
   int aMax = ClampInt(InpHUDAlphaMax, 0, 255);
   if (aMax < aMin)
   {
      int t = aMin;
      aMin = aMax;
      aMax = t;
   }
   const int alpha = ClampInt((int)MathRound(aMin + (aMax - aMin) * Clamp01(strength01)), 0, 255);

   const string regimeText = (regime == REGIME_RANGE ? "RANGE" : (regime == REGIME_TREND ? "TREND" : "MIXED"));
   const string biasText = DirectionToText(biasDir);
   const string microText = DirectionToText(microDir);
   const int strengthPct = (int)MathRound(Clamp01(strength01) * 100.0);

   color base = clrSilver;
   if (regime != REGIME_MIXED)
   {
      if (biasDir > 0)
         base = clrLimeGreen;
      else if (biasDir < 0)
         base = clrTomato;
   }
   const color titleColor = (color)ColorToARGB(clrSilver, 180);
   const color primaryColor = (color)ColorToARGB(base, (uchar)ClampInt(190 + (alpha / 6), 190, 230));
   const color secondaryColor = (color)ColorToARGB(clrSilver, 210);
   const color mutedColor = (color)ColorToARGB(clrSilver, 165);
   const color panelBgColor = (color)ColorToARGB(clrBlack, 45);
   const color shadowColor = (color)ColorToARGB(clrBlack, 20);
   const color accentColor = (color)ColorToARGB(base, (uchar)ClampInt(95 + (alpha / 5), 95, 145));
   const color barBgColor = (color)ColorToARGB(clrDimGray, 70);
   const color activeColor = (color)ColorToARGB(base, (uchar)ClampInt(185 + (alpha / 5), 185, 235));

   string lines[];
   ArrayResize(lines, 0);
   AppendHUDLine(lines, "MarketRegime Zones v2.14");
   AppendHUDLine(lines, StringFormat("REGIME: %s", regimeText));
   if (InpShowBiasAndMicrotrend)
   {
      AppendHUDLine(lines, StringFormat("BIAS: %s", biasText));
      AppendHUDLine(lines, StringFormat("MICROTREND: %s", microText));
   }
   else
      AppendHUDLine(lines, StringFormat("DIR: %s", biasText));
   AppendHUDLine(lines, StringFormat("STRENGTH: %d", strengthPct));
   if (hasTrendExhaustion)
      AppendHUDLine(lines, StringFormat("TREND EXHAUSTION: %d", ClampInt(trendExhaustionPct, 0, 100)));
   else
      AppendHUDLine(lines, "TREND EXHAUSTION: N/A");
   if (hasBreakQuality)
      AppendHUDLine(lines, StringFormat("BREAK QUALITY: %d", ClampInt(breakQualityPct, 0, 100)));
   else
      AppendHUDLine(lines, "BREAK QUALITY: N/A");
   if (hud_step >= 0.0)
      AppendHUDLine(lines, StringFormat("STEP: %s", DoubleToString(hud_step, MathMax(0, _Digits))));
   else
      AppendHUDLine(lines, "STEP: N/A");
   AppendHUDLine(lines, StringFormat("STEP SRC: %s", hudStepSource));
   if (InpEnableZoneEnergy)
   {
      if (hasZoneEnergy)
         AppendHUDLine(lines, StringFormat("ZONE ENERGY: %d", ClampInt(zoneEnergyPct, 0, 100)));
      else
         AppendHUDLine(lines, "ZONE ENERGY: N/A");
   }
   if (InpShowTrendDetails)
      AppendHUDLine(lines, StringFormat("R2: %.2f  ER: %.2f  S: %.2f", Clamp01(r2), Clamp01(er), Clamp01(slope01)));

   const int linesCount = ArraySize(lines);
   const int panelW = HUDPanelWidth();
   const int textBlockH = PAD_TOP + linesCount * LINE_H;
   const int panelH = MathMax(MathMax(0, InpHUDHeight), textBlockH + GAP_TEXT_BAR + BAR_H + PAD_BOTTOM);
   if (!g_hud_user_moved)
   {
      g_hud_x = HUDDefaultX(panelW);
      g_hud_y = HUDDefaultY();
   }
   ClampHUDPosition(panelW, panelH);

   const int x = MathMax(0, g_hud_x);
   const int y = MathMax(0, g_hud_y);
   const int textX = x + PAD_X;
   const int barW = MathMax(10, panelW - 2 * PAD_X);
   const int barX = x + PAD_X;
   int barY = y + panelH - PAD_BOTTOM - BAR_H;
   const int minBarY = y + PAD_TOP + linesCount * LINE_H + GAP_TEXT_BAR;
   if (barY < minBarY)
      barY = minBarY;

   if (!g_hud_is_dragging)
   {
      ObjectSetInteger(0, "LZ_HUD_SHADOW", OBJPROP_CORNER, corner);
      ObjectSetInteger(0, "LZ_HUD_SHADOW", OBJPROP_XDISTANCE, x + SHADOW_OFFSET);
      ObjectSetInteger(0, "LZ_HUD_SHADOW", OBJPROP_YDISTANCE, y + SHADOW_OFFSET);
      ObjectSetInteger(0, "LZ_HUD_ACCENT", OBJPROP_CORNER, corner);
      ObjectSetInteger(0, "LZ_HUD_ACCENT", OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, "LZ_HUD_ACCENT", OBJPROP_YDISTANCE, y);
   }

   ObjectSetInteger(0, "LZ_HUD_SHADOW", OBJPROP_XSIZE, panelW);
   ObjectSetInteger(0, "LZ_HUD_SHADOW", OBJPROP_YSIZE, panelH);
   ObjectSetInteger(0, "LZ_HUD_SHADOW", OBJPROP_COLOR, (color)clrNONE);
   ObjectSetInteger(0, "LZ_HUD_SHADOW", OBJPROP_BGCOLOR, shadowColor);
   ObjectSetInteger(0, "LZ_HUD_SHADOW", OBJPROP_BACK, false);
   ObjectSetInteger(0, "LZ_HUD_SHADOW", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, "LZ_HUD_SHADOW", OBJPROP_HIDDEN, true);

   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_CORNER, corner);
   if (!g_hud_is_dragging)
   {
      ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_YDISTANCE, y);
   }
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_XSIZE, panelW);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_YSIZE, panelH);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_COLOR, (color)clrNONE);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_BGCOLOR, panelBgColor);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_SELECTABLE, InpHUDDraggable);
   if (!InpHUDDraggable)
      ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_SELECTED, false);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_HIDDEN, true);

   ObjectSetInteger(0, "LZ_HUD_ACCENT", OBJPROP_XSIZE, panelW);
   ObjectSetInteger(0, "LZ_HUD_ACCENT", OBJPROP_YSIZE, ACCENT_H);
   ObjectSetInteger(0, "LZ_HUD_ACCENT", OBJPROP_COLOR, (color)clrNONE);
   ObjectSetInteger(0, "LZ_HUD_ACCENT", OBJPROP_BGCOLOR, accentColor);
   ObjectSetInteger(0, "LZ_HUD_ACCENT", OBJPROP_BACK, false);
   ObjectSetInteger(0, "LZ_HUD_ACCENT", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, "LZ_HUD_ACCENT", OBJPROP_HIDDEN, true);

   for (int i = 0; i < linesCount; ++i)
   {
      const string name = HUDLineName(i);
      if (ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

      color lineColor = secondaryColor;
      int lineFontSize = fontSize;
      if (i == 0)
      {
         lineColor = titleColor;
         lineFontSize = titleFontSize;
      }
      else if (IsDetailsHUDLine(lines[i]))
      {
         lineColor = mutedColor;
         lineFontSize = detailFontSize;
      }
      else if (IsPrimaryHUDLine(lines[i]))
      {
         lineColor = primaryColor;
         if (HUDTextStartsWith(lines[i], "STRENGTH:"))
            lineFontSize = fontSize + 1;
      }

      ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, textX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y + PAD_TOP + i * LINE_H);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, lineFontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
      ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);
   }

   for (int i = linesCount; i < HUD_MAX_LINES; ++i)
   {
      const string name = HUDLineName(i);
      if (ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
   }

   // Defensive cleanup of old names to prevent orphan "Label/label".
   ObjectDelete(0, "LZ_HUD_TXT");
   ObjectDelete(0, "LZ_HUD_TITLE");
   ObjectDelete(0, "LZ_HUD_LINE1");
   ObjectDelete(0, "LZ_HUD_LINE2");
   ObjectDelete(0, "LZ_HUD_LINE3");
   ObjectDelete(0, "LZ_HUD_LINE4");
   ObjectDelete(0, "LZ_HUD_LINE5");
   ObjectDelete(0, "LZ_HUD_DETAILS");
   ObjectDelete(0, "LZ_HUD_EBAR_BG");
   ObjectDelete(0, "LZ_HUD_EBAR_FILL");

   if (!g_hud_is_dragging)
   {
      ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_CORNER, corner);
      ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_XDISTANCE, barX);
      ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_YDISTANCE, barY);
   }
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_XSIZE, barW);
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_YSIZE, BAR_H);
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_COLOR, (color)clrNONE);
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_BGCOLOR, barBgColor);
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_HIDDEN, true);

   int fillW = (int)MathRound((double)barW * Clamp01(strength01));
   if (strength01 > 0.0 && fillW < 1)
      fillW = 1;
   if (fillW < 0)
      fillW = 0;

   color fillColor = activeColor;
   if (strength01 <= 0.0)
      fillColor = (color)ColorToARGB(base, 0);

   if (!g_hud_is_dragging)
   {
      ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_CORNER, corner);
      ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_XDISTANCE, barX);
      ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_YDISTANCE, barY);
   }
   ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_XSIZE, MathMin(fillW, barW));
   ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_YSIZE, BAR_H);
   ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_COLOR, (color)clrNONE);
   ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_BGCOLOR, fillColor);
   ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_BACK, false);
   ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
long HashMix(const long h, const long v)
{
   return (h ^ v) * 1099511628211;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
long PriceToKey(const double price)
{
   if (_Point > 0.0)
      return (long)MathRound(price / _Point);
   return (long)MathRound(price * 100000000.0);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
long BuildZoneHash(const ZoneInfo &z)
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
long HashZone(const ZoneInfo &z)
{
   return BuildZoneHash(z);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
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
   if (InpMicrotrendWindow < 2)
      return INIT_PARAMETERS_INCORRECT;
   if (InpExhaustLookback < 2)
      return INIT_PARAMETERS_INCORRECT;
   if (InpExhaustDistanceScale <= 0.0)
      return INIT_PARAMETERS_INCORRECT;
   if (InpOnCalculateDelaySeconds < 0)
      return INIT_PARAMETERS_INCORRECT;

   const int panelW = HUDPanelWidth();
   const int panelH = HUDPanelHeight();
   g_hud_corner = CORNER_LEFT_UPPER;
   g_hud_x = HUDDefaultX(panelW);
   g_hud_y = HUDDefaultY();
   ClampHUDPosition(panelW, panelH);
   g_hud_is_dragging = false;
   g_hud_user_moved = false;

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

   IndicatorSetString(INDICATOR_SHORTNAME, "MarketRegime Zones (v2.14)");

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

   if (rates_total < InpWindow)
      return rates_total;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   const int window = InpWindow;
   const int last_valid = rates_total - window;
   if (last_valid < 0)
      return rates_total;

   // Clear region without full window
   for (int i = rates_total - 1; i > last_valid; --i)
   {
      MarkerBuffer[i] = EMPTY_VALUE;
      ScoreBuffer[i] = EMPTY_VALUE;
      FlagBuffer[i] = 0.0;
      SlopeNormBuffer[i] = EMPTY_VALUE;
      R2Buffer[i] = EMPTY_VALUE;
   }

   const double slope_th = GetSlopeThreshold();
   const double wSlope = Clamp01(InpScoreSlopeWeight);
   const double wR2 = 1.0 - wSlope;

   // 1) Compute LR + R2 + score + flag
   for (int i = last_valid; i >= 0; --i)
   {
      double b_norm = 0.0;
      double r2 = 0.0;
      double er = 0.0;
      if (!ComputeLRMetricsAtIndex(i, window, close, eps, b_norm, r2, er))
      {
         SlopeNormBuffer[i] = EMPTY_VALUE;
         R2Buffer[i] = EMPTY_VALUE;
         FlagBuffer[i] = 0.0;
         ScoreBuffer[i] = EMPTY_VALUE;
         MarkerBuffer[i] = EMPTY_VALUE;
         continue;
      }

      SlopeNormBuffer[i] = b_norm;
      R2Buffer[i] = r2;

      // Hard ranging rule
      const bool lateral = (MathAbs(b_norm) < slope_th && r2 < InpR2Threshold);
      FlagBuffer[i] = lateral ? 1.0 : 0.0;

      // Informational score (0..1)
      const double s1 = 1.0 - MathMin(1.0, MathAbs(b_norm) / slope_th);
      const double s2 = 1.0 - MathMin(1.0, r2 / InpR2Threshold);
      const double score = Clamp01(wSlope * s1 + wR2 * s2);
      ScoreBuffer[i] = score;

      // Arrows
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

   // 2) Zones (MOST RECENT -> OLDEST)
   DeleteByPrefix("LZ_RECT_");
   DeleteByPrefix("LZ_MID_");
   // (projection lines will be drawn later, based on the most recent zone)
   // we do not clear here to avoid unnecessary flicker; DrawProjectionFromZone clears by prefix.

   ZoneInfo lastActive;
   lastActive.valid = false;
   ZoneInfo lastBroken;
   lastBroken.valid = false;
   double lastActiveNetClose = 0.0;
   double lastBrokenNetClose = 0.0;

   int zoneCount = 0;
   const double touchMargin = MathMax(0, InpZoneEnergyTouchMarginPoints) * _Point;

   int i = 0; // most recent -> oldest
   while (i <= last_valid)
   {
      if (FlagBuffer[i] == 1.0)
      {
         int start_recent = i; // most recent
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

         int end_old = i - gap; // oldest
         int length = end_old - start_recent + 1;

         if (length >= InpMinZoneBars)
         {
            double top = -DBL_MAX;
            double bottom = DBL_MAX;
            double sumScore = 0.0;
            int cntScore = 0;
            double path = 0.0;

            for (int j = start_recent; j <= end_old; ++j)
            {
               if (high[j] > top)
                  top = high[j];
               if (low[j] < bottom)
                  bottom = low[j];

               if (j < end_old)
                  path += MathAbs(close[j] - close[j + 1]);

               double sc = ScoreBuffer[j];
               if (sc != EMPTY_VALUE)
               {
                  sumScore += sc;
                  cntScore++;
               }
            }

            int touchTop = 0;
            int touchBot = 0;
            if (InpEnableZoneEnergy)
            {
               for (int j = start_recent; j <= end_old; ++j)
               {
                  if (high[j] >= top - touchMargin)
                     touchTop++;
                  if (low[j] <= bottom + touchMargin)
                     touchBot++;
               }
            }

            ZoneInfo z;
            z.valid = true;
            z.top = top;
            z.bottom = bottom;
            z.mid = (top + bottom) * 0.5;
            z.length = length;
            z.avgScore = (cntScore > 0 ? (sumScore / (double)cntScore) : 0.0);
            z.path = path;
            z.touchTop = touchTop;
            z.touchBot = touchBot;

            // left=oldest; right=most recent
            z.t_left = time[end_old];
            z.t_right = time[start_recent];

            // state/breakout and extension (to the right: lower indexes)
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

            // "Only last active + last broken" mode (most recent)
            if (InpOnlyLastActiveAndLastBroken)
            {
               if (!lastActive.valid && z.state == Z_ACTIVE)
               {
                  lastActive = z;
                  lastActiveNetClose = MathAbs(close[start_recent] - close[end_old]);
               }

               if (!lastBroken.valid && z.state != Z_ACTIVE)
               {
                  lastBroken = z;
                  lastBrokenNetClose = MathAbs(close[start_recent] - close[end_old]);
               }

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

   // Final render in active mode + PROJECTION LINES FROM THE MOST RECENT ZONE
   if (InpOnlyLastActiveAndLastBroken)
   {
      int idx = 0;
      if (lastActive.valid)
         DrawZone(idx++, lastActive);
      if (lastBroken.valid)
         DrawZone(idx++, lastBroken);

      // Most "useful" zone for projection: prioritize active, otherwise broken
      if (lastActive.valid)
         DrawProjectionFromZone(lastActive);
      else if (lastBroken.valid)
         DrawProjectionFromZone(lastBroken);
      else
      {
         // If there is no zone, remove old lines
         DeleteByPrefix("LZ_LVL_");
      }
   }
   else
   {
      // If drawing multiple zones, we use the MOST RECENT detected:
      // since the loop is recent->old, the first drawn zone is the most recent.
      // For simplicity: here we remove lines (or you can implement storing the first zone).
      DeleteByPrefix("LZ_LVL_");
   }

   // 2.1) Zone Energy (price stats only) - O(1) after identifying lastActive
   bool hasZoneEnergy = false;
   double zone_energy01 = 0.0;
   int zone_energy_pct = 0;
   if (lastActive.valid)
      hasZoneEnergy = ComputeZoneEnergyFromZone(lastActive, lastActiveNetClose, eps, zone_energy01, zone_energy_pct);

   bool hasBrokenZoneEnergy = false;
   double broken_zone_energy01 = 0.0;
   int broken_zone_energy_pct = 0;
   if (lastBroken.valid)
      hasBrokenZoneEnergy = ComputeZoneEnergyFromZone(lastBroken, lastBrokenNetClose, eps, broken_zone_energy01, broken_zone_energy_pct);

   // 3) TrendStrength + HUD
   ObjectDelete(0, "LZ_TREND_BG"); // legacy: remove old background if it exists

   double b_norm0 = SlopeNormBuffer[0];
   double r2_0 = Clamp01(R2Buffer[0]);
   double er_0 = 0.0;
   double metrics_b_norm0 = 0.0;
   double metrics_r2_0 = 0.0;
   if (ComputeLRMetricsAtIndex(0, window, close, eps, metrics_b_norm0, metrics_r2_0, er_0))
   {
      b_norm0 = metrics_b_norm0;
      r2_0 = Clamp01(metrics_r2_0);
   }
   const double slope01_0 = Clamp01((slope_th > 0.0) ? (MathAbs(b_norm0) / slope_th) : 0.0);
   const double trend_strength = ComputeTrendStrengthFromMetrics(b_norm0, r2_0, er_0, slope_th);

   int trend_dir = 0;
   if (b_norm0 > eps)
      trend_dir = 1;
   else if (b_norm0 < -eps)
      trend_dir = -1;

   double micro_b_norm = 0.0;
   double micro_r2 = 0.0;
   double micro_er = 0.0;
   int micro_dir = 0;
   const int micro_window = MathMax(2, InpMicrotrendWindow);
   if (ComputeLRMetricsAtIndex(0, micro_window, close, eps, micro_b_norm, micro_r2, micro_er))
   {
      if (micro_b_norm > eps)
         micro_dir = 1;
      else if (micro_b_norm < -eps)
         micro_dir = -1;
   }

   ENUM_REGIME_STATE regime = REGIME_MIXED;
   if (FlagBuffer[0] == 1.0 || lastActive.valid)
      regime = REGIME_RANGE;
   else if (trend_strength >= Clamp01(InpTrendThreshold))
      regime = REGIME_TREND;

   double hud_step = -1.0;
   double hud_mid = 0.0;
   string hud_step_source = "N/A";
   if (lastActive.valid)
   {
      hud_step = lastActive.top - lastActive.bottom;
      hud_mid = lastActive.mid;
      hud_step_source = "ACTIVE";
   }
   else if (lastBroken.valid)
   {
      hud_step = lastBroken.top - lastBroken.bottom;
      hud_mid = lastBroken.mid;
      hud_step_source = "LAST BROKEN";
   }

   double short_b_norm = 0.0;
   double short_r2 = 0.0;
   double short_er = 0.0;
   double trend_strength_short = 0.0;
   bool hasShortMetrics = false;
   const int exhaust_window = MathMax(2, InpExhaustLookback);
   if (ComputeLRMetricsAtIndex(0, exhaust_window, close, eps, short_b_norm, short_r2, short_er))
   {
      trend_strength_short = ComputeTrendStrengthFromMetrics(short_b_norm, short_r2, short_er, slope_th);
      hasShortMetrics = true;
   }

   bool canComputeTrendExhaustion = false;
   double trend_exhaustion01 = 0.0;
   int trend_exhaustion_pct = 0;
   if (hud_step > eps && hasShortMetrics)
   {
      const double distanceSteps = MathAbs(close[0] - hud_mid) / MathMax(hud_step, eps);
      const double distance01 = Clamp01(distanceSteps / MathMax(InpExhaustDistanceScale, eps));
      const double strengthDrop01 = Clamp01(MathMax(0.0, trend_strength - trend_strength_short));
      const double noise01 = Clamp01(1.0 - short_er);

      double wDist = InpExhaustWeightDistance;
      double wStrength = InpExhaustWeightStrength;
      double wNoise = InpExhaustWeightNoise;
      NormalizeWeights3(wDist, wStrength, wNoise);

      trend_exhaustion01 = Clamp01(wDist * distance01 + wStrength * strengthDrop01 + wNoise * noise01);
      trend_exhaustion_pct = ClampInt((int)MathRound(trend_exhaustion01 * 100.0), 0, 100);
      canComputeTrendExhaustion = true;
   }

   bool canComputeBreakQuality = false;
   int break_quality_pct = 0;
   if (lastBroken.valid)
   {
      const double brokenStep = MathMax(lastBroken.top - lastBroken.bottom, 0.0);
      int break_dir = 0;
      if (lastBroken.state == Z_BREAK_UP)
         break_dir = 1;
      else if (lastBroken.state == Z_BREAK_DOWN)
         break_dir = -1;

      if (brokenStep > eps && break_dir != 0)
      {
         const double breakStrength01 = Clamp01(trend_strength);
         const double breakEnergy01 = (hasBrokenZoneEnergy ? broken_zone_energy01 : 0.0);
         double penetration = 0.0;
         if (break_dir > 0)
            penetration = close[0] - lastBroken.top;
         else
            penetration = lastBroken.bottom - close[0];
         const double penetration01 = Clamp01(penetration / MathMax(brokenStep, eps));
         const double freshness01 = (canComputeTrendExhaustion ? Clamp01(1.0 - trend_exhaustion01) : 1.0);

         double wStrength = InpBreakQualityWeightStrength;
         double wEnergy = InpBreakQualityWeightEnergy;
         double wPenetr = InpBreakQualityWeightPenetr;
         double wFresh = InpBreakQualityWeightFresh;
         NormalizeWeights4(wStrength, wEnergy, wPenetr, wFresh);

         const double break_quality01 = Clamp01(wStrength * breakStrength01 +
                                                wEnergy * breakEnergy01 +
                                                wPenetr * penetration01 +
                                                wFresh * freshness01);
         break_quality_pct = ClampInt((int)MathRound(break_quality01 * 100.0), 0, 100);
         canComputeBreakQuality = true;
      }
   }

   if (InpEnableTrendHUD)
      RenderTrendHUD(regime, trend_dir, micro_dir, trend_strength,
                     (InpEnableTrendExhaustion && canComputeTrendExhaustion), trend_exhaustion_pct,
                     (InpEnableBreakQuality && canComputeBreakQuality), break_quality_pct,
                     hud_step, hud_step_source, r2_0, er_0, slope01_0,
                     hasZoneEnergy, zone_energy_pct);
   else
      DeleteTrendHUD();

   return rates_total;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteTrendHUD();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if (!InpEnableTrendHUD)
      return;

   const int panelW = HUDPanelWidth();
   const int panelH = HUDPanelHeight();

   if (id == CHARTEVENT_CHART_CHANGE)
   {
      if (g_hud_user_moved)
         SyncHUDPositionFromObject();
      else
      {
         g_hud_x = HUDDefaultX(panelW);
         g_hud_y = HUDDefaultY();
      }

      g_hud_is_dragging = false;
      ClampHUDPosition(panelW, panelH);
      ApplyHUDPositionToObjects();
      ChartRedraw(0);
      return;
   }

   if (!InpHUDDraggable)
   {
      g_hud_is_dragging = false;
      return;
   }

   if (sparam != "LZ_HUD_BG")
      return;

   if (id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CHANGE)
   {
      const int prevX = g_hud_x;
      const int prevY = g_hud_y;
      g_hud_is_dragging = (id == CHARTEVENT_OBJECT_DRAG);
      SyncHUDPositionFromObject();
      const int draggedX = g_hud_x;
      const int draggedY = g_hud_y;
      g_hud_user_moved = true;
      ClampHUDPosition(panelW, panelH);
      ShiftHUDContentByDelta(draggedX - prevX, draggedY - prevY);
      ApplyHUDPositionToObjects();
      if (id == CHARTEVENT_OBJECT_CHANGE)
         g_hud_is_dragging = false;
      ChartRedraw(0);
   }
}
//+------------------------------------------------------------------+
