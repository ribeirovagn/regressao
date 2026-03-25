#ifndef MARKETREGIME_HUD_HUDLAYOUT_MQH
#define MARKETREGIME_HUD_HUDLAYOUT_MQH

const int HUD_MAX_LINES = 24;

int HUDLineCountEstimate()
{
   int lines = 0;
   lines += 1;
   lines += 1;
   lines += (InpShowBiasAndMicrotrend ? 2 : 1);
   lines += 1;
   lines += 1;
   lines += 1;
   lines += 1;
   lines += 1;
   if (InpEnableZoneEnergy)
      lines += 1;
   if (InpShowTrendDetails)
      lines += 1;
   return lines;
}

int HUDPanelWidth()
{
   return MathMax(MathMax(0, InpHUDWidth), 250);
}

int HUDBarHeight()
{
   return MathMax(8, MathMin(MathMax(2, InpBarHeight), 9));
}

int HUDPanelHeight()
{
   const int PAD_TOP = 10;
   const int LINE_H = 18;
   const int GAP_TEXT_BAR = 10;
   const int PAD_BOTTOM = 12;
   const int BAR_H = HUDBarHeight();
   const int lines = HUDLineCountEstimate();
   const int textBlockH = PAD_TOP + lines * LINE_H;
   const int barBlockH = GAP_TEXT_BAR + BAR_H + PAD_BOTTOM;
   return MathMax(MathMax(0, InpHUDHeight), textBlockH + barBlockH);
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

#endif
