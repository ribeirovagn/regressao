#ifndef MARKETREGIME_CORE_STATEENGINE_MQH
#define MARKETREGIME_CORE_STATEENGINE_MQH

#include "Types.mqh"
#include "Utils.mqh"
#include "../Stats/LinearRegression.mqh"
#include "../Stats/TrendStrength.mqh"
#include "../Stats/TrendExhaustion.mqh"
#include "../Stats/BreakQuality.mqh"
#include "../Stats/VolumeConfirmation.mqh"
#include "../Stats/ZoneEnergy.mqh"
#include "../Zones/ZoneDetector.mqh"

void ResetStateEngineConfig(StateEngineConfig &config)
{
   config.window = 240;
   config.microtrendWindow = 30;
   config.shortWindow = 20;
   config.slopeNormMode = SLOPE_NORM_MEAN;
   config.slopeThresholdMean = 0.0001;
   config.slopeThresholdStd = 0.20;
   config.r2Threshold = 0.05;
   config.scoreSlopeWeight = 0.85;
   config.minZoneBars = 15;
   config.gapTolerance = 1;
   config.extendUntilBreak = true;
   config.breakMarginPoints = 50.0;
   config.trendThreshold = 0.60;
   config.trendWeightSlope = 0.40;
   config.trendWeightR2 = 0.40;
   config.trendWeightER = 0.20;
   config.enableTrendExhaustion = true;
   config.exhaustDistanceScale = 3.0;
   config.exhaustWeightDistance = 0.45;
   config.exhaustWeightStrength = 0.30;
   config.exhaustWeightNoise = 0.25;
   config.enableBreakQuality = true;
   config.enableZoneEnergy = true;
   config.zoneEnergyLenScale = 120;
   config.zoneEnergyTouchMarginPoints = 30;
   config.zoneEnergyTouchScale = 12;
   config.zoneEnergyWeightLen = 0.30;
   config.zoneEnergyWeightComp = 0.35;
   config.zoneEnergyWeightChop = 0.20;
   config.zoneEnergyWeightTouch = 0.15;
   config.breakQualityWeightStrength = 0.35;
   config.breakQualityWeightEnergy = 0.30;
   config.breakQualityWeightPenetr = 0.20;
   config.breakQualityWeightFresh = 0.15;
   config.enableVolumeConfirmation = true;
   config.volumeWindowShort = 20;
   config.volumeWindowLong = 60;
   config.volumeWeightSlope = 0.40;
   config.volumeWeightR2 = 0.20;
   config.volumeWeightRatio = 0.40;
   config.volumeRatioScale = 1.5;
   config.volumeSlopeThreshold = 0.10;
   config.showVolumeDetails = false;
}

void InitializeStateEngineConfig(StateEngineConfig &config,
                                 const int window)
{
   ResetStateEngineConfig(config);
   config.window = MathMax(2, window);
}

void ResetStateSnapshot(StateSnapshot &snapshot)
{
   snapshot.valid = false;
   snapshot.regime = REGIME_MIXED;
   snapshot.biasDir = 0;
   snapshot.microDir = 0;
   snapshot.hasStrength = false;
   snapshot.strength01 = 0.0;
   snapshot.hasExhaustion = false;
   snapshot.exhaustion01 = 0.0;
   snapshot.hasBreakQuality = false;
   snapshot.breakQuality01 = 0.0;
   snapshot.hasStep = false;
   snapshot.step = -1.0;
   snapshot.stepMid = 0.0;
   snapshot.stepSource = STEP_SOURCE_NONE;
   snapshot.hasZoneEnergy = false;
   snapshot.zoneEnergy01 = 0.0;
   snapshot.hasActiveZone = false;
   snapshot.hasBrokenZone = false;
   snapshot.slope01 = 0.0;
   snapshot.hasVolume = false;
   ResetVolumeState(snapshot.volumeState);
   ResetLRMetrics(snapshot.mainMetrics);
   ResetLRMetrics(snapshot.microMetrics);
   ResetLRMetrics(snapshot.shortMetrics);
   ResetZoneInfo(snapshot.lastActive);
   ResetZoneInfo(snapshot.lastBroken);
}

