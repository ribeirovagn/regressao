#ifndef MARKETREGIME_HUD_HUDRENDERER_MQH
#define MARKETREGIME_HUD_HUDRENDERER_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "HUDLayout.mqh"
#include "HUDDragController.mqh"

string HUDLineName(const int idx)
{
   return StringFormat("LZ_HUD_LINE_%d", idx);
}

bool HUDTextStartsWith(const string txt, const string prefix)
{
   return (StringFind(txt, prefix) == 0);
}

bool IsPrimaryHUDLine(const string txt)
{
   return (HUDTextStartsWith(txt, "REGIME:") ||
           HUDTextStartsWith(txt, "BIAS:") ||
           HUDTextStartsWith(txt, "MICROTREND:") ||
           HUDTextStartsWith(txt, "DIR:") ||
           HUDTextStartsWith(txt, "STRENGTH:"));
}

bool IsDetailsHUDLine(const string txt)
{
   return HUDTextStartsWith(txt, "R2:");
}

void AppendHUDLine(string &lines[], const string txt)
{
   const int n = ArraySize(lines);
   ArrayResize(lines, n + 1);
   lines[n] = txt;
}

string DirectionToText(const int dir)
{
   if (dir > 0)
      return "UP";
   if (dir < 0)
      return "DOWN";
   return "NEUTRAL";
}

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

void DeleteTrendHUD()
{
   ObjectDelete(0, "LZ_HUD_SHADOW");
   ObjectDelete(0, "LZ_HUD_BG");
   ObjectDelete(0, "LZ_HUD_ACCENT");
   ObjectDelete(0, "LZ_HUD_BAR_BG");
   ObjectDelete(0, "LZ_HUD_BAR_FILL");
   for (int i = 0; i < HUD_MAX_LINES; ++i)
      ObjectDelete(0, HUDLineName(i));

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

void RenderTrendHUD(const HUDState &state)
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
   const int alpha = ClampInt((int)MathRound(aMin + (aMax - aMin) * Clamp01(state.strength01)), 0, 255);

   const string regimeText = (state.regime == REGIME_RANGE ? "RANGE" : (state.regime == REGIME_TREND ? "TREND" : "MIXED"));
   const string biasText = DirectionToText(state.biasDir);
   const string microText = DirectionToText(state.microDir);
   const int strengthPct = (int)MathRound(Clamp01(state.strength01) * 100.0);

   color base = clrSilver;
   if (state.regime != REGIME_MIXED)
   {
      if (state.biasDir > 0)
         base = clrLimeGreen;
      else if (state.biasDir < 0)
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
   {
      AppendHUDLine(lines, StringFormat("DIR: %s", biasText));
   }
   AppendHUDLine(lines, StringFormat("STRENGTH: %d", strengthPct));
   if (state.hasTrendExhaustion)
      AppendHUDLine(lines, StringFormat("TREND EXHAUSTION: %d", ClampInt(state.trendExhaustionPct, 0, 100)));
   else
      AppendHUDLine(lines, "TREND EXHAUSTION: N/A");
   if (state.hasBreakQuality)
      AppendHUDLine(lines, StringFormat("BREAK QUALITY: %d", ClampInt(state.breakQualityPct, 0, 100)));
   else
      AppendHUDLine(lines, "BREAK QUALITY: N/A");
   if (state.step >= 0.0)
      AppendHUDLine(lines, StringFormat("STEP: %s", DoubleToString(state.step, MathMax(0, _Digits))));
   else
      AppendHUDLine(lines, "STEP: N/A");
   AppendHUDLine(lines, StringFormat("STEP SRC: %s", state.stepSource));
   if (InpEnableZoneEnergy)
   {
      if (state.hasZoneEnergy)
         AppendHUDLine(lines, StringFormat("ZONE ENERGY: %d", ClampInt(state.zoneEnergyPct, 0, 100)));
      else
         AppendHUDLine(lines, "ZONE ENERGY: N/A");
   }
   if (InpShowTrendDetails)
      AppendHUDLine(lines, StringFormat("R2: %.2f  ER: %.2f  S: %.2f", Clamp01(state.r2), Clamp01(state.er), Clamp01(state.slope01)));

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

   int fillW = (int)MathRound((double)barW * Clamp01(state.strength01));
   if (state.strength01 > 0.0 && fillW < 1)
      fillW = 1;
   if (fillW < 0)
      fillW = 0;

   color fillColor = activeColor;
   if (state.strength01 <= 0.0)
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

#endif
