//+------------------------------------------------------------------+
//|                          MarketRegime.mq5 (v2.13)           |
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
#property version "2.13"
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
input int InpProjectionLineAlpha = 10;       // 0..255
input color InpProjectionLineColor = clrGold; // line color

// --- TREND HUD (trend strength) -------------------------------------
input bool InpEnableTrendHUD = true;
input bool InpShowTrendDetails = false;
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
   bool              valid;
   datetime          t_left;  // oldest (left)
   datetime          t_right; // most recent (right; can extend until breakout)
   double            top;
   double            bottom;
   double            mid;
   int               length;
   double            avgScore;
   double            path;
   int               touchTop;
   int               touchBot;
   ENUM_ZONE_STATE   state;
  };

//---------------- HELPERS -------------------------------------------
double Clamp01(const double v) { return (v < 0 ? 0 : (v > 1 ? 1 : v)); }
int ClampInt(const int v, const int lo, const int hi) { return (v < lo ? lo : (v > hi ? hi : v)); }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string HUDLineName(const int idx) { return StringFormat("LZ_HUD_LINE_%d", idx); }
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
int HUDPanelWidth()
  {
   return MathMax(MathMax(0, InpHUDWidth), 220);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int HUDPanelHeight()
  {
   const int PAD_TOP = 8;
   const int LINE_H = 16;
   const int GAP_TEXT_BAR = 8;
   const int PAD_BOTTOM = 10;
   const int BAR_H = MathMax(2, InpBarHeight);
   const int lines = 5 + (InpEnableZoneEnergy ? 1 : 0) + (InpShowTrendDetails ? 1 : 0); // estimate (title+REGIME+DIR+STRENGTH+STEP+optional energy+optional details)
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
   if(chartW <= 0)
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
   if(ObjectFind(0, name) < 0)
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
   if(dx == 0 && dy == 0)
      return;

   ShiftHUDObjectByDelta("LZ_HUD_BAR_BG", dx, dy);
   ShiftHUDObjectByDelta("LZ_HUD_BAR_FILL", dx, dy);
   for(int i = 0; i < 20; ++i)
      ShiftHUDObjectByDelta(HUDLineName(i), dx, dy);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ApplyHUDPositionToObjects()
  {
   if(ObjectFind(0, "LZ_HUD_BG") < 0)
      return;

   const int targetX = MathMax(0, g_hud_x);
   const int targetY = MathMax(0, g_hud_y);
   const int currX = MathMax(0, (int)ObjectGetInteger(0, "LZ_HUD_BG", OBJPROP_XDISTANCE));
   const int currY = MathMax(0, (int)ObjectGetInteger(0, "LZ_HUD_BG", OBJPROP_YDISTANCE));
   const int dx = targetX - currX;
   const int dy = targetY - currY;
   if(dx == 0 && dy == 0)
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
   if(ObjectFind(0, "LZ_HUD_BG") < 0)
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
   if(aMax < aMin)
     {
      int t = aMin;
      aMin = aMax;
      aMax = t;
     }

   int scale = MathMax(InpAlphaLenScale, 1);
   double t = (double)len / (double)scale;
   if(t > 1.0)
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
   if(InpSlopeNormMode == SLOPE_NORM_MEAN)
      return (InpSlopeThresholdMean > 0.0 ? InpSlopeThresholdMean : 0.0001);
   return (InpSlopeThresholdStd > 0.0 ? InpSlopeThresholdStd : 0.20);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteByPrefix(const string prefix)
  {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; --i)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
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
   if(st == Z_BREAK_UP)
      return clrLimeGreen;
   if(st == Z_BREAK_DOWN)
      return clrTomato;
   return clrDodgerBlue; // active
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawZone(const int idx, const ZoneInfo &z)
  {
   if(!z.valid)
      return;

   uchar alpha = ComputeAlphaByLen(z.length);
   int width = ComputeBorderWidthByScore(z.avgScore);
   color base = ZoneBaseColor(z.state);
   color c = ColorToARGB(base, alpha);

   string rect = ZoneRectName(idx, z.t_left, z.t_right);

   if(ObjectCreate(0, rect, OBJ_RECTANGLE, 0, z.t_left, z.top, z.t_right, z.bottom))
     {
      ObjectSetInteger(0, rect, OBJPROP_COLOR, c);
      ObjectSetInteger(0, rect, OBJPROP_BACK, true);
      ObjectSetInteger(0, rect, OBJPROP_FILL, true);
      ObjectSetInteger(0, rect, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, rect, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, rect, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rect, OBJPROP_HIDDEN, true);
     }

   if(InpDrawMidLine)
     {
      string mid = ZoneMidName(idx, z.t_left, z.t_right);
      if(ObjectCreate(0, mid, OBJ_TREND, 0, z.t_left, z.mid, z.t_right, z.mid))
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
   if(ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
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
   if(!InpDrawProjectionLines || !z.valid)
      return;

   DeleteByPrefix("LZ_LVL_");

   const double step = (z.top - z.bottom);
   if(step <= 0.0)
      return;

   const int cnt = MathMax(1, InpProjectionCount);
   const int w = MathMax(1, InpProjectionLineWidth);
   const uchar a = (uchar)ClampInt(InpProjectionLineAlpha, 0, 255);

   const color cMid = ColorToARGB(InpProjectionLineColor, a);
   const color cUp = ColorToARGB(clrLimeGreen, a);
   const color cDn = ColorToARGB(clrDarkOrange, a);

   int idx = 0;

   if(InpProjectionIncludeZoneLevels)
     {
      DrawHLine(StringFormat("LZ_LVL_%d_TOP", idx++), z.top, cUp, w);
      DrawHLine(StringFormat("LZ_LVL_%d_MID", idx++), z.mid, cMid, w);
      DrawHLine(StringFormat("LZ_LVL_%d_BOT", idx++), z.bottom, cDn, w);
     }

   for(int k = 1; k <= cnt; ++k)
     {
      DrawHLine(StringFormat("LZ_LVL_%d_UP_%d", idx++, k), z.top + step * k, cUp, w);
      DrawHLine(StringFormat("LZ_LVL_%d_DN_%d", idx++, k), z.bottom - step * k, cDn, w);
     }

   if(InpDebug)
      PrintFormat("[LZ] Projection step=%.5f cnt=%d (from zone top=%.5f bot=%.5f)",
                  step, cnt, z.top, z.bottom);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double ComputeEfficiencyRatio(const double &close[], const int window)
  {
   if(window < 2)
      return 0.0;

   const double net = MathAbs(close[0] - close[window - 1]);
   double path = 0.0;
   for(int k = 0; k < window - 1; ++k)
      path += MathAbs(close[k] - close[k + 1]);

   if(path <= 0.0)
      return 0.0;

   return Clamp01(net / path);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double ComputeTrendStrength(const double b_norm,
                            const double slope_threshold,
                            const double r2,
                            const double er)
  {
   const double slope01 = Clamp01((slope_threshold > 0.0) ? (MathAbs(b_norm) / slope_threshold) : 0.0);

   double wSlope = MathMax(0.0, InpTrendWeightSlope);
   double wR2 = MathMax(0.0, InpTrendWeightR2);
   double wER = MathMax(0.0, InpTrendWeightER);
   double wSum = wSlope + wR2 + wER;

   if(wSum <= 0.0)
     {
      wSlope = 1.0;
      wR2 = 1.0;
      wER = 1.0;
      wSum = 3.0;
     }

   const double nSlope = wSlope / wSum;
   const double nR2 = wR2 / wSum;
   const double nER = wER / wSum;

   return Clamp01(nSlope * slope01 + nR2 * Clamp01(r2) + nER * Clamp01(er));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void EnsureHUDObjectsCreated()
  {
   bool bgCreated = false;
   if(ObjectFind(0, "LZ_HUD_BG") < 0)
     {
      ObjectCreate(0, "LZ_HUD_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      bgCreated = true;
     }

   if(ObjectFind(0, "LZ_HUD_BAR_BG") < 0)
      ObjectCreate(0, "LZ_HUD_BAR_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);

   if(ObjectFind(0, "LZ_HUD_BAR_FILL") < 0)
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

   if(bgCreated)
     {
      const int panelW = HUDPanelWidth();
      const int panelH = HUDPanelHeight();
      g_hud_corner = CORNER_LEFT_UPPER;
      if(!g_hud_user_moved)
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
   ObjectDelete(0, "LZ_HUD_BG");
   ObjectDelete(0, "LZ_HUD_BAR_BG");
   ObjectDelete(0, "LZ_HUD_BAR_FILL");
   for(int i = 0; i < 20; ++i)
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
                    const int dir,
                    const double strength01,
                    const double hud_step,
                    const double r2,
                    const double er,
                    const double slope01,
                    const bool hasZoneEnergy,
                    const int zoneEnergyPct)
  {
   EnsureHUDObjectsCreated();

   if(InpHUDDraggable && !g_hud_is_dragging && g_hud_user_moved)
      SyncHUDPositionFromObject();

   const int corner = CORNER_LEFT_UPPER;
   const int fontSize = MathMax(6, InpHUDFontSize);
   const int PAD_X = 10;
   const int PAD_TOP = 8;
   const int LINE_H = 16;
   const int PAD_BOTTOM = 10;
   const int GAP_TEXT_BAR = 8;
   const int BAR_H = MathMax(2, InpBarHeight);

   int aMin = ClampInt(InpHUDAlphaMin, 0, 255);
   int aMax = ClampInt(InpHUDAlphaMax, 0, 255);
   if(aMax < aMin)
     {
      int t = aMin;
      aMin = aMax;
      aMax = t;
     }
   const int alpha = ClampInt((int)MathRound(aMin + (aMax - aMin) * Clamp01(strength01)), 0, 255);

   const string regimeText = (regime == REGIME_RANGE ? "RANGE" : (regime == REGIME_TREND ? "TREND" : "MIXED"));
   const string dirText = (dir > 0 ? "UP" : (dir < 0 ? "DOWN" : "NEUTRAL"));
   const int strengthPct = (int)MathRound(Clamp01(strength01) * 100.0);

   color base = clrSilver;
   if(regime != REGIME_MIXED)
     {
      if(dir > 0)
         base = clrLimeGreen;
      else
         if(dir < 0)
            base = clrTomato;
     }
   const color activeColor = ColorToARGB(base, (uchar)alpha);

   string lines[];
   ArrayResize(lines, 0);
   AppendHUDLine(lines, "MarketRegime Zones v2.13");
   AppendHUDLine(lines, StringFormat("REGIME: %s", regimeText));
   AppendHUDLine(lines, StringFormat("DIR: %s", dirText));
   AppendHUDLine(lines, StringFormat("STRENGTH: %d", strengthPct));
   if(hud_step >= 0.0)
      AppendHUDLine(lines, StringFormat("STEP: %s", DoubleToString(hud_step, MathMax(0, _Digits))));
   else
      AppendHUDLine(lines, "STEP: N/A");
   if(hasZoneEnergy)
      AppendHUDLine(lines, StringFormat("ZONE ENERGY: %d", ClampInt(zoneEnergyPct, 0, 100)));
   if(InpShowTrendDetails)
      AppendHUDLine(lines, StringFormat("R2: %.2f  ER: %.2f  S: %.2f", Clamp01(r2), Clamp01(er), Clamp01(slope01)));

   const int linesCount = ArraySize(lines);
   const int panelW = HUDPanelWidth();
   const int textBlockH = PAD_TOP + linesCount * LINE_H;
   const int panelH = MathMax(MathMax(0, InpHUDHeight), textBlockH + GAP_TEXT_BAR + BAR_H + PAD_BOTTOM);
   if(!g_hud_user_moved)
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
   if(barY < minBarY)
      barY = minBarY;

   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_CORNER, corner);
   if(!g_hud_is_dragging)
     {
      ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_YDISTANCE, y);
     }
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_XSIZE, panelW);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_YSIZE, panelH);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_COLOR, activeColor);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_BGCOLOR, ColorToARGB(clrBlack, 60));
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_SELECTABLE, InpHUDDraggable);
   if(!InpHUDDraggable)
      ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_SELECTED, false);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_HIDDEN, true);

   for(int i = 0; i < linesCount; ++i)
     {
      const string name = HUDLineName(i);
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, textX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y + PAD_TOP + i * LINE_H);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, activeColor);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);
     }

   for(int i = linesCount; i < 20; ++i)
     {
      const string name = HUDLineName(i);
      if(ObjectFind(0, name) >= 0)
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

   if(!g_hud_is_dragging)
     {
      ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_CORNER, corner);
      ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_XDISTANCE, barX);
      ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_YDISTANCE, barY);
     }
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_XSIZE, barW);
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_YSIZE, BAR_H);
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_COLOR, ColorToARGB(clrDimGray, 90));
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_BGCOLOR, ColorToARGB(clrDimGray, 90));
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, "LZ_HUD_BAR_BG", OBJPROP_HIDDEN, true);

   int fillW = (int)MathRound((double)barW * Clamp01(strength01));
   if(strength01 > 0.0 && fillW < 1)
      fillW = 1;
   if(fillW < 0)
      fillW = 0;

   color fillColor = activeColor;
   if(strength01 <= 0.0)
      fillColor = ColorToARGB(base, 0);

   if(!g_hud_is_dragging)
     {
      ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_CORNER, corner);
      ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_XDISTANCE, barX);
      ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_YDISTANCE, barY);
     }
   ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_XSIZE, MathMin(fillW, barW));
   ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_YSIZE, BAR_H);
   ObjectSetInteger(0, "LZ_HUD_BAR_FILL", OBJPROP_COLOR, fillColor);
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
   if(_Point > 0.0)
      return (long)MathRound(price / _Point);
   return (long)MathRound(price * 100000000.0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
long HashZone(const ZoneInfo &z)
  {
   long h = 1469598103934665603;
   if(!z.valid)
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

   if(InpWindow < 2)
      return INIT_PARAMETERS_INCORRECT;
   if(InpR2Threshold <= 0.0)
      return INIT_PARAMETERS_INCORRECT;
   if(InpMinZoneBars < 2)
      return INIT_PARAMETERS_INCORRECT;
   if(InpGapTolerance < 0)
      return INIT_PARAMETERS_INCORRECT;
   if(InpOnCalculateDelaySeconds < 0)
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

   IndicatorSetString(INDICATOR_SHORTNAME, "MarketRegime Zones (v2.13)");

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
   if(delay_seconds > 0)
     {
      const ulong now_ms = GetTickCount64();
      const ulong delay_ms = (ulong)delay_seconds * 1000ULL;
      if(last_exec_ms != 0 && (now_ms - last_exec_ms) < delay_ms)
         return prev_calculated;
      last_exec_ms = now_ms;
     }

   if(rates_total < InpWindow)
      return rates_total;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   const int window = InpWindow;
   const double n = (double)window;
   const int last_valid = rates_total - window;
   if(last_valid < 0)
      return rates_total;

// Clear region without full window
   for(int i = rates_total - 1; i > last_valid; --i)
     {
      MarkerBuffer[i] = EMPTY_VALUE;
      ScoreBuffer[i] = EMPTY_VALUE;
      FlagBuffer[i] = 0.0;
      SlopeNormBuffer[i] = EMPTY_VALUE;
      R2Buffer[i] = EMPTY_VALUE;
     }

// Pre-sums of x=0..n-1
   const double sum_x = n * (n - 1.0) * 0.5;
   const double sum_x2 = n * (n - 1.0) * (2.0 * n - 1.0) / 6.0;
   const double denom = n * sum_x2 - sum_x * sum_x;
   if(MathAbs(denom) <= eps)
      return prev_calculated;

   const double slope_th = GetSlopeThreshold();
   const double wSlope = Clamp01(InpScoreSlopeWeight);
   const double wR2 = 1.0 - wSlope;

// 1) Compute LR + R2 + score + flag
   for(int i = last_valid; i >= 0; --i)
     {
      double sum_y = 0.0;
      double sum_xy = 0.0;
      double sum_y2 = 0.0;

      for(int k = 0; k < window; ++k)
        {
         const double y = close[i + (window - 1 - k)];
         sum_y += y;
         sum_xy += (double)k * y;
         sum_y2 += y * y;
        }

      const double b = (n * sum_xy - sum_x * sum_y) / denom;
      const double mean_y = sum_y / n;
      const double ss_tot = sum_y2 - (sum_y * sum_y) / n;

      // slope norm
      double b_norm = 0.0;
      if(InpSlopeNormMode == SLOPE_NORM_MEAN)
        {
         if(MathAbs(mean_y) > eps)
            b_norm = b / mean_y;
        }
      else // STD
        {
         if(ss_tot > eps && (n - 1.0) > 0.0)
           {
            const double sigma = MathSqrt(ss_tot / (n - 1.0));
            if(sigma > eps)
               b_norm = b * (n - 1.0) / sigma;
           }
        }

      // R²
      double r2 = 0.0;
      if(ss_tot > eps)
        {
         const double a = (sum_y - b * sum_x) / n;
         double ss_res = 0.0;
         for(int k = 0; k < window; ++k)
           {
            const double yhat = a + b * (double)k;
            const double y = close[i + (window - 1 - k)];
            const double e = y - yhat;
            ss_res += e * e;
           }
         r2 = Clamp01(1.0 - (ss_res / ss_tot));
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
      if(InpKeepArrows && lateral)
        {
         double offset = (high[i] - low[i]) * 0.25;
         if(offset <= eps)
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

   int zoneCount = 0;
   const double touchMargin = MathMax(0, InpZoneEnergyTouchMarginPoints) * _Point;

   int i = 0; // most recent -> oldest
   while(i <= last_valid)
     {
      if(FlagBuffer[i] == 1.0)
        {
         int start_recent = i; // most recent
         int gap = 0;

         while(i <= last_valid)
           {
            if(FlagBuffer[i] == 1.0)
               gap = 0;
            else
               gap++;

            if(gap > InpGapTolerance)
               break;
            i++;
           }

         int end_old = i - gap; // oldest
         int length = end_old - start_recent + 1;

         if(length >= InpMinZoneBars)
           {
            double top = -DBL_MAX;
            double bottom = DBL_MAX;
            double sumScore = 0.0;
            int cntScore = 0;
            double path = 0.0;

            for(int j = start_recent; j <= end_old; ++j)
              {
               if(high[j] > top)
                  top = high[j];
               if(low[j] < bottom)
                  bottom = low[j];

               if(j < end_old)
                  path += MathAbs(close[j] - close[j + 1]);

               double sc = ScoreBuffer[j];
               if(sc != EMPTY_VALUE)
                 {
                  sumScore += sc;
                  cntScore++;
                 }
              }

            int touchTop = 0;
            int touchBot = 0;
            if(InpEnableZoneEnergy)
              {
               for(int j = start_recent; j <= end_old; ++j)
                 {
                  if(high[j] >= top - touchMargin)
                     touchTop++;
                  if(low[j] <= bottom + touchMargin)
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

            if(InpExtendUntilBreak)
              {
               const double margin = InpBreakMarginPoints * _Point;

               for(int j = start_recent - 1; j >= 0; --j)
                 {
                  if(close[j] > top + margin)
                    {
                     z.state = Z_BREAK_UP;
                     z.t_right = time[j];
                     break;
                    }
                  if(close[j] < bottom - margin)
                    {
                     z.state = Z_BREAK_DOWN;
                     z.t_right = time[j];
                     break;
                    }
                 }
              }

            // "Only last active + last broken" mode (most recent)
            if(InpOnlyLastActiveAndLastBroken)
              {
               if(!lastActive.valid && z.state == Z_ACTIVE)
                 {
                  lastActive = z;
                  lastActiveNetClose = MathAbs(close[start_recent] - close[end_old]);
                 }

               if(!lastBroken.valid && z.state != Z_ACTIVE)
                  lastBroken = z;

               if(lastActive.valid && lastBroken.valid)
                  break;
              }
            else
              {
               DrawZone(zoneCount, z);
               zoneCount++;
               if(zoneCount >= InpMaxZonesOnChart)
                  break;
              }

            if(InpDebug)
               PrintFormat("[LZ] len=%d avgScore=%.2f state=%d", z.length, z.avgScore, (int)z.state);
           }
        }
      else
        {
         i++;
        }
     }

// Final render in active mode + PROJECTION LINES FROM THE MOST RECENT ZONE
   if(InpOnlyLastActiveAndLastBroken)
     {
      int idx = 0;
      if(lastActive.valid)
         DrawZone(idx++, lastActive);
      if(lastBroken.valid)
         DrawZone(idx++, lastBroken);

      // Most "useful" zone for projection: prioritize active, otherwise broken
      if(lastActive.valid)
         DrawProjectionFromZone(lastActive);
      else
         if(lastBroken.valid)
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
   if(InpEnableZoneEnergy && lastActive.valid)
     {
      double wLen = MathMax(0.0, InpZoneEnergyWeightLen);
      double wComp = MathMax(0.0, InpZoneEnergyWeightComp);
      double wChop = MathMax(0.0, InpZoneEnergyWeightChop);
      double wTouch = MathMax(0.0, InpZoneEnergyWeightTouch);
      double wSum = wLen + wComp + wChop + wTouch;
      if(wSum <= eps)
        {
         wLen = 1.0;
         wComp = 1.0;
         wChop = 1.0;
         wTouch = 1.0;
         wSum = 4.0;
        }

      const double nLen = wLen / wSum;
      const double nComp = wComp / wSum;
      const double nChop = wChop / wSum;
      const double nTouch = wTouch / wSum;

      const int lenScale = MathMax(1, InpZoneEnergyLenScale);
      const int touchScale = MathMax(1, InpZoneEnergyTouchScale);
      const double len01 = Clamp01((double)lastActive.length / (double)lenScale);
      const double range = MathMax(0.0, lastActive.top - lastActive.bottom);
      const double path = MathMax(lastActive.path, eps);
      const double compression01 = Clamp01(1.0 - (range / path));
      const double er_zone = Clamp01(lastActiveNetClose / path);
      const double chop01 = Clamp01(1.0 - er_zone);
      const int touches = lastActive.touchTop + lastActive.touchBot;
      const double touches01 = Clamp01((double)touches / (double)touchScale);

      zone_energy01 = Clamp01(nLen * len01 + nComp * compression01 + nChop * chop01 + nTouch * touches01);
      zone_energy_pct = ClampInt((int)MathRound(zone_energy01 * 100.0), 0, 100);
      hasZoneEnergy = true;
     }

// 3) TrendStrength + HUD
   ObjectDelete(0, "LZ_TREND_BG"); // legacy: remove old background if it exists

   const double b_norm0 = SlopeNormBuffer[0];
   const double r2_0 = Clamp01(R2Buffer[0]);
   const double er_0 = ComputeEfficiencyRatio(close, window);
   const double slope01_0 = Clamp01((slope_th > 0.0) ? (MathAbs(b_norm0) / slope_th) : 0.0);
   const double trend_strength = ComputeTrendStrength(b_norm0, slope_th, r2_0, er_0);

   int trend_dir = 0;
   if(b_norm0 > eps)
      trend_dir = 1;
   else
      if(b_norm0 < -eps)
         trend_dir = -1;

   ENUM_REGIME_STATE regime = REGIME_MIXED;
   if(FlagBuffer[0] == 1.0 || lastActive.valid)
      regime = REGIME_RANGE;
   else
      if(trend_strength >= Clamp01(InpTrendThreshold))
         regime = REGIME_TREND;

   double hud_step = -1.0;
   if(lastActive.valid)
      hud_step = lastActive.top - lastActive.bottom;
   else
      if(lastBroken.valid)
         hud_step = lastBroken.top - lastBroken.bottom;

   if(InpEnableTrendHUD)
      RenderTrendHUD(regime, trend_dir, trend_strength, hud_step, r2_0, er_0, slope01_0,
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
   if(!InpEnableTrendHUD)
      return;

   const int panelW = HUDPanelWidth();
   const int panelH = HUDPanelHeight();

   if(id == CHARTEVENT_CHART_CHANGE)
     {
      if(g_hud_user_moved)
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

   if(!InpHUDDraggable)
     {
      g_hud_is_dragging = false;
      return;
     }

   if(sparam != "LZ_HUD_BG")
      return;

   if(id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CHANGE)
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
      if(id == CHARTEVENT_OBJECT_CHANGE)
         g_hud_is_dragging = false;
      ChartRedraw(0);
     }
  }
//+------------------------------------------------------------------+