bool PrepareStateWindowContext(const int ratesTotal,
                               const datetime &time[],
                               const double &high[],
                               const double &low[],
                               const double &close[],
                               const double point,
                               const double eps,
                               const StateEngineConfig &config,
                               double &flagBuffer[],
                               double &scoreBuffer[],
                               ZoneInfo &zoneCatalog[],
                               int &zoneCount,
                               int &lastValid)
{
   ArrayResize(flagBuffer, 0);
   ArrayResize(scoreBuffer, 0);
   ArrayResize(zoneCatalog, 0);
   zoneCount = 0;
   lastValid = -1;

   if (ratesTotal <= 0 || config.window < 2)
      return false;

   lastValid = ratesTotal - config.window;
   if (lastValid < 0)
      return false;

   ArrayResize(flagBuffer, ratesTotal);
   ArrayResize(scoreBuffer, ratesTotal);

   double markerBuffer[];
   double slopeNormBuffer[];
   double r2Buffer[];
   ArrayResize(markerBuffer, ratesTotal);
   ArrayResize(slopeNormBuffer, ratesTotal);
   ArrayResize(r2Buffer, ratesTotal);

   ArrayInitialize(flagBuffer, 0.0);
   ArrayInitialize(scoreBuffer, EMPTY_VALUE);
   ArrayInitialize(markerBuffer, EMPTY_VALUE);
   ArrayInitialize(slopeNormBuffer, EMPTY_VALUE);
   ArrayInitialize(r2Buffer, EMPTY_VALUE);

   ComputeLRRegimeBuffers(ratesTotal,
                          lastValid,
                          config.window,
                          high,
                          low,
                          close,
                          eps,
                          GetSlopeThreshold(config.slopeNormMode, config.slopeThresholdMean, config.slopeThresholdStd),
                          config.slopeNormMode,
                          config.slopeThresholdMean,
                          config.slopeThresholdStd,
                          config.r2Threshold,
                          config.scoreSlopeWeight,
                          false,
                          markerBuffer,
                          scoreBuffer,
                          flagBuffer,
                          slopeNormBuffer,
                          r2Buffer);

   BuildZoneCatalog(lastValid,
                    time,
                    high,
                    low,
                    close,
                    flagBuffer,
                    scoreBuffer,
                    point,
                    config.minZoneBars,
                    config.gapTolerance,
                    config.extendUntilBreak,
                    config.breakMarginPoints,
                    config.enableZoneEnergy,
                    config.zoneEnergyTouchMarginPoints,
                    false,
                    zoneCatalog,
                    zoneCount);

   return true;
}

