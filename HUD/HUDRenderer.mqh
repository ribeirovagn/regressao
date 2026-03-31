#ifndef MARKETREGIME_HUD_HUDRENDERER_MQH
#define MARKETREGIME_HUD_HUDRENDERER_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "HUDLayout.mqh"
#include "HUDDragController.mqh"

string HUDDisplayTitle()
{
   return "MarketRegime Zones";
}

string HUDDisplayVersion()
{
   return "v2.13";
}

string DirectionToText(const int dir)
{
   if (dir > 0)
      return "UP";
   if (dir < 0)
      return "DOWN";
   return "NEUTRAL";
}

string RegimeToText(const ENUM_REGIME_STATE regime)
{
   if (regime == REGIME_RANGE)
      return "RANGE";
   if (regime == REGIME_TREND)
      return "TREND";
   return "MIXED";
}

string PctToText(const bool hasValue, const int pct)
{
   if (!hasValue)
      return "N/A";
   return IntegerToString(ClampInt(pct, 0, 100));
}

string StepToText(const double step)
{
   if (step < 0.0)
      return "N/A";
   return DoubleToString(step, MathMax(0, _Digits));
}

string DetailMetricText(const string key, const bool enabled, const double value)
{
   if (!enabled)
      return StringFormat("%s N/A", key);
   return StringFormat("%s %.2f", key, Clamp01(value));
}

color HUDDirectionColor(const int dir,
                        const color upColor,
                        const color downColor,
                        const color neutralColor)
{
   if (dir > 0)
      return upColor;
   if (dir < 0)
      return downColor;
   return neutralColor;
}

color HUDRegimeColor(const HUDState &state,
                     const color upColor,
                     const color downColor,
                     const color rangeColor,
                     const color neutralColor)
{
   if (state.regime == REGIME_RANGE)
      return rangeColor;
   if (state.regime == REGIME_TREND)
      return HUDDirectionColor(state.biasDir, upColor, downColor, neutralColor);
   return neutralColor;
}

color HUDExhaustionColor(const bool hasValue,
                         const int pct,
                         const color naColor)
{
   if (!hasValue)
      return naColor;
   if (pct >= 70)
      return (color)ColorToARGB(clrOrangeRed, 225);
   if (pct >= 40)
      return (color)ColorToARGB(clrOrange, 225);
   return (color)ColorToARGB(clrGold, 225);
}

color HUDBreakQualityColor(const bool hasValue,
                           const int pct,
                           const color goodColor,
                           const color warnColor,
                           const color lowColor,
                           const color naColor)
{
   if (!hasValue)
      return naColor;
   if (pct >= 70)
      return goodColor;
   if (pct >= 40)
      return warnColor;
   return lowColor;
}

color HUDZoneEnergyColor(const bool hasValue,
                         const int pct,
                         const color strongColor,
                         const color softColor,
                         const color naColor)
{
   if (!hasValue)
      return naColor;
   if (pct >= 65)
      return strongColor;
   return softColor;
}

color HUDStepSourceColor(const string stepSource,
                         const color accentColor,
                         const color naColor)
{
   if (stepSource == "N/A")
      return naColor;
   return accentColor;
}

