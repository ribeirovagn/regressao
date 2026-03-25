#ifndef MARKETREGIME_ZONES_ZONERENDERER_MQH
#define MARKETREGIME_ZONES_ZONERENDERER_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

string ZoneRectName(const int idx, const datetime t1, const datetime t2)
{
   return StringFormat("LZ_RECT_%d_%I64d_%I64d", idx, (long)t1, (long)t2);
}

string ZoneMidName(const int idx, const datetime t1, const datetime t2)
{
   return StringFormat("LZ_MID_%d_%I64d_%I64d", idx, (long)t1, (long)t2);
}

color ZoneBaseColor(const ENUM_ZONE_STATE st)
{
   if (st == Z_BREAK_UP)
      return clrLimeGreen;
   if (st == Z_BREAK_DOWN)
      return clrTomato;
   return clrDodgerBlue;
}

uchar ComputeAlphaByLen(const int len,
                        const int alphaMinInput,
                        const int alphaMaxInput,
                        const int alphaLenScaleInput)
{
   int aMin = ClampInt(alphaMinInput, 0, 255);
   int aMax = ClampInt(alphaMaxInput, 0, 255);
   if (aMax < aMin)
   {
      int t = aMin;
      aMin = aMax;
      aMax = t;
   }

   int scale = MathMax(alphaLenScaleInput, 1);
   double t = (double)len / (double)scale;
   if (t > 1.0)
      t = 1.0;

   int alpha = (int)MathRound(aMin + (aMax - aMin) * t);
   alpha = ClampInt(alpha, 0, 255);
   return (uchar)alpha;
}

int ComputeBorderWidthByScore(const double avgScore,
                              const int borderMinWidthInput,
                              const int borderMaxWidthInput)
{
   int wMin = MathMax(borderMinWidthInput, 1);
   int wMax = MathMax(borderMaxWidthInput, wMin);

   double s = Clamp01(avgScore);
   int w = (int)MathRound(wMin + (wMax - wMin) * s);
   return ClampInt(w, wMin, wMax);
}

void DrawZone(const int idx,
              const ZoneInfo &z,
              const bool drawMidLine,
              const int alphaMin,
              const int alphaMax,
              const int alphaLenScale,
              const int borderMinWidth,
              const int borderMaxWidth)
{
   if (!z.valid)
      return;

   uchar alpha = ComputeAlphaByLen(z.length, alphaMin, alphaMax, alphaLenScale);
   int width = ComputeBorderWidthByScore(z.avgScore, borderMinWidth, borderMaxWidth);
   color base = ZoneBaseColor(z.state);
   color c = (color)ColorToARGB(base, alpha);

   string rect = ZoneRectName(idx, z.t_left, z.t_right);
   if (ObjectCreate(0, rect, OBJ_RECTANGLE, 0, z.t_left, z.top, z.t_right, z.bottom))
   {
      ObjectSetInteger(0, rect, OBJPROP_COLOR, c);
      ObjectSetInteger(0, rect, OBJPROP_BACK, true);
      ObjectSetInteger(0, rect, OBJPROP_FILL, true);
      ObjectSetInteger(0, rect, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, rect, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, rect, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rect, OBJPROP_HIDDEN, true);
   }

   if (drawMidLine)
   {
      string mid = ZoneMidName(idx, z.t_left, z.t_right);
      if (ObjectCreate(0, mid, OBJ_TREND, 0, z.t_left, z.mid, z.t_right, z.mid))
      {
         ObjectSetInteger(0, mid, OBJPROP_COLOR, (color)ColorToARGB(clrSilver, (uchar)ClampInt(alpha + 40, 0, 255)));
         ObjectSetInteger(0, mid, OBJPROP_WIDTH, MathMax(1, width));
         ObjectSetInteger(0, mid, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, mid, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, mid, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, mid, OBJPROP_BACK, true);
         ObjectSetInteger(0, mid, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, mid, OBJPROP_HIDDEN, true);
      }
   }
}

void ClearZoneObjects()
{
   DeleteByPrefix("LZ_RECT_");
   DeleteByPrefix("LZ_MID_");
}

void RenderZones(const ZoneInfo &zones[],
                 const int zoneCount,
                 const bool drawMidLine,
                 const int alphaMin,
                 const int alphaMax,
                 const int alphaLenScale,
                 const int borderMinWidth,
                 const int borderMaxWidth)
{
   for (int i = 0; i < zoneCount; ++i)
   {
      DrawZone(i,
               zones[i],
               drawMidLine,
               alphaMin,
               alphaMax,
               alphaLenScale,
               borderMinWidth,
               borderMaxWidth);
   }
}

#endif