bool ComputeStateSnapshotFromSelection(const int index,
                                       const double &close[],
                                       const long &tick_volume[],
                                       const double currentFlag,
                                       const ZoneSelectionState &zoneState,
                                       const double eps,
                                       const StateEngineConfig &config,
                                       StateSnapshot &snapshot)
{
   ResetStateSnapshot(snapshot);

   const int total = ArraySize(close);
   if (index < 0 || index >= total)
      return false;

   TrendState trendState;
   ComputeTrendStateAtIndex(index,
                            currentFlag,
                            zoneState.lastActive.valid,
                            close,
                            MathMax(2, config.window),
                            MathMax(2, config.microtrendWindow),
                            MathMax(2, config.shortWindow),
                            eps,
                            config.slopeNormMode,
                            config.slopeThresholdMean,
                            config.slopeThresholdStd,
                            config.trendWeightSlope,
                            config.trendWeightR2,
                            config.trendWeightER,
                            config.trendThreshold,
                            trendState);

   if (!trendState.mainMetrics.valid)
      return false;

   snapshot.valid = true;
   snapshot.regime = trendState.regime;
   snapshot.biasDir = trendState.biasDir;
   snapshot.microDir = trendState.microDir;
   snapshot.hasStrength = true;
   snapshot.strength01 = trendState.strength01;
   snapshot.hasActiveZone = zoneState.lastActive.valid;
   snapshot.hasBrokenZone = zoneState.lastBroken.valid;
   snapshot.slope01 = trendState.slope01;
   snapshot.mainMetrics = trendState.mainMetrics;
   snapshot.microMetrics = trendState.microMetrics;
   snapshot.shortMetrics = trendState.shortMetrics;
   snapshot.lastActive = zoneState.lastActive;
   snapshot.lastBroken = zoneState.lastBroken;
   snapshot.hasVolume = (config.enableVolumeConfirmation &&
                         ComputeVolumeConfirmationAtIndex(index,
                                                          tick_volume,
                                                          eps,
                                                          MathMax(2, config.volumeWindowShort),
                                                          MathMax(2, config.volumeWindowLong),
                                                          config.volumeSlopeThreshold,
                                                          config.volumeWeightSlope,
                                                          config.volumeWeightR2,
                                                          config.volumeWeightRatio,
                                                          config.volumeRatioScale,
                                                          snapshot.volumeState));

   ResolveStepFromZones(zoneState, snapshot.step, snapshot.stepMid, snapshot.stepSource);
   snapshot.hasStep = (snapshot.step > eps);

   if (config.enableZoneEnergy && snapshot.hasActiveZone)
   {
      int zoneEnergyPct = 0;
      snapshot.hasZoneEnergy = ComputeZoneEnergy(snapshot.lastActive,
                                                 zoneState.lastActiveNetClose,
                                                 eps,
                                                 config.zoneEnergyLenScale,
                                                 config.zoneEnergyTouchScale,
                                                 config.zoneEnergyWeightLen,
                                                 config.zoneEnergyWeightComp,
                                                 config.zoneEnergyWeightChop,
                                                 config.zoneEnergyWeightTouch,
                                                 snapshot.zoneEnergy01,
                                                 zoneEnergyPct);
   }

   if (config.enableTrendExhaustion && trendState.shortMetrics.valid && snapshot.hasStep)
   {
      int trendExhaustionPct = 0;
      snapshot.hasExhaustion = ComputeTrendExhaustion(close[index],
                                                      snapshot.stepMid,
                                                      snapshot.step,
                                                      trendState.strength01,
                                                      trendState.shortStrength01,
                                                      trendState.shortMetrics.er,
                                                      eps,
                                                      config.exhaustDistanceScale,
                                                      config.exhaustWeightDistance,
                                                      config.exhaustWeightStrength,
                                                      config.exhaustWeightNoise,
                                                      snapshot.exhaustion01,
                                                      trendExhaustionPct);
   }

   bool hasBrokenZoneEnergy = false;
   double brokenZoneEnergy01 = 0.0;
   if (config.enableZoneEnergy && snapshot.hasBrokenZone)
   {
      int brokenZoneEnergyPct = 0;
      hasBrokenZoneEnergy = ComputeZoneEnergy(snapshot.lastBroken,
                                              zoneState.lastBrokenNetClose,
                                              eps,
                                              config.zoneEnergyLenScale,
                                              config.zoneEnergyTouchScale,
                                              config.zoneEnergyWeightLen,
                                              config.zoneEnergyWeightComp,
                                              config.zoneEnergyWeightChop,
                                              config.zoneEnergyWeightTouch,
                                              brokenZoneEnergy01,
                                              brokenZoneEnergyPct);
   }

   if (config.enableBreakQuality && snapshot.hasBrokenZone)
   {
      int breakQualityPct = 0;
      snapshot.hasBreakQuality = ComputeBreakQuality(snapshot.lastBroken,
                                                     close[index],
                                                     trendState.strength01,
                                                     hasBrokenZoneEnergy,
                                                     brokenZoneEnergy01,
                                                     snapshot.hasExhaustion,
                                                     snapshot.exhaustion01,
                                                     eps,
                                                     config.breakQualityWeightStrength,
                                                     config.breakQualityWeightEnergy,
                                                     config.breakQualityWeightPenetr,
                                                     config.breakQualityWeightFresh,
                                                     snapshot.breakQuality01,
                                                     breakQualityPct);
   }

   return true;
}

