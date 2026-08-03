#ifndef MARKETREGIME_HUD_HUDRENDERER_MQH
#define MARKETREGIME_HUD_HUDRENDERER_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/HumanDecisionEvent.mqh"
#include "HUDLayout.mqh"
#include "HUDDragController.mqh"

string HUDDisplayTitle()
{
   return "MarketRegime Zones";
}

string HUDDisplayVersion()
{
   return "v2.17";
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

string HUDMetricLineText(const string label, const string value)
{
   return label + ": " + value;
}

int MeasureHUDTextWidth(const string text,
                        const string font,
                        const int fontSize)
{
   if (fontSize <= 0 || StringLen(text) == 0)
      return 0;

   uint textW = 0;
   uint textH = 0;
   const int logicalFontSize = -10 * MathMax(1, fontSize);
   if (TextSetFont(font, logicalFontSize, 0) && TextGetSize(text, textW, textH))
      return (int)textW;

   return StringLen(text) * MathMax(6, fontSize + 2);
}

int HUDMetricColumnWidth(const string row1,
                         const string row2,
                         const string row3,
                         const string row4,
                         const int metricFontSize)
{
   const int measure1 = MeasureHUDTextWidth(row1, "Segoe UI Semibold", metricFontSize);
   const int measure2 = MeasureHUDTextWidth(row2, "Segoe UI Semibold", metricFontSize);
   const int measure3 = MeasureHUDTextWidth(row3, "Segoe UI Semibold", metricFontSize);
   const int measure4 = MeasureHUDTextWidth(row4, "Segoe UI Semibold", metricFontSize);
   return MathMax(MathMax(measure1, measure2), MathMax(measure3, measure4)) + 8;
}

int HUDResolvePanelWidth(const string exhaustText,
                         const string breakText,
                         const string volumeBiasText,
                         const string volumeConfirmText,
                         const string stepText,
                         const string stepSourceText,
                         const string energyText,
                         const int metricFontSize)
{
   const string leftRow1 = HUDMetricLineText("TREND EXHAUSTION", exhaustText);
   const string leftRow2 = HUDMetricLineText("BREAK QUALITY", breakText);
   const string leftRow3 = HUDMetricLineText("VOLUME BIAS", volumeBiasText);
   const string leftRow4 = HUDMetricLineText("VOLUME CONFIRM", volumeConfirmText);
   const string rightRow1 = HUDMetricLineText("STEP", stepText);
   const string rightRow2 = HUDMetricLineText("STEP SRC", stepSourceText);
   const string rightRow3 = HUDMetricLineText("ZONE ENERGY", energyText);
   const int colSpacing = 20;
   const int colWidth = MathMax(HUDMetricColumnWidth(leftRow1, leftRow2, leftRow3, leftRow4, metricFontSize),
                                HUDMetricColumnWidth(rightRow1, rightRow2, rightRow3, "", metricFontSize));
   const int requiredW = 2 * HUD_SIDE_PADDING + colSpacing + 2 * colWidth;
   return MathMax(HUDBasePanelWidth(), requiredW);
}

int HUDMiddleMetricRowGap(const int metricFontSize)
{
   return MathMax(HUD_MIDDLE_GRID_MIN_ROW_GAP, metricFontSize + 5);
}

int HUDRequiredMiddleGridHeight(const int metricFontSize)
{
   const int rowGap = HUDMiddleMetricRowGap(metricFontSize);
   const int rowCount = 4;
   const int contentH = (rowGap * (rowCount - 1)) + metricFontSize + 10;
   return MathMax(HUD_MIDDLE_GRID_BASE_HEIGHT, contentH);
}

int HUDFooterRowGap(const int detailFontSize)
{
   return MathMax(HUD_FOOTER_MIN_ROW_GAP, detailFontSize + 5);
}

int HUDRequiredFooterHeight(const int detailFontSize,
                            const bool showVolumeDetails)
{
   const int rowGap = HUDFooterRowGap(detailFontSize);
   const int rowCount = (showVolumeDetails ? 2 : 1);
   const int contentH = (rowGap * (rowCount - 1)) + detailFontSize + 12;
   return MathMax(HUD_FOOTER_HEIGHT, contentH);
}

int HUDRequiredPanelHeight(const int middleGridH,
                           const int footerH)
{
   int height = HUD_TOP_PADDING +
                HUD_HEADER_HEIGHT +
                HUD_DIVIDER_THICKNESS +
                HUD_SECTION_GAP +
                HUD_TOP_GRID_HEIGHT +
                HUD_SECTION_GAP +
                HUD_DIVIDER_THICKNESS +
                HUD_SECTION_GAP +
                middleGridH +
                HUD_SECTION_GAP +
                HUD_DIVIDER_THICKNESS +
                HUD_SECTION_GAP +
                footerH;
   if (InpEnableDecisionEvents)
      height += HUD_SECTION_GAP +
                HUD_DIVIDER_THICKNESS +
                HUD_SECTION_GAP +
                HUD_DECISION_SECTION_HEIGHT;
   return height + HUD_BOTTOM_PADDING;
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

void EnsureHUDButton(const string name)
{
   if (ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
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
   ObjectDelete(0, "LZ_HUD_LBL_EXHAUST");
   ObjectDelete(0, "LZ_HUD_VAL_EXHAUST");
   ObjectDelete(0, "LZ_HUD_LBL_BREAKQ");
   ObjectDelete(0, "LZ_HUD_VAL_BREAKQ");
   ObjectDelete(0, "LZ_HUD_LBL_STEP");
   ObjectDelete(0, "LZ_HUD_VAL_STEP");
   ObjectDelete(0, "LZ_HUD_LBL_STEPSRC");
   ObjectDelete(0, "LZ_HUD_VAL_STEPSRC");
   ObjectDelete(0, "LZ_HUD_LBL_ENERGY");
   ObjectDelete(0, "LZ_HUD_VAL_ENERGY");
   ObjectDelete(0, "LZ_HUD_LBL_VOLBIAS");
   ObjectDelete(0, "LZ_HUD_VAL_VOLBIAS");
   ObjectDelete(0, "LZ_HUD_LBL_VOLCONF");
   ObjectDelete(0, "LZ_HUD_VAL_VOLCONF");
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
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
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

void SetHUDButton(const string name,
                  const int x,
                  const int y,
                  const int w,
                  const int h,
                  const string text,
                  const color bgColor,
                  const color borderColor,
                  const color textColor,
                  const int fontSize,
                  const bool enabled)
{
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, MathMax(0, w));
   ObjectSetInteger(0, name, OBJPROP_YSIZE, MathMax(0, h));
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, (enabled ? 2 : 0));
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0,
                   name,
                   OBJPROP_TOOLTIP,
                   (enabled ? "Registra a decisao humana em CSV; nenhuma ordem sera enviada" : "Sem evento ativo"));
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

   EnsureHUDLabel("LZ_HUD_ROW_EXHAUST");
   EnsureHUDLabel("LZ_HUD_ROW_BREAKQ");
   EnsureHUDLabel("LZ_HUD_ROW_STEP");
   EnsureHUDLabel("LZ_HUD_ROW_STEPSRC");
   EnsureHUDLabel("LZ_HUD_ROW_ENERGY");
   EnsureHUDLabel("LZ_HUD_ROW_VOLBIAS");
   EnsureHUDLabel("LZ_HUD_ROW_VOLCONF");

   EnsureHUDRectangle("LZ_HUD_DETAILS_ICON");
   EnsureHUDLabel("LZ_HUD_DETAILS_TXT");
   EnsureHUDLabel("LZ_HUD_DETAILS_R2");
   EnsureHUDLabel("LZ_HUD_DETAILS_ER");
   EnsureHUDLabel("LZ_HUD_DETAILS_S");
   EnsureHUDLabel("LZ_HUD_DETAILS_VOLR2");
   EnsureHUDLabel("LZ_HUD_DETAILS_VOLRATIO");
   EnsureHUDLabel("LZ_HUD_DETAILS_VOLS");

   if (InpEnableDecisionEvents)
   {
      EnsureHUDRectangle("LZ_HUD_DIVIDER_EVENT");
      EnsureHUDLabel("LZ_HUD_EVENT_TITLE");
      EnsureHUDLabel("LZ_HUD_EVENT_EVIDENCE");
      EnsureHUDLabel("LZ_HUD_EVENT_RISK");
      EnsureHUDLabel("LZ_HUD_EVENT_HINT");
      EnsureHUDLabel("LZ_HUD_EVENT_FEEDBACK");
      EnsureHUDButton("LZ_HUD_BTN_MARK_ENTRY");
      EnsureHUDButton("LZ_HUD_BTN_IGNORE");
   }
   else
   {
      for (int eventObjectIndex = 42; eventObjectIndex < HUD_OBJECT_COUNT; ++eventObjectIndex)
         ObjectDelete(0, HUDObjectName(eventObjectIndex));
   }

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

void SetHUDInlineMetric(const string name,
                        const int x,
                        const int y,
                        const string label,
                        const string value,
                        const int metricFontSize,
                        const color textColor)
{
   SetHUDLabel(name,
               x,
               y,
               HUDMetricLineText(label, value),
               "Segoe UI Semibold",
               metricFontSize,
               textColor);
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
              x + 3,
              y + 4,
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
              x + HUD_SIDE_PADDING + 2,
              y + 6,
              MathMax(12, panelW - 2 * HUD_SIDE_PADDING - 4),
              2,
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
                     const color dividerTopColor,
                     const int titleFontSize,
                     const int badgeFontSize)
{
   const int contentX = x + HUD_SIDE_PADDING;
   const int iconSize = 20;
   const int iconX = contentX;
   const int iconY = headerY + 4;
   const int titleX = iconX + iconSize + 10;
   const int titleY = headerY + 1;
   const int badgeW = 44;
   const int badgeH = 18;
   const int badgeX = x + panelW - HUD_SIDE_PADDING - badgeW;
   const int badgeY = headerY + 4;

   SetHUDRect("LZ_HUD_ICON_BG", iconX, iconY, iconSize, iconSize, iconBgColor, (color)clrNONE, false);
   SetHUDRect("LZ_HUD_ICON_1", iconX + 5, iconY + 5, 10, 2, iconBarColor, (color)clrNONE, false);
   SetHUDRect("LZ_HUD_ICON_2", iconX + 5, iconY + 10, 7, 2, iconBarColor, (color)clrNONE, false);
   SetHUDRect("LZ_HUD_ICON_3", iconX + 5, iconY + 15, 12, 2, iconBarColor, (color)clrNONE, false);

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
               badgeX + 10,
               badgeY + 2,
               HUDDisplayVersion(),
               "Segoe UI Semibold",
               badgeFontSize,
               badgeTextColor);

   SetHUDRect("LZ_HUD_DIVIDER_TOP",
              contentX + 3,
              dividerTopY,
              MathMax(12, panelW - 2 * HUD_SIDE_PADDING - 6),
              HUD_DIVIDER_THICKNESS,
              dividerTopColor,
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
                      const color vDividerColor,
                      const color barBgColor,
                      const color barFillColor,
                      const int labelFontSize,
                      const int valueFontSize,
                      const int strengthFontSize)
{
   const int contentX = x + HUD_SIDE_PADDING;
   const int contentW = MathMax(16, panelW - 2 * HUD_SIDE_PADDING);
   const int colW = contentW / 4;
   const int colPad = 6;
   const int labelY = topGridY + 0;
   const int valueY = topGridY + 14;
   const int strengthValueY = topGridY + 10;
   const int sepY = topGridY + 4;
   const int sepH = MathMax(10, topGridH - 12);

   SetHUDRect("LZ_HUD_VSEP_1", contentX + colW, sepY, 1, sepH, vDividerColor, (color)clrNONE, false);
   SetHUDRect("LZ_HUD_VSEP_2", contentX + 2 * colW, sepY, 1, sepH, vDividerColor, (color)clrNONE, false);
   SetHUDRect("LZ_HUD_VSEP_3", contentX + 3 * colW, sepY, 1, sepH, vDividerColor, (color)clrNONE, false);

   SetHUDLabel("LZ_HUD_LBL_REGIME", contentX + colPad, labelY, "REGIME", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_REGIME", contentX + colPad, valueY, regimeText, "Segoe UI Semibold", valueFontSize, regimeColor);

   SetHUDLabel("LZ_HUD_LBL_BIAS", contentX + colW + colPad, labelY, "BIAS", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_BIAS", contentX + colW + colPad, valueY, biasText, "Segoe UI Semibold", valueFontSize, biasColor);

   SetHUDLabel("LZ_HUD_LBL_MICRO", contentX + 2 * colW + colPad, labelY, "MICROTREND", "Segoe UI", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_VAL_MICRO", contentX + 2 * colW + colPad, valueY, microText, "Segoe UI Semibold", valueFontSize, microColor);

   const int strengthX = contentX + 3 * colW + colPad;
   const int strengthBarY = topGridY + 31;
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
              contentX + 2,
              dividerMidY,
              MathMax(12, contentW - 4),
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
                         const string volumeBiasText,
                         const string volumeConfirmText,
                         const string stepText,
                         const string stepSourceText,
                         const string energyText,
                         const color exhaustColor,
                         const color breakColor,
                         const color volumeBiasColor,
                         const color volumeConfirmColor,
                         const color stepColor,
                         const color stepSourceColor,
                         const color energyColor,
                         const color dividerColor,
                         const color vDividerColor,
                         const int metricFontSize)
{
   const int contentX = x + HUD_SIDE_PADDING;
   const int usableWidth = MathMax(16, panelW - 2 * HUD_SIDE_PADDING);
   const int colSpacing = 20;
   const int colWidth = MathMax(20, (usableWidth - colSpacing) / 2);
   const int col1X = contentX;
   const int col2X = col1X + colWidth + colSpacing;
   const int midSepX = col1X + colWidth + (colSpacing / 2);
   const int rowGap = HUDMiddleMetricRowGap(metricFontSize);

   const int row1Y = middleGridY;
   const int row2Y = middleGridY + rowGap;
   const int row3Y = middleGridY + 2 * rowGap;
   const int row4Y = middleGridY + 3 * rowGap;

   SetHUDRect("LZ_HUD_VSEP_MID",
              midSepX,
              middleGridY + 3,
              1,
              MathMax(10, middleGridH - 6),
              vDividerColor,
              (color)clrNONE,
              false);

   SetHUDInlineMetric("LZ_HUD_ROW_EXHAUST", col1X, row1Y, "TREND EXHAUSTION", exhaustText, metricFontSize, exhaustColor);
   SetHUDInlineMetric("LZ_HUD_ROW_BREAKQ", col1X, row2Y, "BREAK QUALITY", breakText, metricFontSize, breakColor);
   SetHUDInlineMetric("LZ_HUD_ROW_VOLBIAS", col1X, row3Y, "VOLUME BIAS", volumeBiasText, metricFontSize, volumeBiasColor);
   SetHUDInlineMetric("LZ_HUD_ROW_VOLCONF", col1X, row4Y, "VOLUME CONFIRM", volumeConfirmText, metricFontSize, volumeConfirmColor);
   SetHUDInlineMetric("LZ_HUD_ROW_STEP", col2X, row1Y, "STEP", stepText, metricFontSize, stepColor);
   SetHUDInlineMetric("LZ_HUD_ROW_STEPSRC", col2X, row2Y, "STEP SRC", stepSourceText, metricFontSize, stepSourceColor);
   SetHUDInlineMetric("LZ_HUD_ROW_ENERGY", col2X, row3Y, "ZONE ENERGY", energyText, metricFontSize, energyColor);

   SetHUDRect("LZ_HUD_DIVIDER_BOTTOM",
              contentX + 2,
              dividerBottomY,
              MathMax(12, usableWidth - 4),
              HUD_DIVIDER_THICKNESS,
              dividerColor,
              (color)clrNONE,
              false);
}

void RenderHUDFooter(const int x,
                     const int panelW,
                     const int footerY,
                     const int footerH,
                     const string r2Text,
                     const string erText,
                     const string sText,
                     const bool showVolumeDetails,
                     const string volR2Text,
                     const string volRatioText,
                     const string volSText,
                     const color detailsIconColor,
                     const color labelColor,
                     const color detailValueColor,
                     const int labelFontSize,
                     const int detailFontSize)
{
   const int contentX = x + HUD_SIDE_PADDING;
   const int contentW = MathMax(16, panelW - 2 * HUD_SIDE_PADDING);
   const int iconSize = 8;
   const int rowStartY = footerY + 2;
   const int detailsX = contentX + 11;
   const int metricW = 48;
   const int metricGap = 10;
   const int metricsStartX = contentX + MathMax(82, contentW - (metricW * 3 + metricGap * 2));
   const int rowGap = HUDFooterRowGap(detailFontSize);
   const int volumeRowY = rowStartY + rowGap;
   const int iconY = footerY + MathMax(0, ((footerH - iconSize) / 2));

   SetHUDRect("LZ_HUD_DETAILS_ICON",
              contentX,
              iconY,
              iconSize,
              iconSize,
              detailsIconColor,
              (color)clrNONE,
              false);
   SetHUDLabel("LZ_HUD_DETAILS_TXT", detailsX, rowStartY, "DETAILS", "Segoe UI Semibold", labelFontSize, labelColor);
   SetHUDLabel("LZ_HUD_DETAILS_R2", metricsStartX, rowStartY, r2Text, "Segoe UI Semibold", detailFontSize, detailValueColor);
   SetHUDLabel("LZ_HUD_DETAILS_ER", metricsStartX + metricW + metricGap, rowStartY, erText, "Segoe UI Semibold", detailFontSize, detailValueColor);
   SetHUDLabel("LZ_HUD_DETAILS_S", metricsStartX + 2 * (metricW + metricGap), rowStartY, sText, "Segoe UI Semibold", detailFontSize, detailValueColor);
   SetHUDLabel("LZ_HUD_DETAILS_VOLR2",
               metricsStartX,
               volumeRowY,
               (showVolumeDetails ? volR2Text : ""),
               "Segoe UI Semibold",
               detailFontSize,
               detailValueColor);
   SetHUDLabel("LZ_HUD_DETAILS_VOLRATIO",
               metricsStartX + metricW + metricGap,
               volumeRowY,
               (showVolumeDetails ? volRatioText : ""),
               "Segoe UI Semibold",
               detailFontSize,
               detailValueColor);
   SetHUDLabel("LZ_HUD_DETAILS_VOLS",
               metricsStartX + 2 * (metricW + metricGap),
               volumeRowY,
               (showVolumeDetails ? volSText : ""),
               "Segoe UI Semibold",
               detailFontSize,
               detailValueColor);
}

string HUDCompactDecisionText(const string text, const int maxCharacters)
{
   if (maxCharacters < 4 || StringLen(text) <= maxCharacters)
      return text;
   return StringSubstr(text, 0, maxCharacters - 3) + "...";
}

string HUDDecisionTitleText(const HUDDecisionEvent &event)
{
   if (!event.valid)
      return "EVENTO: SEM EVENTO CONFIRMADO";
   return StringFormat("EVENTO: %s | %s | %s | %d BARRAS",
                       HUDEventKindToString(event.kind),
                       HUDTradeDirectionToString(event.direction),
                       HUDEventStatusToString(event.status),
                       event.ageBars);
}

int HUDResolveDecisionPanelWidth(const int currentWidth,
                                 const HUDDecisionEvent &event,
                                 const int fontSize)
{
   if (!InpEnableDecisionEvents)
      return currentWidth;

   const string title = HUDCompactDecisionText(HUDDecisionTitleText(event), 62);
   const string evidence = HUDCompactDecisionText("EVIDENCIAS: " + event.evidenceText, 62);
   const string risks = HUDCompactDecisionText("RISCOS: " + event.riskText, 62);
   const int textWidth = MathMax(MeasureHUDTextWidth(title, "Segoe UI Semibold", fontSize),
                                 MathMax(MeasureHUDTextWidth(evidence, "Segoe UI", fontSize),
                                         MeasureHUDTextWidth(risks, "Segoe UI", fontSize)));
   return MathMax(currentWidth, MathMin(560, textWidth + 2 * HUD_SIDE_PADDING + 12));
}

color HUDDecisionHintColor(const ENUM_HUD_DECISION_HINT hint,
                           const color evaluateColor,
                           const color waitColor,
                           const color avoidColor)
{
   if (hint == HUD_DECISION_EVALUATE)
      return evaluateColor;
   if (hint == HUD_DECISION_AVOID)
      return avoidColor;
   return waitColor;
}

void RenderHUDDecisionPanel(const int x,
                            const int panelW,
                            const int dividerY,
                            const int decisionY,
                            const HUDDecisionEvent &event,
                            const color dividerColor,
                            const color labelColor,
                            const color neutralColor,
                            const color evaluateColor,
                            const color waitColor,
                            const color avoidColor,
                            const int fontSize)
{
   const int contentX = x + HUD_SIDE_PADDING;
   const int contentW = MathMax(40, panelW - 2 * HUD_SIDE_PADDING);
   SetHUDRect("LZ_HUD_DIVIDER_EVENT",
              contentX + 2,
              dividerY,
              MathMax(12, contentW - 4),
              HUD_DIVIDER_THICKNESS,
              dividerColor,
              (color)clrNONE,
              false);

   const string titleText = HUDCompactDecisionText(HUDDecisionTitleText(event), 62);
   const string evidenceText = HUDCompactDecisionText("EVIDENCIAS: " + event.evidenceText, 62);
   const string riskText = HUDCompactDecisionText("RISCOS: " + event.riskText, 62);
   const string hintText = "SINTESE HUMANA: " + HUDDecisionHintToString(event.hint) + " | NAO EXECUTA ORDENS";
   const color hintColor = HUDDecisionHintColor(event.hint, evaluateColor, waitColor, avoidColor);

   SetHUDLabel("LZ_HUD_EVENT_TITLE",
               contentX,
               decisionY,
               titleText,
               "Segoe UI Semibold",
               fontSize + 1,
               (event.valid ? hintColor : neutralColor));
   SetHUDLabel("LZ_HUD_EVENT_EVIDENCE",
               contentX,
               decisionY + 18,
               evidenceText,
               "Segoe UI",
               fontSize,
               (event.valid ? neutralColor : labelColor));
   SetHUDLabel("LZ_HUD_EVENT_RISK",
               contentX,
               decisionY + 35,
               riskText,
               "Segoe UI",
               fontSize,
               (event.riskFlags > 0 || event.hint == HUD_DECISION_AVOID ? avoidColor : labelColor));
   SetHUDLabel("LZ_HUD_EVENT_HINT",
               contentX,
               decisionY + 52,
               hintText,
               "Segoe UI Semibold",
               fontSize,
               hintColor);

   const bool activeStatus = (event.valid &&
                              (event.status == HUD_EVENT_STATUS_NEW ||
                               event.status == HUD_EVENT_STATUS_EVALUATING));
   const bool alreadyDecided = (activeStatus && HUDDecisionWasRecorded(event.key));
   const string recordedAction = (alreadyDecided ? HUDRecordedDecisionAction(event.key) : "");
   const bool buttonsEnabled = (activeStatus && !alreadyDecided);
   const int buttonGap = 8;
   const int buttonW = MathMax(40, (contentW - buttonGap) / 2);
   const int buttonY = decisionY + 69;
   const color enabledEntryBg = (color)ColorToARGB(clrDarkGreen, 178);
   const color enabledIgnoreBg = (color)ColorToARGB(clrMaroon, 168);
   const color disabledBg = (color)ColorToARGB(clrSlateGray, 48);
   const color enabledText = (color)ColorToARGB(clrWhiteSmoke, 230);
   const color disabledText = (color)ColorToARGB(clrSilver, 105);
   const color enabledBorder = (color)ColorToARGB(clrSilver, 72);
   const color disabledBorder = (color)ColorToARGB(clrSlateGray, 32);

   SetHUDButton("LZ_HUD_BTN_MARK_ENTRY",
                contentX,
                buttonY,
                buttonW,
                HUD_DECISION_BUTTON_HEIGHT,
                (alreadyDecided && recordedAction == "MARCAR_ENTRADA" ? "ENTRADA REGISTRADA" : "MARCAR ENTRADA"),
                (buttonsEnabled ? enabledEntryBg : disabledBg),
                (buttonsEnabled ? enabledBorder : disabledBorder),
                (buttonsEnabled ? enabledText : disabledText),
                fontSize,
                buttonsEnabled);
   SetHUDButton("LZ_HUD_BTN_IGNORE",
                contentX + buttonW + buttonGap,
                buttonY,
                buttonW,
                HUD_DECISION_BUTTON_HEIGHT,
                (alreadyDecided && recordedAction == "IGNORAR" ? "EVENTO IGNORADO" : "IGNORAR"),
                (buttonsEnabled ? enabledIgnoreBg : disabledBg),
                (buttonsEnabled ? enabledBorder : disabledBorder),
                (buttonsEnabled ? enabledText : disabledText),
                fontSize,
                buttonsEnabled);

   string feedback = g_hud_decision_feedback;
   if (StringLen(feedback) == 0)
      feedback = (activeStatus ? "REGISTRO MANUAL EM CSV" : "AGUARDANDO NOVO EVENTO");
   SetHUDLabel("LZ_HUD_EVENT_FEEDBACK",
               contentX,
               decisionY + 95,
               HUDCompactDecisionText(feedback, 62),
               "Segoe UI",
               MathMax(7, fontSize - 1),
               labelColor);
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
   if (InpHUDDraggable && !g_hud_is_dragging && g_hud_user_moved)
      SyncHUDPositionFromObject();

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
   const string volumeBiasText = (state.hasVolume ? DirectionToText(state.volumeBiasDir) : "N/A");
   const string volumeConfirmText = PctToText(state.hasVolume, state.volumeConfirmPct);
   const string stepText = StepToText(state.step);
   const string stepSourceText = (state.step >= 0.0 && StringLen(state.stepSource) > 0 ? state.stepSource : "N/A");
   const string energyText = PctToText(InpEnableZoneEnergy && state.hasZoneEnergy, state.zoneEnergyPct);
   const string r2Text = DetailMetricText("R2", showDetails, state.r2);
   const string erText = DetailMetricText("ER", showDetails, state.er);
   const string sText = DetailMetricText("S", showDetails, state.slope01);
   const bool showVolumeDetails = (showDetails && InpShowVolumeDetails && state.hasVolume);
   const string volR2Text = DetailMetricText("VOL R2", showVolumeDetails, state.volumeR2);
   const string volRatioText = (showVolumeDetails ? StringFormat("VOL RATIO %.2f", state.volumeRatio) : "VOL RATIO N/A");
   const string volSText = DetailMetricText("VOL S", showVolumeDetails, state.volumeSlope01);

   const color shadowColor = (color)ColorToARGB(clrBlack, (uchar)ClampInt(15 + (alpha / 48), 15, 24));
   const color panelBgColor = (color)ColorToARGB(clrBlack, (uchar)ClampInt(38 + (alpha / 48), 38, 48));
   const color accentColor = (color)ColorToARGB(clrDeepSkyBlue, (uchar)ClampInt(134 + (alpha / 8), 134, 164));
   const color dividerTopColor = (color)ColorToARGB(clrDeepSkyBlue, 52);
   const color dividerColor = (color)ColorToARGB(clrSlateGray, 26);
   const color vDividerColor = (color)ColorToARGB(clrSlateGray, 18);
   const color titleColor = (color)ColorToARGB(clrWhiteSmoke, 235);
   const color badgeBgColor = (color)ColorToARGB(clrBlack, 68);
   const color badgeBorderColor = (color)ColorToARGB(clrSteelBlue, 34);
   const color badgeTextColor = (color)ColorToARGB(clrGainsboro, 214);
   const color iconBgColor = (color)ColorToARGB(clrNavy, 86);
   const color iconBarColor = (color)ColorToARGB(clrAliceBlue, 224);
   const color labelColor = (color)ColorToARGB(clrSilver, 166);
   const color neutralValueColor = (color)ColorToARGB(clrWhiteSmoke, 208);
   const color upColor = (color)ColorToARGB(clrSpringGreen, 214);
   const color downColor = (color)ColorToARGB(clrOrangeRed, 206);
   const color rangeColor = (color)ColorToARGB(clrDeepSkyBlue, 214);
   const color strengthColor = (color)ColorToARGB(clrDeepSkyBlue, 228);
   const color barBgColor = (color)ColorToARGB(clrSlateGray, 58);
   const color barFillColor = (color)ColorToARGB(clrDeepSkyBlue, 214);
   const color warnColor = (color)ColorToARGB(clrGold, 214);
   const color stepColor = (color)ColorToARGB(clrDeepSkyBlue, 224);
   const color stepSourceAccent = (color)ColorToARGB(clrMediumPurple, 204);
   const color energySoftColor = (color)ColorToARGB(clrLightSteelBlue, 196);
   const color detailsIconColor = (color)ColorToARGB(clrLightSteelBlue, 120);
   const color detailValueColor = (color)ColorToARGB(clrSilver, 162);

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
   const color volumeBiasColor = HUDDirectionColor((state.hasVolume ? state.volumeBiasDir : 0),
                                                   upColor,
                                                   downColor,
                                                   neutralValueColor);
   const color volumeConfirmColor = HUDBreakQualityColor(state.hasVolume,
                                                         state.volumeConfirmPct,
                                                         upColor,
                                                         warnColor,
                                                         downColor,
                                                         neutralValueColor);

   const int baseFont = MathMax(8, (int)MathRound((double)MathMax(6, InpHUDFontSize) * 0.80));
   const int labelFontSize = MathMax(7, baseFont - 1);
   const int valueFontSize = baseFont + 2;
   const int smallValueFontSize = baseFont + 1;
   const int middleMetricFontSize = MathMax(labelFontSize + 1, smallValueFontSize);
   const int strengthFontSize = baseFont + 4;
   const int titleFontSize = baseFont + 2;
   const int badgeFontSize = MathMax(7, baseFont - 1);
   const int detailFontSize = MathMax(7, baseFont - 1);
   const int decisionFontSize = MathMax(7, baseFont - 1);
   const int requiredMiddleGridH = HUDRequiredMiddleGridHeight(middleMetricFontSize);
   const int requiredFooterH = HUDRequiredFooterHeight(detailFontSize, showVolumeDetails);
   const int metricsPanelW = HUDResolvePanelWidth(exhaustText,
                                                  breakText,
                                                  volumeBiasText,
                                                  volumeConfirmText,
                                                  stepText,
                                                  stepSourceText,
                                                  energyText,
                                                  middleMetricFontSize);
   const int panelW = HUDResolveDecisionPanelWidth(metricsPanelW,
                                                   g_hud_decision_event,
                                                   decisionFontSize);
   const int panelH = MathMax(HUDBasePanelHeight(), HUDRequiredPanelHeight(requiredMiddleGridH, requiredFooterH));

   HUDRememberPanelSize(panelW, panelH);
   if (!g_hud_user_moved)
   {
      g_hud_x = HUDDefaultX(panelW);
      g_hud_y = HUDDefaultY();
   }
   ClampHUDPosition(panelW, panelH);
   EnsureHUDObjectsCreated();

   const int x = MathMax(0, g_hud_x);
   const int y = MathMax(0, g_hud_y);
   const int middleGridH = requiredMiddleGridH;
   const int footerH = requiredFooterH;

   const int headerY = y + HUD_TOP_PADDING;
   const int dividerTopY = headerY + HUD_HEADER_HEIGHT;
   const int topGridY = dividerTopY + HUD_DIVIDER_THICKNESS + HUD_SECTION_GAP;
   const int dividerMidY = topGridY + HUD_TOP_GRID_HEIGHT + HUD_SECTION_GAP;
   const int middleGridY = dividerMidY + HUD_DIVIDER_THICKNESS + HUD_SECTION_GAP;
   const int dividerBottomY = middleGridY + middleGridH + HUD_SECTION_GAP;
   const int footerY = dividerBottomY + HUD_DIVIDER_THICKNESS + HUD_SECTION_GAP;
   const int dividerEventY = footerY + footerH + HUD_SECTION_GAP;
   const int decisionY = dividerEventY + HUD_DIVIDER_THICKNESS + HUD_SECTION_GAP;

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
                   dividerTopColor,
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
                    vDividerColor,
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
                       volumeBiasText,
                       volumeConfirmText,
                       stepText,
                       stepSourceText,
                       energyText,
                       exhaustColor,
                       breakColor,
                       volumeBiasColor,
                       volumeConfirmColor,
                       stepColor,
                       stepSourceColor,
                       energyColor,
                       dividerColor,
                       vDividerColor,
                       middleMetricFontSize);
   RenderHUDFooter(x,
                   panelW,
                   footerY,
                   footerH,
                   r2Text,
                   erText,
                   sText,
                   showVolumeDetails,
                   volR2Text,
                   volRatioText,
                   volSText,
                   detailsIconColor,
                   labelColor,
                   detailValueColor,
                   labelFontSize,
                   detailFontSize);
   if (InpEnableDecisionEvents)
   {
      RenderHUDDecisionPanel(x,
                             panelW,
                             dividerEventY,
                             decisionY,
                             g_hud_decision_event,
                             dividerColor,
                             labelColor,
                             neutralValueColor,
                             upColor,
                             warnColor,
                             downColor,
                             decisionFontSize);
   }
}

#endif
