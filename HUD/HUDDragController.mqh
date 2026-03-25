#ifndef MARKETREGIME_HUD_HUDDRAGCONTROLLER_MQH
#define MARKETREGIME_HUD_HUDDRAGCONTROLLER_MQH

#include "HUDLayout.mqh"

void ClampHUDPosition(const int panelW, const int panelH)
{
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);

   int maxX = MathMax(0, chartW - panelW - 2);
   int maxY = MathMax(0, chartH - panelH - 2);

   g_hud_x = MathMax(0, MathMin(g_hud_x, maxX));
   g_hud_y = MathMax(0, MathMin(g_hud_y, maxY));
}

void ShiftHUDObjectByDelta(const string name, const int dx, const int dy)
{
   if (ObjectFind(0, name) < 0)
      return;

   const int x = MathMax(0, (int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE) + dx);
   const int y = MathMax(0, (int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE) + dy);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}

void ShiftHUDContentByDelta(const int dx, const int dy)
{
   if (dx == 0 && dy == 0)
      return;

   ShiftHUDObjectByDelta("LZ_HUD_SHADOW", dx, dy);
   ShiftHUDObjectByDelta("LZ_HUD_ACCENT", dx, dy);
   ShiftHUDObjectByDelta("LZ_HUD_BAR_BG", dx, dy);
   ShiftHUDObjectByDelta("LZ_HUD_BAR_FILL", dx, dy);
   for (int i = 0; i < HUD_MAX_LINES; ++i)
      ShiftHUDObjectByDelta(StringFormat("LZ_HUD_LINE_%d", i), dx, dy);
}

void ApplyHUDPositionToObjects()
{
   if (ObjectFind(0, "LZ_HUD_BG") < 0)
      return;

   const int targetX = MathMax(0, g_hud_x);
   const int targetY = MathMax(0, g_hud_y);
   const int currX = MathMax(0, (int)ObjectGetInteger(0, "LZ_HUD_BG", OBJPROP_XDISTANCE));
   const int currY = MathMax(0, (int)ObjectGetInteger(0, "LZ_HUD_BG", OBJPROP_YDISTANCE));
   const int dx = targetX - currX;
   const int dy = targetY - currY;
   if (dx == 0 && dy == 0)
      return;

   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_XDISTANCE, targetX);
   ObjectSetInteger(0, "LZ_HUD_BG", OBJPROP_YDISTANCE, targetY);

   ShiftHUDContentByDelta(dx, dy);
}

void SyncHUDPositionFromObject()
{
   if (ObjectFind(0, "LZ_HUD_BG") < 0)
      return;

   g_hud_corner = CORNER_LEFT_UPPER;
   g_hud_x = MathMax(0, (int)ObjectGetInteger(0, "LZ_HUD_BG", OBJPROP_XDISTANCE));
   g_hud_y = MathMax(0, (int)ObjectGetInteger(0, "LZ_HUD_BG", OBJPROP_YDISTANCE));
}

void InitializeHUDState()
{
   const int panelW = HUDPanelWidth();
   const int panelH = HUDPanelHeight();
   g_hud_corner = CORNER_LEFT_UPPER;
   g_hud_x = HUDDefaultX(panelW);
   g_hud_y = HUDDefaultY();
   ClampHUDPosition(panelW, panelH);
   g_hud_is_dragging = false;
   g_hud_user_moved = false;
}

void HandleHUDChartEvent(const int id, const string sparam)
{
   if (!InpEnableTrendHUD)
      return;

   const int panelW = HUDPanelWidth();
   const int panelH = HUDPanelHeight();

   if (id == CHARTEVENT_CHART_CHANGE)
   {
      if (g_hud_user_moved)
         SyncHUDPositionFromObject();
      else
      {
         g_hud_x = HUDDefaultX(panelW);
         g_hud_y = HUDDefaultY();
      }

      g_hud_is_dragging = false;
      ClampHUDPosition(panelW, panelH);
      ApplyHUDPositionToObjects();
      ChartRedraw(0);
      return;
   }

   if (!InpHUDDraggable)
   {
      g_hud_is_dragging = false;
      return;
   }

   if (sparam != "LZ_HUD_BG")
      return;

   if (id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CHANGE)
   {
      const int prevX = g_hud_x;
      const int prevY = g_hud_y;
      g_hud_is_dragging = (id == CHARTEVENT_OBJECT_DRAG);
      SyncHUDPositionFromObject();
      const int draggedX = g_hud_x;
      const int draggedY = g_hud_y;
      g_hud_user_moved = true;
      ClampHUDPosition(panelW, panelH);
      ShiftHUDContentByDelta(draggedX - prevX, draggedY - prevY);
      ApplyHUDPositionToObjects();
      if (id == CHARTEVENT_OBJECT_CHANGE)
         g_hud_is_dragging = false;
      ChartRedraw(0);
   }
}

#endif