void EnsureHUDRectangle(const string name)
{
   if (ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
}

void EnsureHUDLabel(const string name)
{
   if (ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
}

void DeleteLegacyHUDObjects()
{
   DeleteByPrefix("LZ_HUD_LINE_");
   ObjectDelete(0, "LZ_HUD_TXT");
   ObjectDelete(0, "LZ_HUD_LINE1");
   ObjectDelete(0, "LZ_HUD_LINE2");
   ObjectDelete(0, "LZ_HUD_LINE3");
   ObjectDelete(0, "LZ_HUD_LINE4");
   ObjectDelete(0, "LZ_HUD_LINE5");
   ObjectDelete(0, "LZ_HUD_DETAILS");
   ObjectDelete(0, "LZ_HUD_EBAR_BG");
   ObjectDelete(0, "LZ_HUD_EBAR_FILL");
}

void SetHUDRect(const string name,
                const int x,
                const int y,
                const int w,
                const int h,
                const color bgColor,
                const color borderColor,
                const bool selectable)
{
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, MathMax(0, w));
   ObjectSetInteger(0, name, OBJPROP_YSIZE, MathMax(0, h));
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, borderColor);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, selectable);
   if (!selectable)
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void SetHUDLabel(const string name,
                 const int x,
                 const int y,
                 const string text,
                 const string font,
                 const int fontSize,
                 const color textColor)
{
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void EnsureHUDObjectsCreated()
{
   bool bgCreated = false;

   EnsureHUDRectangle("LZ_HUD_SHADOW");
   if (ObjectFind(0, "LZ_HUD_BG") < 0)
   {
      ObjectCreate(0, "LZ_HUD_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      bgCreated = true;
   }
   EnsureHUDRectangle("LZ_HUD_ACCENT");

   EnsureHUDRectangle("LZ_HUD_ICON_BG");
   EnsureHUDRectangle("LZ_HUD_ICON_1");
   EnsureHUDRectangle("LZ_HUD_ICON_2");
   EnsureHUDRectangle("LZ_HUD_ICON_3");
   EnsureHUDLabel("LZ_HUD_TITLE");
   EnsureHUDRectangle("LZ_HUD_VERSION_BG");
   EnsureHUDLabel("LZ_HUD_VERSION_TXT");

   EnsureHUDRectangle("LZ_HUD_DIVIDER_TOP");
   EnsureHUDRectangle("LZ_HUD_DIVIDER_MID");
   EnsureHUDRectangle("LZ_HUD_DIVIDER_BOTTOM");
   EnsureHUDRectangle("LZ_HUD_VSEP_1");
   EnsureHUDRectangle("LZ_HUD_VSEP_2");
   EnsureHUDRectangle("LZ_HUD_VSEP_3");
   EnsureHUDRectangle("LZ_HUD_VSEP_MID");

   EnsureHUDLabel("LZ_HUD_LBL_REGIME");
   EnsureHUDLabel("LZ_HUD_VAL_REGIME");
   EnsureHUDLabel("LZ_HUD_LBL_BIAS");
   EnsureHUDLabel("LZ_HUD_VAL_BIAS");
   EnsureHUDLabel("LZ_HUD_LBL_MICRO");
   EnsureHUDLabel("LZ_HUD_VAL_MICRO");
   EnsureHUDLabel("LZ_HUD_LBL_STRENGTH");
   EnsureHUDLabel("LZ_HUD_VAL_STRENGTH");
   EnsureHUDRectangle("LZ_HUD_BAR_BG");
   EnsureHUDRectangle("LZ_HUD_BAR_FILL");

   EnsureHUDLabel("LZ_HUD_LBL_EXHAUST");
   EnsureHUDLabel("LZ_HUD_VAL_EXHAUST");
   EnsureHUDLabel("LZ_HUD_LBL_BREAKQ");
   EnsureHUDLabel("LZ_HUD_VAL_BREAKQ");
   EnsureHUDLabel("LZ_HUD_LBL_STEP");
   EnsureHUDLabel("LZ_HUD_VAL_STEP");
   EnsureHUDLabel("LZ_HUD_LBL_STEPSRC");
   EnsureHUDLabel("LZ_HUD_VAL_STEPSRC");
   EnsureHUDLabel("LZ_HUD_LBL_ENERGY");
   EnsureHUDLabel("LZ_HUD_VAL_ENERGY");

   EnsureHUDRectangle("LZ_HUD_DETAILS_ICON");
   EnsureHUDLabel("LZ_HUD_DETAILS_TXT");
   EnsureHUDLabel("LZ_HUD_DETAILS_R2");
   EnsureHUDLabel("LZ_HUD_DETAILS_ER");
   EnsureHUDLabel("LZ_HUD_DETAILS_S");

   DeleteLegacyHUDObjects();

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

void RenderHUDBase(const int x,
                   const int y,
                   const int panelW,
                   const int panelH,
                   const color shadowColor,
                   const color panelBgColor,
                   const color accentColor)
{
   SetHUDRect("LZ_HUD_SHADOW",
              x + 6,
              y + 8,
              panelW,
              panelH,
              shadowColor,
              (color)clrNONE,
              false);

   SetHUDRect("LZ_HUD_BG",
              x,
              y,
              panelW,
              panelH,
              panelBgColor,
              (color)clrNONE,
              InpHUDDraggable);
   if (!InpHUDDraggable)
      ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_SELECTED, false);

   SetHUDRect("LZ_HUD_ACCENT",
              x + HUD_SIDE_PADDING,
              y + 11,
              MathMax(12, panelW - 2 * HUD_SIDE_PADDING),
              3,
              accentColor,
              (color)clrNONE,
              false);
}

void RenderHUDHeader(const int x,
                     const int headerY,
                     const int panelW,
                     const int dividerTopY,
                     const color iconBgColor,
                     const color iconBarColor,
                     const color titleColor,
                     const color badgeBgColor,
                     const color badgeBorderColor,
                     const color badgeTextColor,
                     const color dividerColor,
                     const int titleFontSize,
                     const int badgeFontSize)
{
   const int contentX = x + HUD_SIDE_PADDING;
   const int iconSize = 30;
   const int iconX = contentX;
   const int iconY = headerY + 6;
   const int titleX = iconX + iconSize + 14;
   const int titleY = headerY + 7;
   const int badgeW = 68;
   const int badgeH = 24;
   const int badgeX = x + panelW - HUD_SIDE_PADDING - badgeW;
   const int badgeY = headerY + 9;

   SetHUDRect("LZ_HUD_ICON_BG", iconX, iconY, iconSize, iconSize, iconBgColor, (color)clrNONE, false);
   SetHUDRect("LZ_HUD_ICON_1", iconX + 7, iconY + 8, 16, 2, iconBarColor, (color)clrNONE, false);
   SetHUDRect("LZ_HUD_ICON_2", iconX + 7, iconY + 14, 12, 2, iconBarColor, (color)clrNONE, false);
   SetHUDRect("LZ_HUD_ICON_3", iconX + 7, iconY + 20, 18, 2, iconBarColor, (color)clrNONE, false);

   SetHUDLabel("LZ_HUD_TITLE",
               titleX,
               titleY,
               HUDDisplayTitle(),
               "Segoe UI Semibold",
               titleFontSize,
               titleColor);

   SetHUDRect("LZ_HUD_VERSION_BG",
              badgeX,
              badgeY,
              badgeW,
              badgeH,
              badgeBgColor,
              badgeBorderColor,
              false);
   SetHUDLabel("LZ_HUD_VERSION_TXT",
               badgeX + 17,
               badgeY + 4,
               HUDDisplayVersion(),
               "Segoe UI Semibold",
               badgeFontSize,
               badgeTextColor);

   SetHUDRect("LZ_HUD_DIVIDER_TOP",
              contentX,
              dividerTopY,
              MathMax(12, panelW - 2 * HUD_SIDE_PADDING),
              HUD_DIVIDER_THICKNESS,
              dividerColor,
              (color)clrNONE,
              false);
}

void RenderHUDTopGrid(const int x,
                      const int panelW,
                      const int topGridY,
                      const int topGridH,
                      const int dividerMidY,
                      const string regimeText,
                      const string biasText,
                      const string microText,
                      const int strengthPct,
                      const color labelColor,
                      const color regimeColor,
                      const color biasColor,
                      const color microColor,
                      const color strengthColor,
                      const color dividerColor,
                      const color barBgColor,
                      const color barFillColor,
                      const int labelFontSize,
                      const int valueFontSize,
                      const int strengthFontSize)
{
   const int contentX = x + HUD_SIDE_PADDING;
   const int contentW = MathMax(16, panelW - 2 * HUD_SIDE_PADDING);
   const int colW = contentW / 4;
   const int colPad = 10;
   const int labelY = topGridY + 2;
   const int valueY = topGridY + 28;
   const int strengthValueY = topGridY + 14;
   const int sepY = topGridY + 2;
   const int sepH = MathMax(10, topGridH - 4);

   SetHUDRect("LZ_HUD_VSEP_1", contentX + colW, sepY, 1, sepH, dividerColor, (color)clrNONE, false);
   SetHUDRect("LZ_HUD_VSEP_2", contentX + 2 * colW, sepY, 1, sepH, dividerColor, (color)clrNONE, false);
   SetHUDRect("LZ_HUD_VSEP_3", contentX + 3 * colW, sepY, 1, sepH, dividerColor, (color)clrNONE, false);

   SetHUDLabel("LZ_HUD_LBL_REGIME", contentX + colPad, labelY, "REGIME", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_REGIME", contentX + colPad, valueY, regimeText, "Segoe UI Semibold", valueFontSize, regimeColor);

   SetHUDLabel("LZ_HUD_LBL_BIAS", contentX + colW + colPad, labelY, "BIAS", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_BIAS", contentX + colW + colPad, valueY, biasText, "Segoe UI Semibold", valueFontSize, biasColor);

   SetHUDLabel("LZ_HUD_LBL_MICRO", contentX + 2 * colW + colPad, labelY, "MICROTREND", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_MICRO", contentX + 2 * colW + colPad, valueY, microText, "Segoe UI Semibold", valueFontSize, microColor);

   const int strengthX = contentX + 3 * colW + colPad;
   const int strengthBarY = topGridY + 54;
   const int strengthBarW = MathMax(16, colW - 2 * colPad - 2);
   const int strengthBarH = HUDBarHeight();
   int strengthFillW = (int)MathRound((double)strengthBarW * Clamp01((double)strengthPct / 100.0));
   if (strengthPct > 0 && strengthFillW < 1)
      strengthFillW = 1;

   SetHUDLabel("LZ_HUD_LBL_STRENGTH", strengthX, labelY, "STRENGTH", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_STRENGTH",
               strengthX,
               strengthValueY,
               IntegerToString(ClampInt(strengthPct, 0, 100)),
               "Segoe UI Semibold",
               strengthFontSize,
               strengthColor);

   SetHUDRect("LZ_HUD_BAR_BG",
              strengthX,
              strengthBarY,
              strengthBarW,
              strengthBarH,
              barBgColor,
              (color)clrNONE,
              false);
   SetHUDRect("LZ_HUD_BAR_FILL",
              strengthX,
              strengthBarY,
              MathMin(strengthBarW, MathMax(0, strengthFillW)),
              strengthBarH,
              barFillColor,
              (color)clrNONE,
              false);

   SetHUDRect("LZ_HUD_DIVIDER_MID",
              contentX,
              dividerMidY,
              MathMax(12, contentW),
              HUD_DIVIDER_THICKNESS,
              dividerColor,
              (color)clrNONE,
              false);
}

void RenderHUDMiddleGrid(const int x,
                         const int panelW,
                         const int middleGridY,
                         const int middleGridH,
                         const int dividerBottomY,
                         const string exhaustText,
                         const string breakText,
                         const string stepText,
                         const string stepSourceText,
                         const string energyText,
                         const color labelColor,
                         const color exhaustColor,
                         const color breakColor,
                         const color stepColor,
                         const color stepSourceColor,
                         const color energyColor,
                         const color dividerColor,
                         const int labelFontSize,
                         const int valueFontSize,
                         const int smallValueFontSize)
{
   const int contentX = x + HUD_SIDE_PADDING;
   const int contentW = MathMax(16, panelW - 2 * HUD_SIDE_PADDING);
   const int colGap = 18;
   const int colW = MathMax(20, (contentW - colGap) / 2);
   const int leftX = contentX;
   const int rightX = contentX + colW + colGap;
   const int midSepX = contentX + colW + (colGap / 2);
   const int valueOffset = MathMax(122, colW - 120);
   const int stretch = MathMax(0, middleGridH - HUD_MIDDLE_GRID_BASE_HEIGHT);

   const int leftRow1Y = middleGridY + 0;
   const int leftRow2Y = middleGridY + 24 + (stretch / 3);
   const int leftRow3Y = middleGridY + 48 + ((2 * stretch) / 3);
   const int rightRow1Y = middleGridY + 8;
   const int rightRow2Y = middleGridY + 42 + (stretch / 2);

   SetHUDRect("LZ_HUD_VSEP_MID",
              midSepX,
              middleGridY + 2,
              1,
              MathMax(10, middleGridH - 4),
              dividerColor,
              (color)clrNONE,
              false);

   SetHUDLabel("LZ_HUD_LBL_EXHAUST", leftX, leftRow1Y, "TREND EXHAUSTION", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_EXHAUST", leftX + valueOffset, leftRow1Y - 1, exhaustText, "Segoe UI Semibold", valueFontSize, exhaustColor);

   SetHUDLabel("LZ_HUD_LBL_BREAKQ", leftX, leftRow2Y, "BREAK QUALITY", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_BREAKQ", leftX + valueOffset, leftRow2Y - 1, breakText, "Segoe UI Semibold", valueFontSize, breakColor);

   SetHUDLabel("LZ_HUD_LBL_STEP", leftX, leftRow3Y, "STEP", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_STEP", leftX + valueOffset, leftRow3Y - 1, stepText, "Segoe UI Semibold", smallValueFontSize, stepColor);

   SetHUDLabel("LZ_HUD_LBL_STEPSRC", rightX, rightRow1Y, "STEP SRC", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_STEPSRC", rightX + valueOffset, rightRow1Y - 1, stepSourceText, "Segoe UI Semibold", smallValueFontSize, stepSourceColor);

   SetHUDLabel("LZ_HUD_LBL_ENERGY", rightX, rightRow2Y, "ZONE ENERGY", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_ENERGY", rightX + valueOffset, rightRow2Y - 1, energyText, "Segoe UI Semibold", valueFontSize, energyColor);

   SetHUDRect("LZ_HUD_DIVIDER_BOTTOM",
              contentX,
              dividerBottomY,
              MathMax(12, contentW),
              HUD_DIVIDER_THICKNESS,
              dividerColor,
              (color)clrNONE,
              false);
}

void RenderHUDFooter(const int x,
                     const int panelW,
                     const int footerY,
                     const string r2Text,
                     const string erText,
                     const string sText,
                     const color detailsIconColor,
                     const color labelColor,
                     const color detailValueColor,
                     const int labelFontSize,
                     const int detailFontSize)
{
   const int contentX = x + HUD_SIDE_PADDING;
   const int contentW = MathMax(16, panelW - 2 * HUD_SIDE_PADDING);
   const int iconY = footerY + 6;
   const int iconSize = 10;
   const int detailsX = contentX + 16;
   const int metricW = 68;
   const int metricGap = 14;
   const int metricsStartX = contentX + MathMax(130, contentW - (metricW * 3 + metricGap * 2));

   SetHUDRect("LZ_HUD_DETAILS_ICON",
              contentX,
              iconY,
              iconSize,
              iconSize,
              detailsIconColor,
              (color)clrNONE,
              false);
   SetHUDLabel("LZ_HUD_DETAILS_TXT", detailsX, footerY + 1, "DETAILS", "Segoe UI Semibold", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_DETAILS_R2", metricsStartX, footerY, r2Text, "Segoe UI Semibold", detailFontSize, detailValueColor);
   SetHUDLabel("LZ_HUD_DETAILS_ER", metricsStartX + metricW + metricGap, footerY, erText, "Segoe UI Semibold", detailFontSize, detailValueColor);
   SetHUDLabel("LZ_HUD_DETAILS_S", metricsStartX + 2 * (metricW + metricGap), footerY, sText, "Segoe UI Semibold", detailFontSize, detailValueColor);
}

void DeleteTrendHUD()
{
   for (int i = 0; i < HUD_OBJECT_COUNT; ++i)
   {
      const string name = HUDObjectName(i);
      if (StringLen(name) > 0)
         ObjectDelete(0, name);
   }

   DeleteLegacyHUDObjects();
}

void RenderTrendHUD(const HUDState &state)
{
   EnsureHUDObjectsCreated();

   if (InpHUDDraggable && !g_hud_is_dragging && g_hud_user_moved)
      SyncHUDPositionFromObject();

   const int panelW = HUDPanelWidth();
   const int panelH = HUDPanelHeight();
   if (!g_hud_user_moved)
   {
      g_hud_x = HUDDefaultX(panelW);
      g_hud_y = HUDDefaultY();
   }
   ClampHUDPosition(panelW, panelH);

   const int x = MathMax(0, g_hud_x);
   const int y = MathMax(0, g_hud_y);
   const int extraH = MathMax(0, panelH - HUDMinimumPanelHeight());
   const int middleGridH = HUD_MIDDLE_GRID_BASE_HEIGHT + extraH;

   const int headerY = y + HUD_TOP_PADDING;
   const int dividerTopY = headerY + HUD_HEADER_HEIGHT;
   const int topGridY = dividerTopY + HUD_DIVIDER_THICKNESS + HUD_SECTION_GAP;
   const int dividerMidY = topGridY + HUD_TOP_GRID_HEIGHT + HUD_SECTION_GAP;
   const int middleGridY = dividerMidY + HUD_DIVIDER_THICKNESS + HUD_SECTION_GAP;
   const int dividerBottomY = middleGridY + middleGridH + HUD_SECTION_GAP;
   const int footerY = dividerBottomY + HUD_DIVIDER_THICKNESS + HUD_SECTION_GAP;

   int aMin = ClampInt(InpHUDAlphaMin, 0, 255);
   int aMax = ClampInt(InpHUDAlphaMax, 0, 255);
   if (aMax < aMin)
   {
      const int t = aMin;
      aMin = aMax;
      aMax = t;
   }
   const int alpha = ClampInt((int)MathRound(aMin + (aMax - aMin) * Clamp01(state.strength01)), 0, 255);

   const bool showBiasAndMicro = InpShowBiasAndMicrotrend;
   const bool showDetails = InpShowTrendDetails;

   const string regimeText = RegimeToText(state.regime);
   const string biasText = (showBiasAndMicro ? DirectionToText(state.biasDir) : "N/A");
   const string microText = (showBiasAndMicro ? DirectionToText(state.microDir) : "N/A");
   const int strengthPct = ClampInt((int)MathRound(Clamp01(state.strength01) * 100.0), 0, 100);
   const string exhaustText = PctToText(state.hasTrendExhaustion, state.trendExhaustionPct);
   const string breakText = PctToText(state.hasBreakQuality, state.breakQualityPct);
   const string stepText = StepToText(state.step);
   const string stepSourceText = (state.step >= 0.0 && StringLen(state.stepSource) > 0 ? state.stepSource : "N/A");
   const string energyText = PctToText(InpEnableZoneEnergy && state.hasZoneEnergy, state.zoneEnergyPct);
   const string r2Text = DetailMetricText("R2", showDetails, state.r2);
   const string erText = DetailMetricText("ER", showDetails, state.er);
   const string sText = DetailMetricText("S", showDetails, state.slope01);

   const color shadowColor = (color)ColorToARGB(clrBlack, (uchar)ClampInt(16 + (alpha / 16), 16, 32));
   const color panelBgColor = (color)ColorToARGB(clrMidnightBlue, (uchar)ClampInt(96 + (alpha / 6), 96, 138));
   const color accentColor = (color)ColorToARGB(clrDeepSkyBlue, (uchar)ClampInt(128 + (alpha / 4), 128, 188));
   const color dividerColor = (color)ColorToARGB(clrLightSteelBlue, 42);
   const color titleColor = (color)ColorToARGB(clrWhiteSmoke, 235);
   const color badgeBgColor = (color)ColorToARGB(clrDarkSlateBlue, 145);
   const color badgeBorderColor = (color)ColorToARGB(clrDeepSkyBlue, 52);
   const color badgeTextColor = (color)ColorToARGB(clrAliceBlue, 222);
   const color iconBgColor = (color)ColorToARGB(clrDodgerBlue, 165);
   const color iconBarColor = (color)ColorToARGB(clrAliceBlue, 224);
   const color labelColor = (color)ColorToARGB(clrSilver, 178);
   const color neutralValueColor = (color)ColorToARGB(clrGainsboro, 214);
   const color upColor = (color)ColorToARGB(clrAquamarine, 224);
   const color downColor = (color)ColorToARGB(clrTomato, 222);
   const color rangeColor = (color)ColorToARGB(clrLightSkyBlue, 218);
   const color strengthColor = (color)ColorToARGB(clrAliceBlue, 230);
   const color barBgColor = (color)ColorToARGB(clrSlateGray, 95);
   const color barFillColor = (color)ColorToARGB(clrDeepSkyBlue, 224);
   const color warnColor = (color)ColorToARGB(clrGold, 224);
   const color stepColor = (color)ColorToARGB(clrLightSkyBlue, 226);
   const color stepSourceAccent = (color)ColorToARGB(clrMediumPurple, 220);
   const color energySoftColor = (color)ColorToARGB(clrPowderBlue, 214);
   const color detailValueColor = (color)ColorToARGB(clrSilver, 204);

   const color regimeColor = HUDRegimeColor(state, upColor, downColor, rangeColor, neutralValueColor);
   const color biasColor = (showBiasAndMicro ? HUDDirectionColor(state.biasDir, upColor, downColor, neutralValueColor) : neutralValueColor);
   const color microColor = (showBiasAndMicro ? HUDDirectionColor(state.microDir, upColor, downColor, neutralValueColor) : neutralValueColor);
   const color exhaustColor = HUDExhaustionColor(state.hasTrendExhaustion, state.trendExhaustionPct, neutralValueColor);
   const color breakColor = HUDBreakQualityColor(state.hasBreakQuality,
                                                 state.breakQualityPct,
                                                 upColor,
                                                 warnColor,
                                                 downColor,
                                                 neutralValueColor);
   const color stepSourceColor = HUDStepSourceColor(stepSourceText, stepSourceAccent, neutralValueColor);
   const color energyColor = HUDZoneEnergyColor(InpEnableZoneEnergy && state.hasZoneEnergy,
                                                state.zoneEnergyPct,
                                                upColor,
                                                energySoftColor,
                                                neutralValueColor);

   const int baseFont = MathMax(9, InpHUDFontSize);
   const int labelFontSize = MathMax(8, baseFont - 1);
   const int valueFontSize = baseFont + 3;
   const int smallValueFontSize = baseFont + 1;
   const int strengthFontSize = baseFont + 8;
   const int titleFontSize = baseFont + 3;
   const int badgeFontSize = MathMax(8, baseFont - 1);
   const int detailFontSize = MathMax(9, baseFont);

   RenderHUDBase(x, y, panelW, panelH, shadowColor, panelBgColor, accentColor);
   RenderHUDHeader(x,
                   headerY,
                   panelW,
                   dividerTopY,
                   iconBgColor,
                   iconBarColor,
                   titleColor,
                   badgeBgColor,
                   badgeBorderColor,
                   badgeTextColor,
                   dividerColor,
                   titleFontSize,
                   badgeFontSize);
   RenderHUDTopGrid(x,
                    panelW,
                    topGridY,
                    HUD_TOP_GRID_HEIGHT,
                    dividerMidY,
                    regimeText,
                    biasText,
                    microText,
                    strengthPct,
                    labelColor,
                    regimeColor,
                    biasColor,
                    microColor,
                    strengthColor,
                    dividerColor,
                    barBgColor,
                    barFillColor,
                    labelFontSize,
                    valueFontSize,
                    strengthFontSize);
   RenderHUDMiddleGrid(x,
                       panelW,
                       middleGridY,
                       middleGridH,
                       dividerBottomY,
                       exhaustText,
                       breakText,
                       stepText,
                       stepSourceText,
                       energyText,
                       labelColor,
                       exhaustColor,
                       breakColor,
                       stepColor,
                       stepSourceColor,
                       energyColor,
                       dividerColor,
                       labelFontSize,
                       valueFontSize,
                       smallValueFontSize);
   RenderHUDFooter(x,
                   panelW,
                   footerY,
                   r2Text,
                   erText,
                   sText,
                   accentColor,
                   labelColor,
                   detailValueColor,
                   labelFontSize,
                   detailFontSize);
}

#endif
