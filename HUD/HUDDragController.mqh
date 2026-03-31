#ifndef MARKETREGIME_HUD_HUDDRAGCONTROLLER_MQH
#define MARKETREGIME_HUD_HUDDRAGCONTROLLER_MQH

#include "HUDLayout.mqh"

string BuildHUDStorageKey(const string suffix)
{
   return StringFormat("MRZ_HUD_%s_%s_%d", suffix, _Symbol, (int)_Period);
}

void BuildHUDStorageKeys()
{
   g_hud_key_x = BuildHUDStorageKey("X");
   g_hud_key_y = BuildHUDStorageKey("Y");
   g_hud_key_moved = BuildHUDStorageKey("MOVED");
}

void ClearSavedHUDPosition()
{
   if (StringLen(g_hud_key_x) == 0 || StringLen(g_hud_key_y) == 0 || StringLen(g_hud_key_moved) == 0)
      BuildHUDStorageKeys();

   GlobalVariableDel(g_hud_key_x);
   GlobalVariableDel(g_hud_key_y);
   GlobalVariableDel(g_hud_key_moved);
}

void ClampHUDPosition(const int panelW, const int panelH)
{
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);

   int maxX = MathMax(0, chartW - panelW - 2);
   int maxY = MathMax(0, chartH - panelH - 2);

   g_hud_x = MathMax(0, MathMin(g_hud_x, maxX));
   g_hud_y = MathMax(0, MathMin(g_hud_y, maxY));
}

void SaveHUDPosition()
{
   if (!InpHUDPersistPosition)
      return;

   if (StringLen(g_hud_key_x) == 0 || StringLen(g_hud_key_y) == 0 || StringLen(g_hud_key_moved) == 0)
      BuildHUDStorageKeys();

   ClampHUDPosition(HUDPanelWidth(), HUDPanelHeight());
   GlobalVariableSet(g_hud_key_x, (double)g_hud_x);
   GlobalVariableSet(g_hud_key_y, (double)g_hud_y);
   GlobalVariableSet(g_hud_key_moved, (g_hud_user_moved ? 1.0 : 0.0));
}

void LoadHUDPosition()
{
   g_hud_corner = CORNER_LEFT_UPPER;

   if (!InpHUDPersistPosition)
   {
      g_hud_x = HUDDefaultX(HUDPanelWidth());
      g_hud_y = HUDDefaultY();
      g_hud_user_moved = false;
      return;
   }

   if (StringLen(g_hud_key_x) == 0 || StringLen(g_hud_key_y) == 0 || StringLen(g_hud_key_moved) == 0)
      BuildHUDStorageKeys();

   const bool hasSavedPosition = (GlobalVariableCheck(g_hud_key_x) &&
                                  GlobalVariableCheck(g_hud_key_y) &&
                                  GlobalVariableCheck(g_hud_key_moved));
   if (hasSavedPosition)
   {
      g_hud_x = (int)MathRound(GlobalVariableGet(g_hud_key_x));
      g_hud_y = (int)MathRound(GlobalVariableGet(g_hud_key_y));
      g_hud_user_moved = (GlobalVariableGet(g_hud_key_moved) > 0.5);
      return;
   }

   g_hud_x = HUDDefaultX(HUDPanelWidth());
   g_hud_y = HUDDefaultY();
   g_hud_user_moved = false;
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

   for (int i = 0; i < HUD_OBJECT_COUNT; ++i)
   {
      const string name = HUDObjectName(i);
      if (StringLen(name) == 0 || name == "LZ_HUD_BG")
         continue;
      ShiftHUDObjectByDelta(name, dx, dy);
   }
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
      if (g_hud_user_moved)
         SaveHUDPosition();
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
      SaveHUDPosition();
      ChartRedraw(0);
   }
}

#endif
