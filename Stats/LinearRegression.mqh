#ifndef MARKETREGIME_STATS_LINEARREGRESSION_MQH
#define MARKETREGIME_STATS_LINEARREGRESSION_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

void ResetLRMetrics(LRMetrics &metrics)
{
   metrics.valid = false;
   metrics.b_norm = 0.0;
   metrics.r2 = 0.0;
   metrics.er = 0.0;
}

bool ComputeLRMetricsAtIndex(const int i,
                             const int window,
                             const double &close[],
                             const double eps,
                             const ENUM_SLOPE_NORM_MODE normMode,
                             const double slopeThresholdMean,
                             const double slopeThresholdStd,
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

   if (normMode == SLOPE_NORM_MEAN)
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

bool ComputeCurrentLRMetrics(const int window,
                             const double &close[],
                             const double eps,
                             const ENUM_SLOPE_NORM_MODE normMode,
                             const double slopeThresholdMean,
                             const double slopeThresholdStd,
                             LRMetrics &metrics)
{
   ResetLRMetrics(metrics);

   double b_norm = 0.0;
   double r2 = 0.0;
   double er = 0.0;
   if (!ComputeLRMetricsAtIndex(0,
                                window,
                                close,
                                eps,
                                normMode,
                                slopeThresholdMean,
                                slopeThresholdStd,
                                b_norm,
                                r2,
                                er))
   {
      return false;
   }

   metrics.valid = true;
   metrics.b_norm = b_norm;
   metrics.r2 = r2;
   metrics.er = er;
   return true;
}

void ClearWarmupBuffers(const int rates_total,
                        const int last_valid,
                        double &markerBuffer[],
                        double &scoreBuffer[],
                        double &flagBuffer[],
                        double &slopeNormBuffer[],
                        double &r2Buffer[])
{
   for (int i = rates_total - 1; i > last_valid; --i)
   {
      markerBuffer[i] = EMPTY_VALUE;
      scoreBuffer[i] = EMPTY_VALUE;
      flagBuffer[i] = 0.0;
      slopeNormBuffer[i] = EMPTY_VALUE;
      r2Buffer[i] = EMPTY_VALUE;
   }
}

void ComputeLRRegimeBuffers(const int rates_total,
                            const int last_valid,
                            const int window,
                            const double &high[],
                            const double &low[],
                            const double &close[],
                            const double eps,
                            const double slopeThreshold,
                            const ENUM_SLOPE_NORM_MODE normMode,
                            const double slopeThresholdMean,
                            const double slopeThresholdStd,
                            const double r2Threshold,
                            const double scoreSlopeWeight,
                            const bool keepArrows,
                            double &markerBuffer[],
                            double &scoreBuffer[],
                            double &flagBuffer[],
                            double &slopeNormBuffer[],
                            double &r2Buffer[])
{
   const double wSlope = Clamp01(scoreSlopeWeight);
   const double wR2 = 1.0 - wSlope;

   for (int i = last_valid; i >= 0; --i)
   {
      double b_norm = 0.0;
      double r2 = 0.0;
      double er = 0.0;
      if (!ComputeLRMetricsAtIndex(i,
                                   window,
                                   close,
                                   eps,
                                   normMode,
                                   slopeThresholdMean,
                                   slopeThresholdStd,
                                   b_norm,
                                   r2,
                                   er))
      {
         slopeNormBuffer[i] = EMPTY_VALUE;
         r2Buffer[i] = EMPTY_VALUE;
         flagBuffer[i] = 0.0;
         scoreBuffer[i] = EMPTY_VALUE;
         markerBuffer[i] = EMPTY_VALUE;
         continue;
      }

      slopeNormBuffer[i] = b_norm;
      r2Buffer[i] = r2;

      const bool lateral = (MathAbs(b_norm) < slopeThreshold && r2 < r2Threshold);
      flagBuffer[i] = lateral ? 1.0 : 0.0;

      const double s1 = 1.0 - MathMin(1.0, MathAbs(b_norm) / slopeThreshold);
      const double s2 = 1.0 - MathMin(1.0, r2 / r2Threshold);
      const double score = Clamp01(wSlope * s1 + wR2 * s2);
      scoreBuffer[i] = score;

      if (keepArrows && lateral)
      {
         double offset = (high[i] - low[i]) * 0.25;
         if (offset <= eps)
            offset = MathMax(_Point * 10.0, MathAbs(close[i]) * 0.0001);
         markerBuffer[i] = high[i] + offset;
      }
      else
      {
         markerBuffer[i] = EMPTY_VALUE;
      }
   }
}

#endif
