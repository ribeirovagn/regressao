#ifndef MARKETREGIME_STATS_BREAKQUALITY_MQH
#define MARKETREGIME_STATS_BREAKQUALITY_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

bool ComputeBreakQuality(const ZoneInfo &brokenZone,
                         const double currentClose,
                         const double trendStrength,
                         const bool hasBrokenZoneEnergy,
                         const double brokenZoneEnergy01,
                         const bool hasTrendExhaustion,
                         const double trendExhaustion01,
                         const double eps,
                         double weightStrength,
                         double weightEnergy,
                         double weightPenetr,
                         double weightFresh,
                         int &breakQualityPct)
{
   breakQualityPct = 0;
   if (!brokenZone.valid)
      return false;

   const double brokenStep = MathMax(brokenZone.top - brokenZone.bottom, 0.0);
   int breakDir = 0;
   if (brokenZone.state == Z_BREAK_UP)
      breakDir = 1;
   else if (brokenZone.state == Z_BREAK_DOWN)
      breakDir = -1;

   if (brokenStep <= eps || breakDir == 0)
      return false;

   const double breakStrength01 = Clamp01(trendStrength);
   const double breakEnergy01 = (hasBrokenZoneEnergy ? brokenZoneEnergy01 : 0.0);

   double penetration = 0.0;
   if (breakDir > 0)
      penetration = currentClose - brokenZone.top;
   else
      penetration = brokenZone.bottom - currentClose;

   const double penetration01 = Clamp01(penetration / MathMax(brokenStep, eps));
   const double freshness01 = (hasTrendExhaustion ? Clamp01(1.0 - trendExhaustion01) : 1.0);

   double wStrength = weightStrength;
   double wEnergy = weightEnergy;
   double wPenetr = weightPenetr;
   double wFresh = weightFresh;
   NormalizeWeights4(wStrength, wEnergy, wPenetr, wFresh);

   const double breakQuality01 = Clamp01(wStrength * breakStrength01 +
                                         wEnergy * breakEnergy01 +
                                         wPenetr * penetration01 +
                                         wFresh * freshness01);
   breakQualityPct = ClampInt((int)MathRound(breakQuality01 * 100.0), 0, 100);
   return true;
}

#endif
