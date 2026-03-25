#ifndef MARKETREGIME_ZONES_ZONEDETECTOR_MQH
#define MARKETREGIME_ZONES_ZONEDETECTOR_MQH

#include "../Core/Types.mqh"

void ResetZoneInfo(ZoneInfo &z)
{
   z.valid = false;
   z.t_left = 0;
   z.t_right = 0;
   z.top = 0.0;
   z.bottom = 0.0;
   z.mid = 0.0;
   z.length = 0;
   z.avgScore = 0.0;
   z.path = 0.0;
   z.touchTop = 0;
   z.touchBot = 0;
   z.state = Z_ACTIVE;
}

void ResetZoneSelectionState(ZoneSelectionState &state)
{
   ResetZoneInfo(state.lastActive);
   ResetZoneInfo(state.lastBroken);
   ResetZoneInfo(state.projectionZone);
   state.lastActiveNetClose = 0.0;
   state.lastBrokenNetClose = 0.0;
   state.hasProjectionZone = false;
}

void AppendZoneToRenderList(const ZoneInfo &z,
                            ZoneInfo &renderZones[],
                            int &renderZoneCount)
{
   ArrayResize(renderZones, renderZoneCount + 1);
   renderZones[renderZoneCount] = z;
   renderZoneCount++;
}

void ResolveHUDStepFromZones(const ZoneSelectionState &state,
                             double &hudStep,
                             double &hudMid,
                             string &hudStepSource)
{
   hudStep = -1.0;
   hudMid = 0.0;
   hudStepSource = "N/A";

   if (state.lastActive.valid)
   {
      hudStep = state.lastActive.top - state.lastActive.bottom;
      hudMid = state.lastActive.mid;
      hudStepSource = "ACTIVE";
   }
   else if (state.lastBroken.valid)
   {
      hudStep = state.lastBroken.top - state.lastBroken.bottom;
      hudMid = state.lastBroken.mid;
      hudStepSource = "LAST BROKEN";
   }
}

void DetectZones(const int lastValid,
                 const datetime &time[],
                 const double &high[],
                 const double &low[],
                 const double &close[],
                 const double &flagBuffer[],
                 const double &scoreBuffer[],
                 const double point,
                 const int minZoneBars,
                 const int gapTolerance,
                 const bool extendUntilBreak,
                 const double breakMarginPoints,
                 const bool enableZoneEnergy,
                 const int zoneEnergyTouchMarginPoints,
                 const bool onlyLastActiveAndLastBroken,
                 const int maxZonesOnChart,
                 const bool debug,
                 ZoneInfo &renderZones[],
                 int &renderZoneCount,
                 ZoneSelectionState &selectionState)
{
   ArrayResize(renderZones, 0);
   renderZoneCount = 0;
   ResetZoneSelectionState(selectionState);

   const double touchMargin = MathMax(0, zoneEnergyTouchMarginPoints) * point;

   int i = 0;
   while (i <= lastValid)
   {
      if (flagBuffer[i] == 1.0)
      {
         int startRecent = i;
         int gap = 0;

         while (i <= lastValid)
         {
            if (flagBuffer[i] == 1.0)
               gap = 0;
            else
               gap++;

            if (gap > gapTolerance)
               break;
            i++;
         }

         int endOld = i - gap;
         int length = endOld - startRecent + 1;

         if (length >= minZoneBars)
         {
            double top = -DBL_MAX;
            double bottom = DBL_MAX;
            double sumScore = 0.0;
            int cntScore = 0;
            double path = 0.0;

            for (int j = startRecent; j <= endOld; ++j)
            {
               if (high[j] > top)
                  top = high[j];
               if (low[j] < bottom)
                  bottom = low[j];

               if (j < endOld)
                  path += MathAbs(close[j] - close[j + 1]);

               double sc = scoreBuffer[j];
               if (sc != EMPTY_VALUE)
               {
                  sumScore += sc;
                  cntScore++;
               }
            }

            int touchTop = 0;
            int touchBot = 0;
            if (enableZoneEnergy)
            {
               for (int j = startRecent; j <= endOld; ++j)
               {
                  if (high[j] >= top - touchMargin)
                     touchTop++;
                  if (low[j] <= bottom + touchMargin)
                     touchBot++;
               }
            }

            ZoneInfo z;
            z.valid = true;
            z.top = top;
            z.bottom = bottom;
            z.mid = (top + bottom) * 0.5;
            z.length = length;
            z.avgScore = (cntScore > 0 ? (sumScore / (double)cntScore) : 0.0);
            z.path = path;
            z.touchTop = touchTop;
            z.touchBot = touchBot;
            z.t_left = time[endOld];
            z.t_right = time[startRecent];
            z.state = Z_ACTIVE;

            if (extendUntilBreak)
            {
               const double margin = breakMarginPoints * point;

               for (int j = startRecent - 1; j >= 0; --j)
               {
                  if (close[j] > top + margin)
                  {
                     z.state = Z_BREAK_UP;
                     z.t_right = time[j];
                     break;
                  }

                  if (close[j] < bottom - margin)
                  {
                     z.state = Z_BREAK_DOWN;
                     z.t_right = time[j];
                     break;
                  }
               }
            }

            if (onlyLastActiveAndLastBroken)
            {
               if (!selectionState.lastActive.valid && z.state == Z_ACTIVE)
               {
                  selectionState.lastActive = z;
                  selectionState.lastActiveNetClose = MathAbs(close[startRecent] - close[endOld]);
               }

               if (!selectionState.lastBroken.valid && z.state != Z_ACTIVE)
               {
                  selectionState.lastBroken = z;
                  selectionState.lastBrokenNetClose = MathAbs(close[startRecent] - close[endOld]);
               }

               if (selectionState.lastActive.valid && selectionState.lastBroken.valid)
                  break;
            }
            else
            {
               AppendZoneToRenderList(z, renderZones, renderZoneCount);
               if (renderZoneCount >= maxZonesOnChart)
                  break;
            }

            if (debug)
               PrintFormat("[LZ] len=%d avgScore=%.2f state=%d", z.length, z.avgScore, (int)z.state);
         }
      }
      else
      {
         i++;
      }
   }

   if (onlyLastActiveAndLastBroken)
   {
      if (selectionState.lastActive.valid)
      {
         AppendZoneToRenderList(selectionState.lastActive, renderZones, renderZoneCount);
         selectionState.projectionZone = selectionState.lastActive;
         selectionState.hasProjectionZone = true;
      }

      if (selectionState.lastBroken.valid)
      {
         AppendZoneToRenderList(selectionState.lastBroken, renderZones, renderZoneCount);
         if (!selectionState.hasProjectionZone)
         {
            selectionState.projectionZone = selectionState.lastBroken;
            selectionState.hasProjectionZone = true;
         }
      }
   }
}

#endif
