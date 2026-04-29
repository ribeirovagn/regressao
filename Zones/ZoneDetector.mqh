#ifndef MARKETREGIME_ZONES_ZONEDETECTOR_MQH
#define MARKETREGIME_ZONES_ZONEDETECTOR_MQH

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

void ResetZoneInfo(ZoneInfo &z)
{
   z.valid = false;
   z.t_left = 0;
   z.t_right = 0;
   z.t_cluster_right = 0;
   z.t_break = 0;
   z.top = 0.0;
   z.bottom = 0.0;
   z.mid = 0.0;
   z.length = 0;
   z.avgScore = 0.0;
   z.path = 0.0;
   z.netClose = 0.0;
   z.touchTop = 0;
   z.touchBot = 0;
   z.startIndex = -1;
   z.endIndex = -1;
   z.breakIndex = -1;
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

void FinalizeProjectionZone(ZoneSelectionState &state)
{
   ResetZoneInfo(state.projectionZone);
   state.hasProjectionZone = false;

   if (state.lastActive.valid)
   {
      state.projectionZone = state.lastActive;
      state.hasProjectionZone = true;
   }
   else if (state.lastBroken.valid)
   {
      state.projectionZone = state.lastBroken;
      state.hasProjectionZone = true;
   }
}

void ResolveStepFromZones(const ZoneSelectionState &state,
                          double &step,
                          double &mid,
                          ENUM_STEP_SOURCE &stepSource)
{
   step = -1.0;
   mid = 0.0;
   stepSource = STEP_SOURCE_NONE;

   if (state.lastActive.valid)
   {
      step = state.lastActive.top - state.lastActive.bottom;
      mid = state.lastActive.mid;
      stepSource = STEP_SOURCE_ACTIVE;
   }
   else if (state.lastBroken.valid)
   {
      step = state.lastBroken.top - state.lastBroken.bottom;
      mid = state.lastBroken.mid;
      stepSource = STEP_SOURCE_LAST_BROKEN;
   }
}

void ResolveHUDStepFromZones(const ZoneSelectionState &state,
                             double &hudStep,
                             double &hudMid,
                             string &hudStepSource)
{
   ENUM_STEP_SOURCE stepSource = STEP_SOURCE_NONE;
   ResolveStepFromZones(state, hudStep, hudMid, stepSource);
   hudStepSource = StepSourceToString(stepSource);
}

bool BuildZoneFromCluster(const int startRecent,
                          const int endOld,
                          const int breakoutSearchStart,
                          const datetime &time[],
                          const double &high[],
                          const double &low[],
                          const double &close[],
                          const double &scoreBuffer[],
                          const double point,
                          const double touchMargin,
                          const bool extendUntilBreak,
                          const double breakMarginPoints,
                          const bool enableZoneEnergy,
                          ZoneInfo &z)
{
   ResetZoneInfo(z);

   const int length = endOld - startRecent + 1;
   if (length < 1)
      return false;

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

   z.valid = true;
   z.top = top;
   z.bottom = bottom;
   z.mid = (top + bottom) * 0.5;
   z.length = length;
   z.avgScore = (cntScore > 0 ? (sumScore / (double)cntScore) : 0.0);
   z.path = path;
   z.netClose = MathAbs(close[startRecent] - close[endOld]);
   z.touchTop = touchTop;
   z.touchBot = touchBot;
   z.startIndex = startRecent;
   z.endIndex = endOld;
   z.breakIndex = -1;
   z.t_left = time[endOld];
   z.t_cluster_right = time[startRecent];
   z.t_right = z.t_cluster_right;
   z.state = Z_ACTIVE;

   if (extendUntilBreak)
   {
      const double margin = breakMarginPoints * point;

      for (int j = startRecent - 1; j >= breakoutSearchStart; --j)
      {
         if (close[j] > top + margin)
         {
            z.state = Z_BREAK_UP;
            z.breakIndex = j;
            z.t_break = time[j];
            z.t_right = z.t_break;
            break;
         }

         if (close[j] < bottom - margin)
         {
            z.state = Z_BREAK_DOWN;
            z.breakIndex = j;
            z.t_break = time[j];
            z.t_right = z.t_break;
            break;
         }
      }
   }

   return true;
}

void BuildZoneCatalog(const int lastValid,
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
                      const bool debug,
                      ZoneInfo &zoneCatalog[],
                      int &zoneCount)
{
   ArrayResize(zoneCatalog, 0);
   zoneCount = 0;

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
            ZoneInfo z;
            if (BuildZoneFromCluster(startRecent,
                                     endOld,
                                     0,
                                     time,
                                     high,
                                     low,
                                     close,
                                     scoreBuffer,
                                     point,
                                     touchMargin,
                                     extendUntilBreak,
                                     breakMarginPoints,
                                     enableZoneEnergy,
                                     z))
            {
               AppendZoneToRenderList(z, zoneCatalog, zoneCount);

               if (debug)
                  PrintFormat("[LZ] len=%d avgScore=%.2f state=%d", z.length, z.avgScore, (int)z.state);
            }
         }
      }
      else
      {
         i++;
      }
   }
}

