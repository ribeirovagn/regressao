#ifndef MARKETREGIME_HUD_HUDLAYOUT_MQH
#define MARKETREGIME_HUD_HUDLAYOUT_MQH

const double HUD_SCALE_FACTOR = 0.62;
const int HUD_PANEL_MIN_WIDTH = 384;
const int HUD_TOP_PADDING = 12;
const int HUD_SIDE_PADDING = 14;
const int HUD_BOTTOM_PADDING = 10;
const int HUD_HEADER_HEIGHT = 33;
const int HUD_TOP_GRID_HEIGHT = 50;
const int HUD_MIDDLE_GRID_BASE_HEIGHT = 44;
const int HUD_FOOTER_HEIGHT = 15;
const int HUD_SECTION_GAP = 5;
const int HUD_DIVIDER_THICKNESS = 1;
const int HUD_OBJECT_COUNT = 37;

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

int HUDBasePanelWidth()
{
   const int requestedW = MathMax(0, InpHUDWidth);
   return MathMax(HUD_PANEL_MIN_WIDTH, (int)MathRound((double)requestedW * HUD_SCALE_FACTOR));
}

int HUDPanelWidth()
{
   return MathMax(HUDBasePanelWidth(), g_hud_panel_w);
}

int HUDBarHeight()
{
   const int scaledH = (int)MathRound((double)MathMax(0, InpBarHeight) * HUD_SCALE_FACTOR);
   return MathMax(6, MathMin(MathMax(2, scaledH), 8));
}

int HUDBasePanelHeight()
{
   const int requestedH = MathMax(0, InpHUDHeight);
   return MathMax(HUDMinimumPanelHeight(), (int)MathRound((double)requestedH * HUD_SCALE_FACTOR));
}

int HUDPanelHeight()
{
   return MathMax(HUDBasePanelHeight(), g_hud_panel_h);
}

void HUDRememberPanelSize(const int panelW, const int panelH)
{
   g_hud_panel_w = MathMax(HUDBasePanelWidth(), panelW);
   g_hud_panel_h = MathMax(HUDBasePanelHeight(), panelH);
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
      case 27: return "LZ_HUD_ROW_EXHAUST";
      case 28: return "LZ_HUD_ROW_BREAKQ";
      case 29: return "LZ_HUD_ROW_STEP";
      case 30: return "LZ_HUD_ROW_STEPSRC";
      case 31: return "LZ_HUD_ROW_ENERGY";
      case 32: return "LZ_HUD_DETAILS_ICON";
      case 33: return "LZ_HUD_DETAILS_TXT";
      case 34: return "LZ_HUD_DETAILS_R2";
      case 35: return "LZ_HUD_DETAILS_ER";
      case 36: return "LZ_HUD_DETAILS_S";
   }

   return "";
}

#endif
