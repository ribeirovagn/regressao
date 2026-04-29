//+------------------------------------------------------------------+
//|                        MarketRegime.mq5 (v2.15)                  |
//|   MarketRegime (LR Close) + Zones (clusters)                     |
//+------------------------------------------------------------------+
#property copyright "Vagner Ribeiro"
#property link "https://www.mql5.com"
#property version "2.15"
#property strict

#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots 1

#property indicator_label1 "LateralMarker"
#property indicator_type1 DRAW_ARROW
#property indicator_color1 clrLimeGreen
#property indicator_width1 1

#include "Core/Types.mqh"

input int InpWindow = 240;

input ENUM_SLOPE_NORM_MODE InpSlopeNormMode = SLOPE_NORM_MEAN;

input double InpSlopeThresholdMean = 0.0001;
input double InpSlopeThresholdStd = 0.20;

input double InpR2Threshold = 0.05;

input double InpScoreSlopeWeight = 0.85;

input int InpMinZoneBars = 15;
input int InpGapTolerance = 1;

input bool InpExtendUntilBreak = true;
input double InpBreakMarginPoints = 50;

input int InpMaxZonesOnChart = 3;
input bool InpKeepArrows = true;
input bool InpDrawMidLine = false;

input int InpAlphaMin = 15;
input int InpAlphaMax = 50;
input int InpAlphaLenScale = 120;

input int InpBorderMinWidth = 1;
input int InpBorderMaxWidth = 4;

input bool InpOnlyLastActiveAndLastBroken = true;

input bool InpDrawProjectionLines = true;
input int InpProjectionCount = 10;
input bool InpProjectionIncludeZoneLevels = true;
input int InpProjectionLineWidth = 1;
input int InpProjectionLineAlpha = 10;
input color InpProjectionLineColor = clrGold;

input bool InpEnableTrendHUD = true;
input bool InpShowTrendDetails = true;
input bool InpShowBiasAndMicrotrend = true;
input int InpMicrotrendWindow = 30;
input bool InpHUDDraggable = true;
input bool InpHUDPersistPosition = true;
input bool InpHUDResetSavedPosition = false;
input int InpHUDXDefault = 12;
input int InpHUDYDefault = 12;
input int InpHUDFontSize = 8;
input int InpHUDWidth = 384;
input int InpHUDHeight = 192;
input int InpHUDAlphaMin = 170;
input int InpHUDAlphaMax = 255;
input int InpBarHeight = 7;
input int InpBarMarginX = 10;
input int InpBarMarginBottom = 10;
input double InpTrendThreshold = 0.60;
input double InpTrendWeightSlope = 0.40;
input double InpTrendWeightR2 = 0.40;
input double InpTrendWeightER = 0.20;

input bool InpEnableTrendExhaustion = true;
input int InpExhaustLookback = 20;
input double InpExhaustDistanceScale = 3.0;
input double InpExhaustWeightDistance = 0.45;
input double InpExhaustWeightStrength = 0.30;
input double InpExhaustWeightNoise = 0.25;

input bool InpEnableBreakQuality = true;
input double InpBreakQualityWeightStrength = 0.35;
input double InpBreakQualityWeightEnergy = 0.30;
input double InpBreakQualityWeightPenetr = 0.20;
input double InpBreakQualityWeightFresh = 0.15;

input bool InpEnableVolumeConfirmation = true;
input int InpVolumeWindowShort = 20;
input int InpVolumeWindowLong = 60;
input double InpVolumeWeightSlope = 0.40;
input double InpVolumeWeightR2 = 0.20;
input double InpVolumeWeightRatio = 0.40;
input double InpVolumeRatioScale = 1.5;
input double InpVolumeSlopeThreshold = 0.10;
input bool InpShowVolumeDetails = false;

