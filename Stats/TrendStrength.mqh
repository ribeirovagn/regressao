#ifndef MARKETREGIME_STATS_TRENDSTRENGTH_MQH
#define MARKETREGIME_STATS_TRENDSTRENGTH_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "LinearRegression.mqh"

double GetSlopeThreshold(const ENUM_SLOPE_NORM_MODE normMode,
                         const double slopeThresholdMean,
                         const double slopeThresholdStd)
{
   if (normMode == SLOPE_NORM_MEAN)
      return (slopeThresholdMean > 0.0 ? slopeThresholdMean : 0.0001);
   return (slopeThresholdStd > 0.0 ? slopeThresholdStd : 0.20);
}

int DirectionFromSlope(const double b_norm, const double eps)
{
   if (b_norm > eps)
      return 1;
   if (b_norm < -eps)
      return -1;
   return 0;
}

double ComputeTrendStrength(const double b_norm,
                            const double r2,
                            const double er,
                            const double slopeThreshold,
                            double trendWeightSlope,
                            double trendWeightR2,
                            double trendWeightER)
{
   const double slope01 = Clamp01((slopeThreshold > 0.0) ? (MathAbs(b_norm) / slopeThreshold) : 0.0);

   double wSlope = MathMax(0.0, trendWeightSlope);
   double wR2 = MathMax(0.0, trendWeightR2);
   double wER = MathMax(0.0, trendWeightER);
   NormalizeWeights3(wSlope, wR2, wER);

   return Clamp01(wSlope * slope01 + wR2 * Clamp01(r2) + wER * Clamp01(er));
}

ENUM_REGIME_STATE ResolveRegimeState(const double currentFlag,
                                     const bool hasActiveZone,
                                     const double trendStrength,
                                     const double trendThreshold)
{
   if (currentFlag == 1.0 || hasActiveZone)
      return REGIME_RANGE;
   if (trendStrength >= Clamp01(trendThreshold))
      return REGIME_TREND;
   return REGIME_MIXED;
}

void ResetTrendState(TrendState &state)
{
   ResetLRMetrics(state.mainMetrics);
   ResetLRMetrics(state.microMetrics);
   ResetLRMetrics(state.shortMetrics);
   state.slope01 = 0.0;
   state.strength01 = 0.0;
   state.shortStrength01 = 0.0;
   state.biasDir = 0;
   state.microDir = 0;
   state.regime = REGIME_MIXED;
}

void ComputeTrendStateAtIndex(const int index,
                              const double currentFlag,
                              const bool hasActiveZone,
                              const double &close[],
                              const int mainWindow,
                              const int microWindow,
                              const int shortWindow,
                              const double eps,
                              const ENUM_SLOPE_NORM_MODE normMode,
                              const double slopeThresholdMean,
                              const double slopeThresholdStd,
                              const double trendWeightSlope,
                              const double trendWeightR2,
                              const double trendWeightER,
                              const double trendThreshold,
                              TrendState &state);

void ComputeTrendState(const double currentFlag,
                       const bool hasActiveZone,
                       const double &close[],
                       const int mainWindow,
                       const int microWindow,
                       const int shortWindow,
                       const double eps,
                       const ENUM_SLOPE_NORM_MODE normMode,
                       const double slopeThresholdMean,
                       const double slopeThresholdStd,
                       const double trendWeightSlope,
                       const double trendWeightR2,
                       const double trendWeightER,
                       const double trendThreshold,
                       TrendState &state)
{
   ComputeTrendStateAtIndex(0,
                            currentFlag,
                            hasActiveZone,
                            close,
                            mainWindow,
                            microWindow,
                            shortWindow,
                            eps,
                            normMode,
                            slopeThresholdMean,
                            slopeThresholdStd,
                            trendWeightSlope,
                            trendWeightR2,
                            trendWeightER,
                            trendThreshold,
                            state);
}

void ComputeTrendStateAtIndex(const int index,
                              const double currentFlag,
                              const bool hasActiveZone,
                              const double &close[],
                              const int mainWindow,
                              const int microWindow,
                              const int shortWindow,
                              const double eps,
                              const ENUM_SLOPE_NORM_MODE normMode,
                              const double slopeThresholdMean,
                              const double slopeThresholdStd,
                              const double trendWeightSlope,
                              const double trendWeightR2,
                              const double trendWeightER,
                              const double trendThreshold,
                              TrendState &state)
{
   ResetTrendState(state);

   const double slopeThreshold = GetSlopeThreshold(normMode, slopeThresholdMean, slopeThresholdStd);

   if (ComputeLRMetricsAtIndex(index,
                               mainWindow,
                               close,
                               eps,
                               normMode,
                               slopeThresholdMean,
                               slopeThresholdStd,
                               state.mainMetrics.b_norm,
                               state.mainMetrics.r2,
                               state.mainMetrics.er))
   {
      state.mainMetrics.valid = true;
      state.slope01 = Clamp01((slopeThreshold > 0.0) ? (MathAbs(state.mainMetrics.b_norm) / slopeThreshold) : 0.0);
      state.strength01 = ComputeTrendStrength(state.mainMetrics.b_norm,
                                              state.mainMetrics.r2,
                                              state.mainMetrics.er,
                                              slopeThreshold,
                                              trendWeightSlope,
                                              trendWeightR2,
                                              trendWeightER);
      state.biasDir = DirectionFromSlope(state.mainMetrics.b_norm, eps);
   }

   if (ComputeLRMetricsAtIndex(index,
                               microWindow,
                               close,
                               eps,
                               normMode,
                               slopeThresholdMean,
                               slopeThresholdStd,
                               state.microMetrics.b_norm,
                               state.microMetrics.r2,
                               state.microMetrics.er))
   {
      state.microMetrics.valid = true;
      state.microDir = DirectionFromSlope(state.microMetrics.b_norm, eps);
   }

   if (ComputeLRMetricsAtIndex(index,
                               shortWindow,
                               close,
                               eps,
                               normMode,
                               slopeThresholdMean,
                               slopeThresholdStd,
                               state.shortMetrics.b_norm,
                               state.shortMetrics.r2,
                               state.shortMetrics.er))
   {
      state.shortMetrics.valid = true;
      state.shortStrength01 = ComputeTrendStrength(state.shortMetrics.b_norm,
                                                   state.shortMetrics.r2,
                                                   state.shortMetrics.er,
                                                   slopeThreshold,
                                                   trendWeightSlope,
                                                   trendWeightR2,
                                                   trendWeightER);
   }

   state.regime = ResolveRegimeState(currentFlag, hasActiveZone, state.strength01, trendThreshold);
}

#endif
