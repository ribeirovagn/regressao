#ifndef MARKETREGIME_HUD_HUDLAYOUT_MQH
#define MARKETREGIME_HUD_HUDLAYOUT_MQH

const int HUD_PANEL_MIN_WIDTH = 620;
const int HUD_TOP_PADDING = 18;
const int HUD_SIDE_PADDING = 22;
const int HUD_BOTTOM_PADDING = 17;
const int HUD_HEADER_HEIGHT = 52;
const int HUD_TOP_GRID_HEIGHT = 78;
const int HUD_MIDDLE_GRID_BASE_HEIGHT = 72;
const int HUD_FOOTER_HEIGHT = 24;
const int HUD_SECTION_GAP = 8;
const int HUD_DIVIDER_THICKNESS = 1;
const int HUD_OBJECT_COUNT = 42;

int HUDMinimumPanelHeight()
{
   return HUD_TOP_PADDING +
          HUD_HEADER_HEIGHT +
          HUD_DIVIDER_THICKNESS +
          HUD_SECTION_GAP +
          HUD_TOP_GRID_HEIGHT +
          HUD_SECTION_GAP +
          HUD_DIVIDER_THICKNESS +
          HUD_SECTION_GAP +
          HUD_MIDDLE_GRID_BASE_HEIGHT +
          HUD_SECTION_GAP +
          HUD_DIVIDER_THICKNESS +
          HUD_SECTION_GAP +
          HUD_FOOTER_HEIGHT +
          HUD_BOTTOM_PADDING;
}

int HUDPanelWidth()
{
   return MathMax(MathMax(0, InpHUDWidth), HUD_PANEL_MIN_WIDTH);
}

int HUDBarHeight()
{
   return MathMax(10, MathMin(MathMax(2, InpBarHeight), 12));
}

int HUDPanelHeight()
{
   return MathMax(MathMax(0, InpHUDHeight), HUDMinimumPanelHeight());
}

int HUDDefaultX(const int panelW)
{
   const int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   if (chartW <= 0)
      return MathMax(0, InpHUDXDefault);
   return MathMax(0, chartW - panelW - MathMax(0, InpHUDXDefault));
}

int HUDDefaultY()
{
   return MathMax(0, InpHUDYDefault);
}

string HUDObjectName(const int idx)
{
   switch (idx)
   {
      case 0:  return "LZ_HUD_SHADOW";
      case 1:  return "LZ_HUD_BG";
      case 2:  return "LZ_HUD_ACCENT";
      case 3:  return "LZ_HUD_ICON_BG";
      case 4:  return "LZ_HUD_ICON_1";
      case 5:  return "LZ_HUD_ICON_2";
      case 6:  return "LZ_HUD_ICON_3";
      case 7:  return "LZ_HUD_TITLE";
      case 8:  return "LZ_HUD_VERSION_BG";
      case 9:  return "LZ_HUD_VERSION_TXT";
      case 10: return "LZ_HUD_DIVIDER_TOP";
      case 11: return "LZ_HUD_DIVIDER_MID";
      case 12: return "LZ_HUD_DIVIDER_BOTTOM";
      case 13: return "LZ_HUD_VSEP_1";
      case 14: return "LZ_HUD_VSEP_2";
      case 15: return "LZ_HUD_VSEP_3";
      case 16: return "LZ_HUD_VSEP_MID";
      case 17: return "LZ_HUD_LBL_REGIME";
      case 18: return "LZ_HUD_VAL_REGIME";
      case 19: return "LZ_HUD_LBL_BIAS";
      case 20: return "LZ_HUD_VAL_BIAS";
      case 21: return "LZ_HUD_LBL_MICRO";
      case 22: return "LZ_HUD_VAL_MICRO";
      case 23: return "LZ_HUD_LBL_STRENGTH";
      case 24: return "LZ_HUD_VAL_STRENGTH";
      case 25: return "LZ_HUD_BAR_BG";
      case 26: return "LZ_HUD_BAR_FILL";
      case 27: return "LZ_HUD_LBL_EXHAUST";
      case 28: return "LZ_HUD_VAL_EXHAUST";
      case 29: return "LZ_HUD_LBL_BREAKQ";
      case 30: return "LZ_HUD_VAL_BREAKQ";
      case 31: return "LZ_HUD_LBL_STEP";
      case 32: return "LZ_HUD_VAL_STEP";
      case 33: return "LZ_HUD_LBL_STEPSRC";
      case 34: return "LZ_HUD_VAL_STEPSRC";
      case 35: return "LZ_HUD_LBL_ENERGY";
      case 36: return "LZ_HUD_VAL_ENERGY";
      case 37: return "LZ_HUD_DETAILS_ICON";
      case 38: return "LZ_HUD_DETAILS_TXT";
      case 39: return "LZ_HUD_DETAILS_R2";
      case 40: return "LZ_HUD_DETAILS_ER";
      case 41: return "LZ_HUD_DETAILS_S";
   }

   return "";
}

#endif