bool ResolveZoneAtIndex(const int presentIndex,
                        const ZoneInfo &catalogZone,
                        ZoneInfo &resolvedZone)
{
   ResetZoneInfo(resolvedZone);

   if (!catalogZone.valid)
      return false;
   if (presentIndex > catalogZone.startIndex)
      return false;

   resolvedZone = catalogZone;
   resolvedZone.state = Z_ACTIVE;
   resolvedZone.t_right = catalogZone.t_cluster_right;

   if (catalogZone.breakIndex >= 0 && presentIndex <= catalogZone.breakIndex)
   {
      resolvedZone.state = catalogZone.state;
      resolvedZone.t_right = catalogZone.t_break;
   }

   return true;
}

void SelectZonesAtIndex(const int presentIndex,
                        const ZoneInfo &zoneCatalog[],
                        const int zoneCount,
                        ZoneSelectionState &selectionState)
{
   ResetZoneSelectionState(selectionState);

   for (int idx = 0; idx < zoneCount; ++idx)
   {
      ZoneInfo resolvedZone;
      if (!ResolveZoneAtIndex(presentIndex, zoneCatalog[idx], resolvedZone))
         continue;

      if (!selectionState.lastActive.valid && resolvedZone.state == Z_ACTIVE)
      {
         selectionState.lastActive = resolvedZone;
         selectionState.lastActiveNetClose = resolvedZone.netClose;
      }

      if (!selectionState.lastBroken.valid && resolvedZone.state != Z_ACTIVE)
      {
         selectionState.lastBroken = resolvedZone;
         selectionState.lastBrokenNetClose = resolvedZone.netClose;
      }

      if (selectionState.lastActive.valid && selectionState.lastBroken.valid)
         break;
   }

   FinalizeProjectionZone(selectionState);
}

void SelectZonesAtIndexFromBuffers(const int presentIndex,
                                   const int lastValid,
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
                                   const bool debug,
                                   ZoneSelectionState &selectionState)
{
   ResetZoneSelectionState(selectionState);

   const double touchMargin = MathMax(0, zoneEnergyTouchMarginPoints) * point;

   int i = presentIndex;
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
            ZoneInfo z;
            if (BuildZoneFromCluster(startRecent,
                                     endOld,
                                     presentIndex,
                                     time,
                                     high,
                                     low,
                                     close,
                                     scoreBuffer,
                                     point,
                                     touchMargin,
                                     extendUntilBreak,
                                     breakMarginPoints,
                                     enableZoneEnergy,
                                     z))
            {
               if (!selectionState.lastActive.valid && z.state == Z_ACTIVE)
               {
                  selectionState.lastActive = z;
                  selectionState.lastActiveNetClose = z.netClose;
               }

               if (!selectionState.lastBroken.valid && z.state != Z_ACTIVE)
               {
                  selectionState.lastBroken = z;
                  selectionState.lastBrokenNetClose = z.netClose;
               }

               if (debug)
                  PrintFormat("[LZ] len=%d avgScore=%.2f state=%d start=%d present=%d",
                              z.length,
                              z.avgScore,
                              (int)z.state,
                              z.startIndex,
                              presentIndex);

               if (selectionState.lastActive.valid && selectionState.lastBroken.valid)
                  break;
            }
         }
      }
      else
      {
         i++;
      }
   }

   FinalizeProjectionZone(selectionState);
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
   ZoneInfo zoneCatalog[];
   int zoneCount = 0;

   BuildZoneCatalog(lastValid,
                    time,
                    high,
                    low,
                    close,
                    flagBuffer,
                    scoreBuffer,
                    point,
                    minZoneBars,
                    gapTolerance,
                    extendUntilBreak,
                    breakMarginPoints,
                    enableZoneEnergy,
                    zoneEnergyTouchMarginPoints,
                    debug,
                    zoneCatalog,
                    zoneCount);

   ArrayResize(renderZones, 0);
   renderZoneCount = 0;
   ResetZoneSelectionState(selectionState);

   if (onlyLastActiveAndLastBroken)
   {
      SelectZonesAtIndex(0, zoneCatalog, zoneCount, selectionState);

      if (selectionState.lastActive.valid)
         AppendZoneToRenderList(selectionState.lastActive, renderZones, renderZoneCount);

      if (selectionState.lastBroken.valid)
         AppendZoneToRenderList(selectionState.lastBroken, renderZones, renderZoneCount);

      return;
   }

   for (int idx = 0; idx < zoneCount && renderZoneCount < maxZonesOnChart; ++idx)
      AppendZoneToRenderList(zoneCatalog[idx], renderZones, renderZoneCount);
}

#endif
