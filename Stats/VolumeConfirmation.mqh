#ifndef MARKETREGIME_STATS_VOLUMECONFIRMATION_MQH
#define MARKETREGIME_STATS_VOLUMECONFIRMATION_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

int VolumeBiasFromSlope(const double b_norm, const double eps)
{
   if (b_norm > eps)
      return 1;
   if (b_norm < -eps)
      return -1;
   return 0;
}

void ResetVolumeState(VolumeState &state)
{
   state.valid = false;
   state.bias = 0;
   state.confirmation01 = 0.0;
   state.b_norm = 0.0;
   state.r2 = 0.0;
   state.ratio = 0.0;
   state.slope01 = 0.0;
}

bool ComputeVolumeAverageAtIndex(const int i,
                                 const int window,
                                 const long &tick_volume[],
                                 const double eps,
                                 double &mean_volume)
{
   mean_volume = 0.0;

   const int total = ArraySize(tick_volume);
   if (i < 0 || window < 1 || total <= 0 || (i + window) > total)
      return false;

   double sum_volume = 0.0;
   for (int k = 0; k < window; ++k)
      sum_volume += (double)tick_volume[i + k];

   mean_volume = sum_volume / (double)window;
   return (mean_volume > eps);
}

bool ComputeVolumeLRMetricsAtIndex(const int i,
                                   const int window,
                                   const long &tick_volume[],
                                   const double eps,
                                   double &b_norm,
                                   double &r2,
                                   double &mean_volume)
{
   b_norm = 0.0;
   r2 = 0.0;
   mean_volume = 0.0;

   const int total = ArraySize(tick_volume);
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
      const double y = (double)tick_volume[i + (window - 1 - k)];
      sum_y += y;
      sum_xy += (double)k * y;
      sum_y2 += y * y;
   }

   mean_volume = sum_y / n;
   if (mean_volume <= eps)
      return false;

   const double b = (n * sum_xy - sum_x * sum_y) / denom;
   b_norm = b / mean_volume;

   const double ss_tot = sum_y2 - (sum_y * sum_y) / n;
   if (ss_tot > eps)
   {
      const double a = (sum_y - b * sum_x) / n;
      double ss_res = 0.0;
      for (int k = 0; k < window; ++k)
      {
         const double yhat = a + b * (double)k;
         const double y = (double)tick_volume[i + (window - 1 - k)];
         const double err = y - yhat;
         ss_res += err * err;
      }
      r2 = Clamp01(1.0 - (ss_res / ss_tot));
   }

   return true;
}

bool ComputeVolumeConfirmationAtIndex(const int i,
                                      const long &tick_volume[],
                                      const double eps,
                                      const int shortWindow,
                                      const int longWindow,
                                      const double slopeThreshold,
                                      double weightSlope,
                                      double weightR2,
                                      double weightRatio,
                                      const double ratioScale,
                                      VolumeState &state)
{
   ResetVolumeState(state);

   if (shortWindow < 2 || longWindow < 2 || slopeThreshold <= 0.0 || ratioScale <= 0.0)
      return false;

   double b_norm = 0.0;
   double r2 = 0.0;
   double mean_short = 0.0;
   if (!ComputeVolumeLRMetricsAtIndex(i, shortWindow, tick_volume, eps, b_norm, r2, mean_short))
      return false;

   double mean_long = 0.0;
   if (!ComputeVolumeAverageAtIndex(i, longWindow, tick_volume, eps, mean_long))
      return false;

   NormalizeWeights3(weightSlope, weightR2, weightRatio);

   const double ratio = mean_short / MathMax(mean_long, eps);
   const double slope01 = Clamp01(MathAbs(b_norm) / slopeThreshold);
   const double ratio01 = Clamp01(ratio / ratioScale);
   const double confirmation01 = Clamp01(weightSlope * slope01 +
                                         weightR2 * Clamp01(r2) +
                                         weightRatio * ratio01);

   state.valid = true;
   state.bias = VolumeBiasFromSlope(b_norm, eps);
   state.confirmation01 = confirmation01;
   state.b_norm = b_norm;
   state.r2 = r2;
   state.ratio = ratio;
   state.slope01 = slope01;
   return true;
}

#endif
