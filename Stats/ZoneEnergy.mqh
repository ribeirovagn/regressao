#ifndef MARKETREGIME_STATS_ZONEENERGY_MQH
#define MARKETREGIME_STATS_ZONEENERGY_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

bool ComputeZoneEnergy(const ZoneInfo &z,
                       const double zoneNetClose,
                       const double eps,
                       const int zoneEnergyLenScale,
                       const int zoneEnergyTouchScale,
                       double weightLen,
                       double weightComp,
                       double weightChop,
                       double weightTouch,
                       double &zoneEnergy01,
                       int &zoneEnergyPct)
{
   zoneEnergy01 = 0.0;
   zoneEnergyPct = 0;
   if (!z.valid)
      return false;

   double wLen = weightLen;
   double wComp = weightComp;
   double wChop = weightChop;
   double wTouch = weightTouch;
   NormalizeWeights4(wLen, wComp, wChop, wTouch);

   const int lenScale = MathMax(1, zoneEnergyLenScale);
   const int touchScale = MathMax(1, zoneEnergyTouchScale);
   const double len01 = Clamp01((double)z.length / (double)lenScale);
   const double range = MathMax(0.0, z.top - z.bottom);
   const double path = MathMax(z.path, eps);
   const double compression01 = Clamp01(1.0 - (range / path));
   const double erZone = Clamp01(zoneNetClose / path);
   const double chop01 = Clamp01(1.0 - erZone);
   const int touches = z.touchTop + z.touchBot;
   const double touches01 = Clamp01((double)touches / (double)touchScale);

   zoneEnergy01 = Clamp01(wLen * len01 + wComp * compression01 + wChop * chop01 + wTouch * touches01);
   zoneEnergyPct = ClampInt((int)MathRound(zoneEnergy01 * 100.0), 0, 100);
   return true;
}

#endif
