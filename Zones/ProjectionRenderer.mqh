#ifndef MARKETREGIME_ZONES_PROJECTIONRENDERER_MQH
#define MARKETREGIME_ZONES_PROJECTIONRENDERER_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

void DrawHLine(const string name, const double price, const color c, const int width)
{
   if (ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

void DrawProjectionFromZone(const ZoneInfo &z,
                            const bool drawProjectionLines,
                            const int projectionCount,
                            const bool projectionIncludeZoneLevels,
                            const int projectionLineWidth,
                            const int projectionLineAlpha,
                            const color projectionLineColor,
                            const bool debug)
{
   if (!drawProjectionLines || !z.valid)
      return;

   DeleteByPrefix("LZ_LVL_");

   const double step = (z.top - z.bottom);
   if (step <= 0.0)
      return;

   const int cnt = MathMax(1, projectionCount);
   const int w = MathMax(1, projectionLineWidth);
   const uchar a = (uchar)ClampInt(projectionLineAlpha, 0, 255);

   const color cMid = (color)ColorToARGB(projectionLineColor, a);
   const color cUp = (color)ColorToARGB(clrLimeGreen, a);
   const color cDn = (color)ColorToARGB(clrDarkOrange, a);

   int idx = 0;

   if (projectionIncludeZoneLevels)
   {
      DrawHLine(StringFormat("LZ_LVL_%d_TOP", idx++), z.top, cUp, w);
      DrawHLine(StringFormat("LZ_LVL_%d_MID", idx++), z.mid, cMid, w);
      DrawHLine(StringFormat("LZ_LVL_%d_BOT", idx++), z.bottom, cDn, w);
   }

   for (int k = 1; k <= cnt; ++k)
   {
      DrawHLine(StringFormat("LZ_LVL_%d_UP_%d", idx++, k), z.top + step * k, cUp, w);
      DrawHLine(StringFormat("LZ_LVL_%d_DN_%d", idx++, k), z.bottom - step * k, cDn, w);
   }

   if (debug)
      PrintFormat("[LZ] Projection step=%.5f cnt=%d (from zone top=%.5f bot=%.5f)",
                  step,
                  cnt,
                  z.top,
                  z.bottom);
}

void RenderProjectionSelection(const bool onlyLastActiveAndLastBroken,
                               const bool hasProjectionZone,
                               const ZoneInfo &projectionZone,
                               const bool drawProjectionLines,
                               const int projectionCount,
                               const bool projectionIncludeZoneLevels,
                               const int projectionLineWidth,
                               const int projectionLineAlpha,
                               const color projectionLineColor,
                               const bool debug)
{
   if (onlyLastActiveAndLastBroken)
   {
      if (hasProjectionZone)
      {
         DrawProjectionFromZone(projectionZone,
                                drawProjectionLines,
                                projectionCount,
                                projectionIncludeZoneLevels,
                                projectionLineWidth,
                                projectionLineAlpha,
                                projectionLineColor,
                                debug);
      }
      else
      {
         DeleteByPrefix("LZ_LVL_");
      }
      return;
   }

   DeleteByPrefix("LZ_LVL_");
}

#endif