bool ComputeStateSnapshotAtIndex(const int index,
                                 const int lastValid,
                                 const datetime &time[],
                                 const double &high[],
                                 const double &low[],
                                 const double &close[],
                                 const long &tick_volume[],
                                 const double &flagBuffer[],
                                 const double &scoreBuffer[],
                                 const double point,
                                 const double eps,
                                 const StateEngineConfig &config,
                                 StateSnapshot &snapshot)
{
   if (index < 0 || index >= ArraySize(flagBuffer) || index > lastValid)
   {
      ResetStateSnapshot(snapshot);
      return false;
   }

   ZoneSelectionState zoneState;
   SelectZonesAtIndexFromBuffers(index,
                                 lastValid,
                                 time,
                                 high,
                                 low,
                                 close,
                                 flagBuffer,
                                 scoreBuffer,
                                 point,
                                 config.minZoneBars,
                                 config.gapTolerance,
                                 config.extendUntilBreak,
                                 config.breakMarginPoints,
                                 config.enableZoneEnergy,
                                 config.zoneEnergyTouchMarginPoints,
                                 false,
                                 zoneState);
   return ComputeStateSnapshotFromSelection(index,
                                            close,
                                            tick_volume,
                                            flagBuffer[index],
                                            zoneState,
                                            eps,
                                            config,
                                            snapshot);
}

void BuildHUDStateFromSnapshot(const StateSnapshot &snapshot,
                               HUDState &hudState)
{
   hudState.regime = snapshot.regime;
   hudState.biasDir = snapshot.biasDir;
   hudState.microDir = snapshot.microDir;
   hudState.strength01 = snapshot.strength01;
   hudState.hasTrendExhaustion = snapshot.hasExhaustion;
   hudState.trendExhaustionPct = (snapshot.hasExhaustion ? ClampInt((int)MathRound(snapshot.exhaustion01 * 100.0), 0, 100) : 0);
   hudState.hasBreakQuality = snapshot.hasBreakQuality;
   hudState.breakQualityPct = (snapshot.hasBreakQuality ? ClampInt((int)MathRound(snapshot.breakQuality01 * 100.0), 0, 100) : 0);
   hudState.step = (snapshot.hasStep ? snapshot.step : -1.0);
   hudState.stepSource = StepSourceToString(snapshot.stepSource);
   hudState.r2 = snapshot.mainMetrics.r2;
   hudState.er = snapshot.mainMetrics.er;
   hudState.slope01 = snapshot.slope01;
   hudState.hasZoneEnergy = snapshot.hasZoneEnergy;
   hudState.zoneEnergyPct = (snapshot.hasZoneEnergy ? ClampInt((int)MathRound(snapshot.zoneEnergy01 * 100.0), 0, 100) : 0);
   hudState.hasVolume = snapshot.hasVolume;
   hudState.volumeBiasDir = (snapshot.hasVolume ? snapshot.volumeState.bias : 0);
   hudState.volumeConfirmPct = (snapshot.hasVolume ? ClampInt((int)MathRound(snapshot.volumeState.confirmation01 * 100.0), 0, 100) : 0);
   hudState.volumeR2 = (snapshot.hasVolume ? snapshot.volumeState.r2 : 0.0);
   hudState.volumeRatio = (snapshot.hasVolume ? snapshot.volumeState.ratio : 0.0);
   hudState.volumeSlope01 = (snapshot.hasVolume ? snapshot.volumeState.slope01 : 0.0);
}

#endif
