#ifndef MARKETREGIME_STATS_TRENDEXHAUSTION_MQH
#define MARKETREGIME_STATS_TRENDEXHAUSTION_MQH

#include "../Core/Utils.mqh"

bool ComputeTrendExhaustion(const double currentClose,
                            const double zoneMid,
                            const double zoneStep,
                            const double trendStrength,
                            const double shortTrendStrength,
                            const double shortER,
                            const double eps,
                            const double exhaustDistanceScale,
                            double weightDistance,
                            double weightStrength,
                            double weightNoise,
                            double &trendExhaustion01,
                            int &trendExhaustionPct)
{
   trendExhaustion01 = 0.0;
   trendExhaustionPct = 0;

   if (zoneStep <= eps)
      return false;

   const double distanceSteps = MathAbs(currentClose - zoneMid) / MathMax(zoneStep, eps);
   const double distance01 = Clamp01(distanceSteps / MathMax(exhaustDistanceScale, eps));
   const double strengthDrop01 = Clamp01(MathMax(0.0, trendStrength - shortTrendStrength));
   const double noise01 = Clamp01(1.0 - shortER);

   double wDist = weightDistance;
   double wStrength = weightStrength;
   double wNoise = weightNoise;
   NormalizeWeights3(wDist, wStrength, wNoise);

   trendExhaustion01 = Clamp01(wDist * distance01 + wStrength * strengthDrop01 + wNoise * noise01);
   trendExhaustionPct = ClampInt((int)MathRound(trendExhaustion01 * 100.0), 0, 100);
   return true;
}

#endif