input bool InpEnableZoneEnergy = true;
input int InpZoneEnergyLenScale = 120;
input int InpZoneEnergyTouchMarginPoints = 30;
input int InpZoneEnergyTouchScale = 12;
input double InpZoneEnergyWeightLen = 0.30;
input double InpZoneEnergyWeightComp = 0.35;
input double InpZoneEnergyWeightChop = 0.20;
input double InpZoneEnergyWeightTouch = 0.15;

input bool InpDebug = false;

input int InpOnCalculateDelaySeconds = 5;

double MarkerBuffer[];
double ScoreBuffer[];
double FlagBuffer[];
double SlopeNormBuffer[];
double R2Buffer[];
double DummyBuffer[];

int g_hud_corner = CORNER_LEFT_UPPER;
int g_hud_x = 12;
int g_hud_y = 12;
int g_hud_panel_w = 0;
int g_hud_panel_h = 0;
bool g_hud_is_dragging = false;
bool g_hud_user_moved = false;
string g_hud_key_x = "";
string g_hud_key_y = "";
string g_hud_key_moved = "";

#include "Core/Utils.mqh"
#include "Stats/LinearRegression.mqh"
#include "Stats/TrendStrength.mqh"
#include "Stats/TrendExhaustion.mqh"
#include "Stats/BreakQuality.mqh"
#include "Stats/VolumeConfirmation.mqh"
#include "Stats/ZoneEnergy.mqh"
#include "Zones/ZoneDetector.mqh"
#include "Zones/ZoneRenderer.mqh"
#include "Zones/ProjectionRenderer.mqh"
#include "HUD/HUDLayout.mqh"
#include "HUD/HUDDragController.mqh"
#include "HUD/HUDRenderer.mqh"

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
   if (InpVolumeWindowShort < 2)
      return INIT_PARAMETERS_INCORRECT;
   if (InpVolumeWindowLong < 2)
      return INIT_PARAMETERS_INCORRECT;
   if (InpVolumeRatioScale <= 0.0)
      return INIT_PARAMETERS_INCORRECT;
   if (InpVolumeSlopeThreshold <= 0.0)
      return INIT_PARAMETERS_INCORRECT;
   if (InpOnCalculateDelaySeconds < 0)
      return INIT_PARAMETERS_INCORRECT;

   BuildHUDStorageKeys();
   if (InpHUDResetSavedPosition)
      ClearSavedHUDPosition();

   LoadHUDPosition();
   const int panelW = HUDPanelWidth();
   const int panelH = HUDPanelHeight();
   ClampHUDPosition(panelW, panelH);
   if (InpHUDPersistPosition && g_hud_user_moved)
      SaveHUDPosition();
   g_hud_corner = CORNER_LEFT_UPPER;
   g_hud_is_dragging = false;

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

   IndicatorSetString(INDICATOR_SHORTNAME, "MarketRegime Zones (v2.15)");
   return INIT_SUCCEEDED;
}

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

   const int delaySeconds = MathMax(InpOnCalculateDelaySeconds, 0);
   if (delaySeconds > 0)
   {
      const ulong nowMs = GetTickCount64();
      const ulong delayMs = (ulong)delaySeconds * 1000ULL;
      if (last_exec_ms != 0 && (nowMs - last_exec_ms) < delayMs)
         return prev_calculated;
      last_exec_ms = nowMs;
   }

   if (rates_total < InpWindow)
      return rates_total;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);

   const int window = InpWindow;
   const int lastValid = rates_total - window;
   if (lastValid < 0)
      return rates_total;

   const double slopeThreshold = GetSlopeThreshold(InpSlopeNormMode, InpSlopeThresholdMean, InpSlopeThresholdStd);

   ClearWarmupBuffers(rates_total, lastValid, MarkerBuffer, ScoreBuffer, FlagBuffer, SlopeNormBuffer, R2Buffer);
   ComputeLRRegimeBuffers(rates_total,
                          lastValid,
                          window,
                          high,
                          low,
                          close,
                          eps,
                          slopeThreshold,
                          InpSlopeNormMode,
                          InpSlopeThresholdMean,
                          InpSlopeThresholdStd,
                          InpR2Threshold,
                          InpScoreSlopeWeight,
                          InpKeepArrows,
                          MarkerBuffer,
                          ScoreBuffer,
                          FlagBuffer,
                          SlopeNormBuffer,
                          R2Buffer);

   ZoneInfo renderZones[];
   int renderZoneCount = 0;
   ZoneSelectionState zoneState;
   DetectZones(lastValid,
               time,
               high,
               low,
               close,
               FlagBuffer,
               ScoreBuffer,
               _Point,
               InpMinZoneBars,
               InpGapTolerance,
               InpExtendUntilBreak,
               InpBreakMarginPoints,
               InpEnableZoneEnergy,
               InpZoneEnergyTouchMarginPoints,
               InpOnlyLastActiveAndLastBroken,
               InpMaxZonesOnChart,
               InpDebug,
               renderZones,
               renderZoneCount,
               zoneState);

   ClearZoneObjects();
   RenderZones(renderZones,
               renderZoneCount,
               InpDrawMidLine,
               InpAlphaMin,
               InpAlphaMax,
               InpAlphaLenScale,
               InpBorderMinWidth,
               InpBorderMaxWidth);
   RenderProjectionSelection(InpOnlyLastActiveAndLastBroken,
                             zoneState.hasProjectionZone,
                             zoneState.projectionZone,
                             InpDrawProjectionLines,
                             InpProjectionCount,
                             InpProjectionIncludeZoneLevels,
                             InpProjectionLineWidth,
                             InpProjectionLineAlpha,
                             InpProjectionLineColor,
                             InpDebug);

   bool hasZoneEnergy = false;
   double zoneEnergy01 = 0.0;
   int zoneEnergyPct = 0;
   if (InpEnableZoneEnergy && zoneState.lastActive.valid)
   {
      hasZoneEnergy = ComputeZoneEnergy(zoneState.lastActive,
                                        zoneState.lastActiveNetClose,
                                        eps,
                                        InpZoneEnergyLenScale,
                                        InpZoneEnergyTouchScale,
                                        InpZoneEnergyWeightLen,
                                        InpZoneEnergyWeightComp,
                                        InpZoneEnergyWeightChop,
                                        InpZoneEnergyWeightTouch,
                                        zoneEnergy01,
                                        zoneEnergyPct);
   }

   bool hasBrokenZoneEnergy = false;
   double brokenZoneEnergy01 = 0.0;
   int brokenZoneEnergyPct = 0;
   if (InpEnableZoneEnergy && zoneState.lastBroken.valid)
   {
      hasBrokenZoneEnergy = ComputeZoneEnergy(zoneState.lastBroken,
                                              zoneState.lastBrokenNetClose,
                                              eps,
                                              InpZoneEnergyLenScale,
                                              InpZoneEnergyTouchScale,
                                              InpZoneEnergyWeightLen,
                                              InpZoneEnergyWeightComp,
                                              InpZoneEnergyWeightChop,
                                              InpZoneEnergyWeightTouch,
                                              brokenZoneEnergy01,
                                              brokenZoneEnergyPct);
   }

   ObjectDelete(0, "LZ_TREND_BG");

   TrendState trendState;
   ComputeTrendState(FlagBuffer[0],
                     zoneState.lastActive.valid,
                     close,
                     window,
                     MathMax(2, InpMicrotrendWindow),
                     MathMax(2, InpExhaustLookback),
                     eps,
                     InpSlopeNormMode,
                     InpSlopeThresholdMean,
                     InpSlopeThresholdStd,
                     InpTrendWeightSlope,
                     InpTrendWeightR2,
                     InpTrendWeightER,
                     InpTrendThreshold,
                     trendState);

   double hudStep = -1.0;
   double hudMid = 0.0;
   string hudStepSource = "N/A";
   ResolveHUDStepFromZones(zoneState, hudStep, hudMid, hudStepSource);

   bool hasTrendExhaustion = false;
   double trendExhaustion01 = 0.0;
   int trendExhaustionPct = 0;
   if (trendState.shortMetrics.valid)
   {
      hasTrendExhaustion = ComputeTrendExhaustion(close[0],
                                                  hudMid,
                                                  hudStep,
                                                  trendState.strength01,
                                                  trendState.shortStrength01,
                                                  trendState.shortMetrics.er,
                                                  eps,
                                                  InpExhaustDistanceScale,
                                                  InpExhaustWeightDistance,
                                                  InpExhaustWeightStrength,
                                                  InpExhaustWeightNoise,
                                                  trendExhaustion01,
                                                  trendExhaustionPct);
   }

   bool hasBreakQuality = false;
   int breakQualityPct = 0;
   if (zoneState.lastBroken.valid)
   {
      hasBreakQuality = ComputeBreakQuality(zoneState.lastBroken,
                                            close[0],
                                            trendState.strength01,
                                            hasBrokenZoneEnergy,
                                            brokenZoneEnergy01,
                                            hasTrendExhaustion,
                                            trendExhaustion01,
                                            eps,
                                            InpBreakQualityWeightStrength,
                                            InpBreakQualityWeightEnergy,
                                            InpBreakQualityWeightPenetr,
                                            InpBreakQualityWeightFresh,
                                            breakQualityPct);
   }

   VolumeState volumeState;
   const bool hasVolume = (InpEnableVolumeConfirmation &&
                           ComputeVolumeConfirmationAtIndex(0,
                                                            tick_volume,
                                                            eps,
                                                            MathMax(2, InpVolumeWindowShort),
                                                            MathMax(2, InpVolumeWindowLong),
                                                            InpVolumeSlopeThreshold,
                                                            InpVolumeWeightSlope,
                                                            InpVolumeWeightR2,
                                                            InpVolumeWeightRatio,
                                                            InpVolumeRatioScale,
                                                            volumeState));

   HUDState hudState;
   hudState.regime = trendState.regime;
   hudState.biasDir = trendState.biasDir;
   hudState.microDir = trendState.microDir;
   hudState.strength01 = trendState.strength01;
   hudState.hasTrendExhaustion = (InpEnableTrendExhaustion && hasTrendExhaustion);
   hudState.trendExhaustionPct = trendExhaustionPct;
   hudState.hasBreakQuality = (InpEnableBreakQuality && hasBreakQuality);
   hudState.breakQualityPct = breakQualityPct;
   hudState.step = hudStep;
   hudState.stepSource = hudStepSource;
   hudState.r2 = trendState.mainMetrics.r2;
   hudState.er = trendState.mainMetrics.er;
   hudState.slope01 = trendState.slope01;
   hudState.hasZoneEnergy = hasZoneEnergy;
   hudState.zoneEnergyPct = zoneEnergyPct;
   hudState.hasVolume = hasVolume;
   hudState.volumeBiasDir = (hasVolume ? volumeState.bias : 0);
   hudState.volumeConfirmPct = (hasVolume ? ClampInt((int)MathRound(volumeState.confirmation01 * 100.0), 0, 100) : 0);
   hudState.volumeR2 = (hasVolume ? volumeState.r2 : 0.0);
   hudState.volumeRatio = (hasVolume ? volumeState.ratio : 0.0);
   hudState.volumeSlope01 = (hasVolume ? volumeState.slope01 : 0.0);

   if (InpEnableTrendHUD)
      RenderTrendHUD(hudState);
   else
      DeleteTrendHUD();

   return rates_total;
}

void OnDeinit(const int reason)
{
   DeleteTrendHUD();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   HandleHUDChartEvent(id, sparam);
}
//+------------------------------------------------------------------+
