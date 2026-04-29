#ifndef MARKETREGIME_CORE_UTILS_MQH
#define MARKETREGIME_CORE_UTILS_MQH

#include "Types.mqh"

double Clamp01(const double v)
{
   return (v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v));
}

int ClampInt(const int v, const int lo, const int hi)
{
   return (v < lo ? lo : (v > hi ? hi : v));
}

string RegimeToString(const ENUM_REGIME_STATE regime)
{
   if (regime == REGIME_RANGE)
      return "RANGE";
   if (regime == REGIME_TREND)
      return "TREND";
   return "MIXED";
}

string DirectionToString(const int direction)
{
   if (direction > 0)
      return "UP";
   if (direction < 0)
      return "DOWN";
   return "NEUTRAL";
}

string StepSourceToString(const ENUM_STEP_SOURCE source)
{
   if (source == STEP_SOURCE_ACTIVE)
      return "ACTIVE";
   if (source == STEP_SOURCE_LAST_BROKEN)
      return "LAST BROKEN";
   return "N/A";
}

string TimeframeToString(const ENUM_TIMEFRAMES timeframe)
{
   switch (timeframe)
   {
      case PERIOD_M1: return "M1";
      case PERIOD_M2: return "M2";
      case PERIOD_M3: return "M3";
      case PERIOD_M4: return "M4";
      case PERIOD_M5: return "M5";
      case PERIOD_M6: return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1: return "H1";
      case PERIOD_H2: return "H2";
      case PERIOD_H3: return "H3";
      case PERIOD_H4: return "H4";
      case PERIOD_H6: return "H6";
      case PERIOD_H8: return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1: return "D1";
      case PERIOD_W1: return "W1";
      case PERIOD_MN1: return "MN1";
   }

   return IntegerToString((int)timeframe);
}

void NormalizeWeights3(double &w1,
                       double &w2,
                       double &w3)
{
   w1 = MathMax(0.0, w1);
   w2 = MathMax(0.0, w2);
   w3 = MathMax(0.0, w3);

   double wSum = w1 + w2 + w3;
   if (wSum <= 0.0)
   {
      w1 = (1.0 / 3.0);
      w2 = (1.0 / 3.0);
      w3 = (1.0 / 3.0);
      return;
   }

   w1 /= wSum;
   w2 /= wSum;
   w3 /= wSum;
}

void NormalizeWeights4(double &w1,
                       double &w2,
                       double &w3,
                       double &w4)
{
   w1 = MathMax(0.0, w1);
   w2 = MathMax(0.0, w2);
   w3 = MathMax(0.0, w3);
   w4 = MathMax(0.0, w4);

   double wSum = w1 + w2 + w3 + w4;
   if (wSum <= 0.0)
   {
      w1 = 0.25;
      w2 = 0.25;
      w3 = 0.25;
      w4 = 0.25;
      return;
   }

   w1 /= wSum;
   w2 /= wSum;
   w3 /= wSum;
   w4 /= wSum;
}

void DeleteByPrefix(const string prefix)
{
   int total = ObjectsTotal(0, 0, -1);
   for (int i = total - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if (StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

long HashMix(const long h, const long v)
{
   return (h ^ v) * 1099511628211;
}

long PriceToKey(const double price)
{
   if (_Point > 0.0)
      return (long)MathRound(price / _Point);
   return (long)MathRound(price * 100000000.0);
}

long BuildZoneHash(const ZoneInfo &z)
{
   long h = 1469598103934665603;
   if (!z.valid)
      return HashMix(h, -1);

   h = HashMix(h, 1);
   h = HashMix(h, (long)z.t_left);
   h = HashMix(h, (long)z.t_right);
   h = HashMix(h, PriceToKey(z.top));
   h = HashMix(h, PriceToKey(z.bottom));
   h = HashMix(h, (long)z.state);
   h = HashMix(h, (long)z.length);
   return h;
}

long HashZone(const ZoneInfo &z)
{
   return BuildZoneHash(z);
}

long BuildRenderSignature(const ZoneInfo &mostRecent,
                          const ZoneInfo &lastActive,
                          const ZoneInfo &lastBroken,
                          const int drawnCount,
                          const bool hasProjection,
                          const bool onlyLastActiveAndLastBroken)
{
   long h = 1469598103934665603;
   h = HashMix(h, HashZone(mostRecent));
   h = HashMix(h, HashZone(lastActive));
   h = HashMix(h, HashZone(lastBroken));
   h = HashMix(h, (long)drawnCount);
   h = HashMix(h, (hasProjection ? 1 : 0));
   h = HashMix(h, (onlyLastActiveAndLastBroken ? 1 : 0));
   return h;
}

#endif
