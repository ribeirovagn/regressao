//+------------------------------------------------------------------+
//| ExportXAUUSDBreakoutMLDataset.mq5                                |
//| Event-based breakout dataset with cost-aware triple barriers     |
//+------------------------------------------------------------------+
#property copyright "Vagner Ribeiro"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs
#property strict

#include "../Core/StateEngine.mqh"
#include "../Core/BreakoutExit.mqh"

input string          InpExportSymbol = "XAUUSD";
input ENUM_TIMEFRAMES InpExportTimeframe = PERIOD_M1;
input int             InpRequestedBars = 500000;

input int InpStateWindowFast = 120;
input int InpStateWindowSlow = 180;
input int InpMicrotrendWindow = 30;
input int InpShortWindow = 20;

input bool   InpEnableImmediateBreakout = true;
input bool   InpEnableRecentContinuation = true;
input bool   InpEnableRetestBreakout = true;
input int    InpRecentBreakoutWindow = 6;
input double InpContinuationStepFraction = 0.05;
input double InpRetestToleranceStepFraction = 0.20;
input bool   InpOneEventPerKindPerZone = true;

input double InpStopStepMultiple = 0.80;
input double InpTargetStepMultiple = 0.80;
input int    InpMaxHoldBars = 20;
input int    InpSlippagePoints = 5;

input bool   InpEnableIndicatorExit = false;
input bool   InpEnableStructureExit = true;
input bool   InpEnableFlowReversalExit = false;
input bool   InpEnableExhaustionReversalExit = false;
input int    InpIndicatorExitMinHoldBars = 1;
input double InpExitInsideZoneStepFraction = 0.50;
input double InpExitExhaustionThreshold = 0.65;

input int InpATRLookback = 14;
input int InpVolatilityLookback = 20;
input int InpVolumeZScoreLookback = 20;

input string InpExportFileName = "xauusd_breakout_ml_events.csv";
input bool   InpExportExitPath = true;
input string InpExitPathFileName = "xauusd_breakout_exit_path.csv";
input bool   InpUseCommonFolder = false;
input int    InpStartShift = 0;
input int    InpMaxRows = 0;

enum ENUM_BARRIER_EXIT_REASON
{
   BARRIER_EXIT_STOP = 0,
   BARRIER_EXIT_TARGET = 1,
   BARRIER_EXIT_TIMEOUT = 2,
   BARRIER_EXIT_STRUCTURE = 3,
   BARRIER_EXIT_FLOW_REVERSAL = 4,
   BARRIER_EXIT_EXHAUSTION_REVERSAL = 5
};

struct BarrierLabel
{
   bool valid;
   int success;
   int targetHit;
   bool ambiguousBar;
   ENUM_BARRIER_EXIT_REASON exitReason;
   datetime entryTime;
   datetime exitTime;
   datetime indicatorExitSignalTime;
   int holdBars;
   int entrySpreadPoints;
   double grossEntryPrice;
   double entryPrice;
   double stopPrice;
   double targetPrice;
   double exitPrice;
   double netPoints;
   double netStepReturn;
   double mfeStep;
   double maeStep;
   int exitRegime;
   int exitBias;
   int exitMicrotrend;
   double exitExhaustion;
};

struct BreakoutCandidate
{
   int index;
   string signalKind;
   int direction;
   int breakoutAge;
};

struct ExitPathObservation
{
   int barIndex;
   int holdBars;
   double currentNetStep;
   double actionExitStep;
   double runningMfeStep;
   double runningMaeStep;
   double givebackStep;
   double futureBestActionStep;
   bool peakActionRow;
   bool finalMfeAlreadySeen;
};

double Eps()
{
   return 1.0e-12;
}

double MissingNumber()
{
   return -999.0;
}

string ResolveExportSymbol()
{
   if (StringLen(InpExportSymbol) > 0)
      return InpExportSymbol;
   return _Symbol;
}

string BarrierExitReasonToString(const ENUM_BARRIER_EXIT_REASON reason)
{
   if (reason == BARRIER_EXIT_STOP)
      return "STOP";
   if (reason == BARRIER_EXIT_TARGET)
      return "TARGET";
   if (reason == BARRIER_EXIT_STRUCTURE)
      return "STRUCTURE";
   if (reason == BARRIER_EXIT_FLOW_REVERSAL)
      return "FLOW_REVERSAL";
   if (reason == BARRIER_EXIT_EXHAUSTION_REVERSAL)
      return "EXHAUSTION_REVERSAL";
   return "TIMEOUT";
}

ENUM_BARRIER_EXIT_REASON IndicatorExitToBarrierReason(const ENUM_BREAKOUT_INDICATOR_EXIT reason)
{
   if (reason == BREAKOUT_INDICATOR_EXIT_STRUCTURE)
      return BARRIER_EXIT_STRUCTURE;
   if (reason == BREAKOUT_INDICATOR_EXIT_FLOW_REVERSAL)
      return BARRIER_EXIT_FLOW_REVERSAL;
   if (reason == BREAKOUT_INDICATOR_EXIT_EXHAUSTION_REVERSAL)
      return BARRIER_EXIT_EXHAUSTION_REVERSAL;
   return BARRIER_EXIT_TIMEOUT;
}

void ResetBarrierLabel(BarrierLabel &label)
{
   label.valid = false;
   label.success = 0;
   label.targetHit = 0;
   label.ambiguousBar = false;
   label.exitReason = BARRIER_EXIT_TIMEOUT;
   label.entryTime = 0;
   label.exitTime = 0;
   label.indicatorExitSignalTime = 0;
   label.holdBars = 0;
   label.entrySpreadPoints = 0;
   label.grossEntryPrice = 0.0;
   label.entryPrice = 0.0;
   label.stopPrice = 0.0;
   label.targetPrice = 0.0;
   label.exitPrice = 0.0;
   label.netPoints = 0.0;
   label.netStepReturn = 0.0;
   label.mfeStep = 0.0;
   label.maeStep = 0.0;
   label.exitRegime = -1;
   label.exitBias = 0;
   label.exitMicrotrend = 0;
   label.exitExhaustion = MissingNumber();
}

void AppendBreakoutCandidate(BreakoutCandidate &candidates[],
                             int &candidateCount,
                             const int index,
                             const string signalKind,
                             const int direction,
                             const int breakoutAge)
{
   ArrayResize(candidates, candidateCount + 1);
   candidates[candidateCount].index = index;
   candidates[candidateCount].signalKind = signalKind;
   candidates[candidateCount].direction = direction;
   candidates[candidateCount].breakoutAge = breakoutAge;
   candidateCount++;
}

bool LoadRatesSeries(const string symbol,
                     const ENUM_TIMEFRAMES timeframe,
                     datetime &time[],
                     double &open[],
                     double &high[],
                     double &low[],
                     double &close[],
                     long &tickVolume[],
                     int &spread[],
                     int &ratesTotal)
{
   ratesTotal = 0;

   if (!SymbolSelect(symbol, true))
   {
      PrintFormat("XAUUSD ML export failed: unable to select symbol %s", symbol);
      return false;
   }

   const int availableBars = Bars(symbol, timeframe);
   if (availableBars <= 0)
   {
      PrintFormat("XAUUSD ML export failed: no bars available for %s %s",
                  symbol,
                  TimeframeToString(timeframe));
      return false;
   }

   const int requestedBars = (InpRequestedBars > 0 ? InpRequestedBars : availableBars);

   MqlRates rates[];
   ResetLastError();
   const int copied = CopyRates(symbol, timeframe, 0, requestedBars, rates);
   if (copied <= 0)
   {
      PrintFormat("XAUUSD ML export failed: CopyRates returned %d for %s %s (error %d)",
                  copied,
                  symbol,
                  TimeframeToString(timeframe),
                  GetLastError());
      return false;
   }

   ArrayResize(time, copied);
   ArrayResize(open, copied);
   ArrayResize(high, copied);
   ArrayResize(low, copied);
   ArrayResize(close, copied);
   ArrayResize(tickVolume, copied);
   ArrayResize(spread, copied);

   for (int i = 0; i < copied; ++i)
   {
      time[i] = rates[i].time;
      open[i] = rates[i].open;
      high[i] = rates[i].high;
      low[i] = rates[i].low;
      close[i] = rates[i].close;
      tickVolume[i] = rates[i].tick_volume;
      spread[i] = (int)rates[i].spread;
   }

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tickVolume, true);
   ArraySetAsSeries(spread, true);

   ratesTotal = copied;
   return true;
}

void ConfigureStateEngine(StateEngineConfig &config,
                          const int window)
{
   InitializeStateEngineConfig(config, window);
   config.microtrendWindow = MathMax(2, InpMicrotrendWindow);
   config.shortWindow = MathMax(2, InpShortWindow);
}

bool HasRecentBreakout(const StateSnapshot &snapshot,
                       const int index,
                       int &direction,
                       int &breakoutAge)
{
   direction = 0;
   breakoutAge = -1;

   if (!snapshot.valid ||
       !snapshot.hasBrokenZone ||
       !snapshot.hasStep ||
       snapshot.step <= Eps() ||
       snapshot.stepSource != STEP_SOURCE_LAST_BROKEN)
   {
      return false;
   }

   if (snapshot.lastBroken.state == Z_BREAK_UP)
      direction = 1;
   else if (snapshot.lastBroken.state == Z_BREAK_DOWN)
      direction = -1;

   if (direction == 0)
      return false;

   breakoutAge = snapshot.lastBroken.breakIndex - index;
   return (breakoutAge >= 0 && breakoutAge <= InpRecentBreakoutWindow);
}

bool EvaluateBreakoutSetup(const StateSnapshot &snapshot,
                           const int index,
                           const double &high[],
                           const double &low[],
                           const double &close[],
                           string &signalKind,
                           int &direction,
                           int &breakoutAge)
{
   signalKind = "";
   direction = 0;
   breakoutAge = -1;

   if (!HasRecentBreakout(snapshot, index, direction, breakoutAge))
      return false;

   const double step = snapshot.step;
   const double retestTolerance = step * InpRetestToleranceStepFraction;
   const double continuationLevel = step * InpContinuationStepFraction;

   if (breakoutAge == 0 && InpEnableImmediateBreakout)
   {
      signalKind = "IMMEDIATE";
      return true;
   }

   if (breakoutAge > 0 && InpEnableRetestBreakout)
   {
      if (direction > 0 &&
          low[index] <= (snapshot.lastBroken.top + retestTolerance) &&
          close[index] > snapshot.lastBroken.top)
      {
         signalKind = "RETEST";
         return true;
      }

      if (direction < 0 &&
          high[index] >= (snapshot.lastBroken.bottom - retestTolerance) &&
          close[index] < snapshot.lastBroken.bottom)
      {
         signalKind = "RETEST";
         return true;
      }
   }

   if (breakoutAge > 0 && InpEnableRecentContinuation)
   {
      if (direction > 0 && close[index] >= (snapshot.lastBroken.top + continuationLevel))
      {
         signalKind = "CONTINUATION";
         return true;
      }

      if (direction < 0 && close[index] <= (snapshot.lastBroken.bottom - continuationLevel))
      {
         signalKind = "CONTINUATION";
         return true;
      }
   }

   return false;
}

bool AcceptUniqueEvent(const string signalKind,
                       const datetime breakTime,
                       datetime &lastImmediateBreak,
                       datetime &lastContinuationBreak,
                       datetime &lastRetestBreak)
{
   if (!InpOneEventPerKindPerZone)
      return true;

   if (signalKind == "IMMEDIATE")
   {
      if (lastImmediateBreak == breakTime)
         return false;
      lastImmediateBreak = breakTime;
      return true;
   }

   if (signalKind == "CONTINUATION")
   {
      if (lastContinuationBreak == breakTime)
         return false;
      lastContinuationBreak = breakTime;
      return true;
   }

   if (signalKind == "RETEST")
   {
      if (lastRetestBreak == breakTime)
         return false;
      lastRetestBreak = breakTime;
      return true;
   }

   return false;
}

double NetExitPrice(const int direction,
                    const double grossExitPrice,
                    const int spreadPoints,
                    const double point,
                    const double slippagePrice)
{
   if (direction > 0)
      return grossExitPrice - slippagePrice;
   return grossExitPrice + (spreadPoints * point) + slippagePrice;
}

bool ComputeBarrierLabel(const int signalIndex,
                         const int direction,
                         const double step,
                         const ZoneInfo &signalZone,
                         const BreakoutExitState &exitStates[],
                         const datetime &time[],
                         const double &open[],
                         const double &high[],
                         const double &low[],
                         const double &close[],
                         const int &spread[],
                         const double point,
                         BarrierLabel &label)
{
   ResetBarrierLabel(label);

   const int entryIndex = signalIndex - 1;
   const int finalIndex = entryIndex - InpMaxHoldBars + 1;
   if (entryIndex < 0 || finalIndex < 0 || step <= Eps() || direction == 0)
      return false;

   const double slippagePrice = InpSlippagePoints * point;
   const double entrySpreadPrice = spread[entryIndex] * point;

   label.entryTime = time[entryIndex];
   label.entrySpreadPoints = spread[entryIndex];
   label.grossEntryPrice = open[entryIndex];
   label.entryPrice = (direction > 0
                       ? open[entryIndex] + entrySpreadPrice + slippagePrice
                       : open[entryIndex] - slippagePrice);
   label.stopPrice = label.entryPrice - (direction * InpStopStepMultiple * step);
   label.targetPrice = label.entryPrice + (direction * InpTargetStepMultiple * step);

   double maxNetMove = -DBL_MAX;
   double minNetMove = DBL_MAX;
   ENUM_BREAKOUT_INDICATOR_EXIT pendingIndicatorExit = BREAKOUT_INDICATOR_EXIT_NONE;
   BreakoutExitState pendingExitState;
   ResetBreakoutExitState(pendingExitState);

   for (int bar = entryIndex; bar >= finalIndex; --bar)
   {
      const int holdBars = entryIndex - bar + 1;

      // Indicator decisions are confirmed on the previous candle close and
      // executed at this candle open, before its intrabar range is known.
      if (pendingIndicatorExit != BREAKOUT_INDICATOR_EXIT_NONE)
      {
         label.exitReason = IndicatorExitToBarrierReason(pendingIndicatorExit);
         label.exitPrice = NetExitPrice(direction,
                                        open[bar],
                                        spread[bar],
                                        point,
                                        slippagePrice);
         label.exitTime = time[bar];
         label.holdBars = entryIndex - bar;
         label.exitRegime = (int)pendingExitState.regime;
         label.exitBias = pendingExitState.biasDir;
         label.exitMicrotrend = pendingExitState.microDir;
         label.exitExhaustion = (pendingExitState.hasExhaustion
                                 ? pendingExitState.exhaustion01
                                 : MissingNumber());
         const double indicatorExitMove = (label.exitPrice - label.entryPrice) * direction;
         if (indicatorExitMove > maxNetMove)
            maxNetMove = indicatorExitMove;
         if (indicatorExitMove < minNetMove)
            minNetMove = indicatorExitMove;
         break;
      }

      const double favorableGross = (direction > 0 ? high[bar] : low[bar]);
      const double adverseGross = (direction > 0 ? low[bar] : high[bar]);
      const double favorableExit = NetExitPrice(direction,
                                                favorableGross,
                                                spread[bar],
                                                point,
                                                slippagePrice);
      const double adverseExit = NetExitPrice(direction,
                                              adverseGross,
                                              spread[bar],
                                              point,
                                              slippagePrice);
      const double favorableMove = (favorableExit - label.entryPrice) * direction;
      const double adverseMove = (adverseExit - label.entryPrice) * direction;

      if (favorableMove > maxNetMove)
         maxNetMove = favorableMove;
      if (adverseMove < minNetMove)
         minNetMove = adverseMove;

      const bool stopHit = (direction > 0
                            ? low[bar] <= label.stopPrice
                            : high[bar] >= label.stopPrice);
      const bool targetHit = (direction > 0
                              ? high[bar] >= label.targetPrice
                              : low[bar] <= label.targetPrice);

      if (stopHit || targetHit)
      {
         label.ambiguousBar = (stopHit && targetHit);
         label.exitReason = (stopHit ? BARRIER_EXIT_STOP : BARRIER_EXIT_TARGET);
         const double grossExitPrice = (stopHit ? label.stopPrice : label.targetPrice);
         label.exitPrice = NetExitPrice(direction,
                                        grossExitPrice,
                                        spread[bar],
                                        point,
                                        slippagePrice);
         label.exitTime = time[bar];
         label.holdBars = holdBars;
         break;
      }

      if (bar == finalIndex)
      {
         label.exitReason = BARRIER_EXIT_TIMEOUT;
         label.exitPrice = NetExitPrice(direction,
                                        close[bar],
                                        spread[bar],
                                        point,
                                        slippagePrice);
         label.exitTime = time[bar];
         label.holdBars = holdBars;
         continue;
      }

      if (bar > finalIndex && bar < ArraySize(exitStates))
      {
         const ENUM_BREAKOUT_INDICATOR_EXIT indicatorExit = EvaluateBreakoutIndicatorExit(direction,
                                                                                            holdBars,
                                                                                            signalZone.top,
                                                                                            signalZone.bottom,
                                                                                            step,
                                                                                            close[bar],
                                                                                            exitStates[bar],
                                                                                            InpEnableIndicatorExit,
                                                                                            InpEnableStructureExit,
                                                                                            InpEnableFlowReversalExit,
                                                                                            InpEnableExhaustionReversalExit,
                                                                                            InpIndicatorExitMinHoldBars,
                                                                                            InpExitInsideZoneStepFraction,
                                                                                            InpExitExhaustionThreshold,
                                                                                            Eps());
         if (indicatorExit != BREAKOUT_INDICATOR_EXIT_NONE)
         {
            pendingIndicatorExit = indicatorExit;
            pendingExitState = exitStates[bar];
            label.indicatorExitSignalTime = time[bar];
         }
      }
   }

   if (maxNetMove == -DBL_MAX || minNetMove == DBL_MAX || label.holdBars <= 0)
      return false;

   const double netMove = (label.exitPrice - label.entryPrice) * direction;
   label.netPoints = netMove / point;
   label.netStepReturn = netMove / step;
   label.mfeStep = maxNetMove / step;
   label.maeStep = minNetMove / step;
   label.targetHit = (label.exitReason == BARRIER_EXIT_TARGET ? 1 : 0);
   label.success = (label.netPoints > 0.0 ? 1 : 0);
   label.valid = true;
   return true;
}

double OptionalValue(const bool hasValue,
                     const double value)
{
   return (hasValue ? value : MissingNumber());
}

int OptionalAlignment(const bool hasLeft,
                      const int left,
                      const bool hasRight,
                      const int right)
{
   if (!hasLeft || !hasRight)
      return -1;
   return (left == right ? 1 : 0);
}

double OptionalDelta(const bool hasLeft,
                     const double left,
                     const bool hasRight,
                     const double right)
{
   if (!hasLeft || !hasRight)
      return MissingNumber();
   return left - right;
}

double StepReturn(const int index,
                  const int lookback,
                  const double &close[],
                  const double step)
{
   const int olderIndex = index + lookback;
   if (lookback < 1 || olderIndex >= ArraySize(close) || step <= Eps())
      return MissingNumber();
   return (close[index] - close[olderIndex]) / step;
}

double AverageTrueRangeStep(const int index,
                            const int lookback,
                            const double &high[],
                            const double &low[],
                            const double &close[],
                            const double step)
{
   if (lookback < 1 || (index + lookback) >= ArraySize(close) || step <= Eps())
      return MissingNumber();

   double sum = 0.0;
   for (int offset = 0; offset < lookback; ++offset)
   {
      const int bar = index + offset;
      const double previousClose = close[bar + 1];
      const double trueRange = MathMax(high[bar] - low[bar],
                                       MathMax(MathAbs(high[bar] - previousClose),
                                               MathAbs(low[bar] - previousClose)));
      sum += trueRange;
   }

   return (sum / lookback) / step;
}

double RealizedVolatilityStep(const int index,
                              const int lookback,
                              const double &close[],
                              const double step)
{
   if (lookback < 2 || (index + lookback) >= ArraySize(close) || step <= Eps())
      return MissingNumber();

   double sum = 0.0;
   double sumSq = 0.0;
   for (int offset = 0; offset < lookback; ++offset)
   {
      const int bar = index + offset;
      const double change = close[bar] - close[bar + 1];
      sum += change;
      sumSq += change * change;
   }

   const double mean = sum / lookback;
   const double variance = MathMax(0.0, (sumSq / lookback) - (mean * mean));
   return MathSqrt(variance) / step;
}

double VolumeZScore(const int index,
                    const int lookback,
                    const long &tickVolume[])
{
   if (lookback < 2 || (index + lookback) >= ArraySize(tickVolume))
      return MissingNumber();

   double sum = 0.0;
   double sumSq = 0.0;
   for (int offset = 1; offset <= lookback; ++offset)
   {
      const double value = (double)tickVolume[index + offset];
      sum += value;
      sumSq += value * value;
   }

   const double mean = sum / lookback;
   const double variance = MathMax(0.0, (sumSq / lookback) - (mean * mean));
   const double stddev = MathSqrt(variance);
   if (stddev <= Eps())
      return 0.0;
   return ((double)tickVolume[index] - mean) / stddev;
}

double BreakBoundaryDistanceStep(const StateSnapshot &snapshot,
                                 const int direction,
                                 const double signalClose)
{
   if (!snapshot.hasBrokenZone || !snapshot.hasStep || snapshot.step <= Eps())
      return MissingNumber();

   if (direction > 0)
      return (signalClose - snapshot.lastBroken.top) / snapshot.step;
   return (snapshot.lastBroken.bottom - signalClose) / snapshot.step;
}

double MidDistanceDirectionalStep(const StateSnapshot &snapshot,
                                  const int direction,
                                  const double signalClose)
{
   if (!snapshot.hasBrokenZone || !snapshot.hasStep || snapshot.step <= Eps())
      return MissingNumber();
   return ((signalClose - snapshot.lastBroken.mid) * direction) / snapshot.step;
}

double DirectionalCloseLocation(const int index,
                                const int direction,
                                const double &high[],
                                const double &low[],
                                const double &close[])
{
   const double range = high[index] - low[index];
   if (range <= Eps())
      return 0.5;

   const double rawLocation = (close[index] - low[index]) / range;
   return (direction > 0 ? rawLocation : 1.0 - rawLocation);
}

string CsvEscape(string value)
{
   const bool quote = (StringFind(value, ",") >= 0 ||
                       StringFind(value, "\"") >= 0 ||
                       StringFind(value, "\r") >= 0 ||
                       StringFind(value, "\n") >= 0);
   StringReplace(value, "\"", "\"\"");
   if (quote)
      return "\"" + value + "\"";
   return value;
}

void CsvAppendString(string &line,
                     const string value)
{
   if (StringLen(line) > 0)
      line += ",";
   line += CsvEscape(value);
}

void CsvAppendInt(string &line,
                  const int value)
{
   CsvAppendString(line, IntegerToString(value));
}

void CsvAppendDouble(string &line,
                     const double value)
{
   CsvAppendString(line, DoubleToString(value, 10));
}

void CsvAppendTime(string &line,
                   const datetime value)
{
   CsvAppendString(line, TimeToString(value, TIME_DATE | TIME_MINUTES | TIME_SECONDS));
}

void CsvAppendOptionalTime(string &line,
                           const datetime value)
{
   if (value > 0)
      CsvAppendTime(line, value);
   else
      CsvAppendString(line, "");
}

int OpenExportFile()
{
   int flags = FILE_WRITE | FILE_TXT | FILE_ANSI;
   if (InpUseCommonFolder)
      flags |= FILE_COMMON;

   ResetLastError();
   const int fileHandle = FileOpen(InpExportFileName, flags);
   if (fileHandle == INVALID_HANDLE)
   {
      PrintFormat("XAUUSD ML export failed: unable to open %s (error %d)",
                  InpExportFileName,
                  GetLastError());
   }
   return fileHandle;
}

void WriteCsvHeader(const int fileHandle)
{
   string columns[] =
   {
      "meta_schema_version",
      "meta_signal_time",
      "meta_entry_time",
      "meta_symbol",
      "meta_timeframe",
      "meta_signal_kind",
      "meta_direction",
      "meta_break_time",
      "meta_breakout_age_bars",
      "meta_signal_close",
      "meta_zone_step",
      "feature_regime_fast",
      "feature_bias_fast",
      "feature_microtrend_fast",
      "feature_strength_fast",
      "feature_exhaustion_fast",
      "feature_break_quality_fast",
      "feature_slope_fast",
      "feature_r2_fast",
      "feature_er_fast",
      "feature_volume_bias_fast",
      "feature_volume_confirm_fast",
      "feature_volume_r2_fast",
      "feature_volume_ratio_fast",
      "feature_regime_slow",
      "feature_bias_slow",
      "feature_microtrend_slow",
      "feature_strength_slow",
      "feature_exhaustion_slow",
      "feature_break_quality_slow",
      "feature_slope_slow",
      "feature_r2_slow",
      "feature_er_slow",
      "feature_volume_bias_slow",
      "feature_volume_confirm_slow",
      "feature_regime_alignment",
      "feature_bias_alignment",
      "feature_microtrend_alignment",
      "feature_volume_bias_alignment",
      "feature_strength_delta",
      "feature_break_quality_delta",
      "feature_exhaustion_delta",
      "feature_volume_confirm_delta",
      "feature_return_1_step",
      "feature_return_3_step",
      "feature_return_5_step",
      "feature_return_10_step",
      "feature_return_20_step",
      "feature_body_step",
      "feature_range_step",
      "feature_upper_wick_step",
      "feature_lower_wick_step",
      "feature_close_location_directional",
      "feature_atr_step",
      "feature_realized_volatility_step",
      "feature_volume_zscore",
      "feature_signal_spread_step",
      "feature_break_boundary_distance_step",
      "feature_mid_distance_directional_step",
      "feature_zone_length_bars",
      "feature_zone_touch_top",
      "feature_zone_touch_bottom",
      "feature_zone_path_step",
      "feature_server_hour",
      "feature_day_of_week",
      "label_success",
      "label_target_hit",
      "label_exit_reason",
      "label_indicator_exit_signal_time",
      "label_exit_time",
      "label_hold_bars",
      "label_ambiguous_bar",
      "label_entry_spread_points",
      "label_gross_entry_price",
      "label_entry_price",
      "label_stop_price",
      "label_target_price",
      "label_exit_price",
      "label_net_points",
      "label_net_step_return",
      "label_mfe_step",
      "label_mae_step",
      "label_exit_regime",
      "label_exit_bias",
      "label_exit_microtrend",
      "label_exit_exhaustion"
   };

   string line = "";
   for (int i = 0; i < ArraySize(columns); ++i)
      CsvAppendString(line, columns[i]);
   FileWriteString(fileHandle, line + "\r\n");
}

void WriteEventRow(const int fileHandle,
                   const string symbol,
                   const string timeframeLabel,
                   const int index,
                   const string signalKind,
                   const int direction,
                   const int breakoutAge,
                   const StateSnapshot &fastState,
                   const StateSnapshot &slowState,
                   const datetime &time[],
                   const double &open[],
                   const double &high[],
                   const double &low[],
                   const double &close[],
                   const long &tickVolume[],
                   const int &spread[],
                   const double point,
                   const BarrierLabel &label)
{
   const double step = fastState.step;
   const double bodyTop = MathMax(open[index], close[index]);
   const double bodyBottom = MathMin(open[index], close[index]);

   MqlDateTime dateParts;
   TimeToStruct(time[index], dateParts);

   string line = "";
   CsvAppendString(line, "2");
   CsvAppendTime(line, time[index]);
   CsvAppendTime(line, label.entryTime);
   CsvAppendString(line, symbol);
   CsvAppendString(line, timeframeLabel);
   CsvAppendString(line, signalKind);
   CsvAppendInt(line, direction);
   CsvAppendTime(line, fastState.lastBroken.t_break);
   CsvAppendInt(line, breakoutAge);
   CsvAppendDouble(line, close[index]);
   CsvAppendDouble(line, step);

   CsvAppendInt(line, (int)fastState.regime);
   CsvAppendInt(line, fastState.biasDir);
   CsvAppendInt(line, fastState.microDir);
   CsvAppendDouble(line, OptionalValue(fastState.hasStrength, fastState.strength01));
   CsvAppendDouble(line, OptionalValue(fastState.hasExhaustion, fastState.exhaustion01));
   CsvAppendDouble(line, OptionalValue(fastState.hasBreakQuality, fastState.breakQuality01));
   CsvAppendDouble(line, fastState.slope01);
   CsvAppendDouble(line, OptionalValue(fastState.mainMetrics.valid, fastState.mainMetrics.r2));
   CsvAppendDouble(line, OptionalValue(fastState.mainMetrics.valid, fastState.mainMetrics.er));
   CsvAppendInt(line, (fastState.hasVolume ? fastState.volumeState.bias : 0));
   CsvAppendDouble(line, OptionalValue(fastState.hasVolume, fastState.volumeState.confirmation01));
   CsvAppendDouble(line, OptionalValue(fastState.hasVolume, fastState.volumeState.r2));
   CsvAppendDouble(line, OptionalValue(fastState.hasVolume, fastState.volumeState.ratio));

   CsvAppendInt(line, (int)slowState.regime);
   CsvAppendInt(line, slowState.biasDir);
   CsvAppendInt(line, slowState.microDir);
   CsvAppendDouble(line, OptionalValue(slowState.hasStrength, slowState.strength01));
   CsvAppendDouble(line, OptionalValue(slowState.hasExhaustion, slowState.exhaustion01));
   CsvAppendDouble(line, OptionalValue(slowState.hasBreakQuality, slowState.breakQuality01));
   CsvAppendDouble(line, slowState.slope01);
   CsvAppendDouble(line, OptionalValue(slowState.mainMetrics.valid, slowState.mainMetrics.r2));
   CsvAppendDouble(line, OptionalValue(slowState.mainMetrics.valid, slowState.mainMetrics.er));
   CsvAppendInt(line, (slowState.hasVolume ? slowState.volumeState.bias : 0));
   CsvAppendDouble(line, OptionalValue(slowState.hasVolume, slowState.volumeState.confirmation01));

   CsvAppendInt(line, OptionalAlignment(fastState.valid,
                                        (int)fastState.regime,
                                        slowState.valid,
                                        (int)slowState.regime));
   CsvAppendInt(line, OptionalAlignment(fastState.mainMetrics.valid,
                                        fastState.biasDir,
                                        slowState.mainMetrics.valid,
                                        slowState.biasDir));
   CsvAppendInt(line, OptionalAlignment(fastState.microMetrics.valid,
                                        fastState.microDir,
                                        slowState.microMetrics.valid,
                                        slowState.microDir));
   CsvAppendInt(line, OptionalAlignment(fastState.hasVolume,
                                        fastState.volumeState.bias,
                                        slowState.hasVolume,
                                        slowState.volumeState.bias));
   CsvAppendDouble(line, OptionalDelta(fastState.hasStrength,
                                       fastState.strength01,
                                       slowState.hasStrength,
                                       slowState.strength01));
   CsvAppendDouble(line, OptionalDelta(fastState.hasBreakQuality,
                                       fastState.breakQuality01,
                                       slowState.hasBreakQuality,
                                       slowState.breakQuality01));
   CsvAppendDouble(line, OptionalDelta(fastState.hasExhaustion,
                                       fastState.exhaustion01,
                                       slowState.hasExhaustion,
                                       slowState.exhaustion01));
   CsvAppendDouble(line, OptionalDelta(fastState.hasVolume,
                                       fastState.volumeState.confirmation01,
                                       slowState.hasVolume,
                                       slowState.volumeState.confirmation01));

   CsvAppendDouble(line, StepReturn(index, 1, close, step));
   CsvAppendDouble(line, StepReturn(index, 3, close, step));
   CsvAppendDouble(line, StepReturn(index, 5, close, step));
   CsvAppendDouble(line, StepReturn(index, 10, close, step));
   CsvAppendDouble(line, StepReturn(index, 20, close, step));
   CsvAppendDouble(line, (close[index] - open[index]) / step);
   CsvAppendDouble(line, (high[index] - low[index]) / step);
   CsvAppendDouble(line, (high[index] - bodyTop) / step);
   CsvAppendDouble(line, (bodyBottom - low[index]) / step);
   CsvAppendDouble(line, DirectionalCloseLocation(index, direction, high, low, close));
   CsvAppendDouble(line, AverageTrueRangeStep(index, InpATRLookback, high, low, close, step));
   CsvAppendDouble(line, RealizedVolatilityStep(index, InpVolatilityLookback, close, step));
   CsvAppendDouble(line, VolumeZScore(index, InpVolumeZScoreLookback, tickVolume));
   CsvAppendDouble(line, (spread[index] * point) / step);
   CsvAppendDouble(line, BreakBoundaryDistanceStep(fastState, direction, close[index]));
   CsvAppendDouble(line, MidDistanceDirectionalStep(fastState, direction, close[index]));
   CsvAppendInt(line, fastState.lastBroken.length);
   CsvAppendInt(line, fastState.lastBroken.touchTop);
   CsvAppendInt(line, fastState.lastBroken.touchBot);
   CsvAppendDouble(line, fastState.lastBroken.path / step);
   CsvAppendInt(line, dateParts.hour);
   CsvAppendInt(line, dateParts.day_of_week);

   CsvAppendInt(line, label.success);
   CsvAppendInt(line, label.targetHit);
   CsvAppendString(line, BarrierExitReasonToString(label.exitReason));
   CsvAppendOptionalTime(line, label.indicatorExitSignalTime);
   CsvAppendTime(line, label.exitTime);
   CsvAppendInt(line, label.holdBars);
   CsvAppendInt(line, (label.ambiguousBar ? 1 : 0));
   CsvAppendInt(line, label.entrySpreadPoints);
   CsvAppendDouble(line, label.grossEntryPrice);
   CsvAppendDouble(line, label.entryPrice);
   CsvAppendDouble(line, label.stopPrice);
   CsvAppendDouble(line, label.targetPrice);
   CsvAppendDouble(line, label.exitPrice);
   CsvAppendDouble(line, label.netPoints);
   CsvAppendDouble(line, label.netStepReturn);
   CsvAppendDouble(line, label.mfeStep);
   CsvAppendDouble(line, label.maeStep);
   CsvAppendInt(line, label.exitRegime);
   CsvAppendInt(line, label.exitBias);
   CsvAppendInt(line, label.exitMicrotrend);
   CsvAppendDouble(line, label.exitExhaustion);

   FileWriteString(fileHandle, line + "\r\n");
}

int OpenExitPathFile()
{
   int flags = FILE_WRITE | FILE_TXT | FILE_ANSI;
   if (InpUseCommonFolder)
      flags |= FILE_COMMON;

   ResetLastError();
   const int fileHandle = FileOpen(InpExitPathFileName, flags);
   if (fileHandle == INVALID_HANDLE)
   {
      PrintFormat("XAUUSD exit-path export failed: unable to open %s (error %d)",
                  InpExitPathFileName,
                  GetLastError());
   }
   return fileHandle;
}

void WriteExitPathHeader(const int fileHandle)
{
   string columns[] =
   {
      "meta_schema_version",
      "meta_signal_time",
      "meta_entry_time",
      "meta_decision_bar_time",
      "meta_execution_time",
      "meta_symbol",
      "meta_timeframe",
      "meta_signal_kind",
      "meta_direction",
      "meta_hold_bars",
      "meta_baseline_exit_time",
      "meta_baseline_exit_reason",
      "feature_zone_step",
      "feature_current_close",
      "label_action_exit_price",
      "feature_current_net_step",
      "label_action_exit_step",
      "feature_running_mfe_step",
      "feature_running_mae_step",
      "feature_giveback_from_mfe_step",
      "feature_hold_fraction",
      "feature_entry_boundary_distance_step",
      "feature_current_boundary_distance_step",
      "feature_current_mid_distance_step",
      "feature_body_directional_step",
      "feature_range_step",
      "feature_close_location_directional",
      "label_action_execution_spread_step",
      "feature_regime_fast",
      "feature_bias_fast",
      "feature_microtrend_fast",
      "feature_bias_with_trade_fast",
      "feature_microtrend_with_trade_fast",
      "feature_strength_fast",
      "feature_exhaustion_fast",
      "feature_break_quality_fast",
      "feature_slope_fast",
      "feature_r2_fast",
      "feature_er_fast",
      "feature_volume_bias_fast",
      "feature_volume_bias_with_trade_fast",
      "feature_volume_confirm_fast",
      "feature_volume_r2_fast",
      "feature_volume_ratio_fast",
      "feature_volume_slope_fast",
      "feature_regime_slow",
      "feature_bias_slow",
      "feature_microtrend_slow",
      "feature_bias_with_trade_slow",
      "feature_microtrend_with_trade_slow",
      "feature_strength_slow",
      "feature_exhaustion_slow",
      "feature_break_quality_slow",
      "feature_slope_slow",
      "feature_r2_slow",
      "feature_er_slow",
      "feature_volume_bias_slow",
      "feature_volume_bias_with_trade_slow",
      "feature_volume_confirm_slow",
      "feature_volume_r2_slow",
      "feature_volume_ratio_slow",
      "feature_volume_slope_slow",
      "feature_regime_alignment",
      "feature_bias_alignment",
      "feature_microtrend_alignment",
      "feature_volume_bias_alignment",
      "feature_strength_delta_entry_fast",
      "feature_exhaustion_delta_entry_fast",
      "feature_break_quality_delta_entry_fast",
      "feature_slope_delta_entry_fast",
      "feature_r2_delta_entry_fast",
      "feature_er_delta_entry_fast",
      "feature_volume_confirm_delta_entry_fast",
      "feature_strength_delta_previous_fast",
      "feature_exhaustion_delta_previous_fast",
      "feature_break_quality_delta_previous_fast",
      "feature_slope_delta_previous_fast",
      "feature_r2_delta_previous_fast",
      "feature_er_delta_previous_fast",
      "feature_volume_confirm_delta_previous_fast",
      "feature_strength_delta_entry_slow",
      "feature_exhaustion_delta_entry_slow",
      "feature_break_quality_delta_entry_slow",
      "feature_slope_delta_entry_slow",
      "feature_r2_delta_entry_slow",
      "feature_er_delta_entry_slow",
      "feature_volume_confirm_delta_entry_slow",
      "feature_strength_delta_previous_slow",
      "feature_exhaustion_delta_previous_slow",
      "feature_break_quality_delta_previous_slow",
      "feature_slope_delta_previous_slow",
      "feature_r2_delta_previous_slow",
      "feature_er_delta_previous_slow",
      "feature_volume_confirm_delta_previous_slow",
      "label_baseline_success",
      "label_baseline_net_step",
      "label_baseline_mfe_step",
      "label_baseline_mae_step",
      "label_future_best_action_step",
      "label_action_advantage_vs_baseline_step",
      "label_action_regret_step",
      "label_peak_action_row",
      "label_final_mfe_already_seen"
   };

   string line = "";
   for (int i = 0; i < ArraySize(columns); ++i)
      CsvAppendString(line, columns[i]);
   FileWriteString(fileHandle, line + "\r\n");
}

void AppendExitHUDFeatures(string &line,
                           const StateSnapshot &state,
                           const int direction)
{
   CsvAppendInt(line, (int)state.regime);
   CsvAppendInt(line, state.biasDir);
   CsvAppendInt(line, state.microDir);
   CsvAppendInt(line, state.biasDir * direction);
   CsvAppendInt(line, state.microDir * direction);
   CsvAppendDouble(line, OptionalValue(state.hasStrength, state.strength01));
   CsvAppendDouble(line, OptionalValue(state.hasExhaustion, state.exhaustion01));
   CsvAppendDouble(line, OptionalValue(state.hasBreakQuality, state.breakQuality01));
   CsvAppendDouble(line, state.slope01);
   CsvAppendDouble(line, OptionalValue(state.mainMetrics.valid, state.mainMetrics.r2));
   CsvAppendDouble(line, OptionalValue(state.mainMetrics.valid, state.mainMetrics.er));
   CsvAppendInt(line, (state.hasVolume ? state.volumeState.bias : 0));
   CsvAppendInt(line, (state.hasVolume ? state.volumeState.bias * direction : 0));
   CsvAppendDouble(line, OptionalValue(state.hasVolume, state.volumeState.confirmation01));
   CsvAppendDouble(line, OptionalValue(state.hasVolume, state.volumeState.r2));
   CsvAppendDouble(line, OptionalValue(state.hasVolume, state.volumeState.ratio));
   CsvAppendDouble(line, OptionalValue(state.hasVolume, state.volumeState.slope01));
}

void AppendExitHUDDeltas(string &line,
                         const StateSnapshot &current,
                         const StateSnapshot &reference)
{
   CsvAppendDouble(line, OptionalDelta(current.hasStrength,
                                       current.strength01,
                                       reference.hasStrength,
                                       reference.strength01));
   CsvAppendDouble(line, OptionalDelta(current.hasExhaustion,
                                       current.exhaustion01,
                                       reference.hasExhaustion,
                                       reference.exhaustion01));
   CsvAppendDouble(line, OptionalDelta(current.hasBreakQuality,
                                       current.breakQuality01,
                                       reference.hasBreakQuality,
                                       reference.breakQuality01));
   CsvAppendDouble(line, OptionalDelta(current.mainMetrics.valid,
                                       current.slope01,
                                       reference.mainMetrics.valid,
                                       reference.slope01));
   CsvAppendDouble(line, OptionalDelta(current.mainMetrics.valid,
                                       current.mainMetrics.r2,
                                       reference.mainMetrics.valid,
                                       reference.mainMetrics.r2));
   CsvAppendDouble(line, OptionalDelta(current.mainMetrics.valid,
                                       current.mainMetrics.er,
                                       reference.mainMetrics.valid,
                                       reference.mainMetrics.er));
   CsvAppendDouble(line, OptionalDelta(current.hasVolume,
                                       current.volumeState.confirmation01,
                                       reference.hasVolume,
                                       reference.volumeState.confirmation01));
}

int BuildExitPathObservations(const int signalIndex,
                              const int direction,
                              const double step,
                              const BarrierLabel &label,
                              const datetime &time[],
                              const double &open[],
                              const double &high[],
                              const double &low[],
                              const double &close[],
                              const int &spread[],
                              const double point,
                              ExitPathObservation &observations[])
{
   ArrayResize(observations, 0);
   const int entryIndex = signalIndex - 1;
   if (entryIndex <= 0 || step <= Eps())
      return 0;

   const double slippagePrice = InpSlippagePoints * point;
   double runningMfeStep = -DBL_MAX;
   double runningMaeStep = DBL_MAX;
   int count = 0;

   for (int bar = entryIndex; bar > 0; --bar)
   {
      if (time[bar] >= label.exitTime)
         break;

      const double favorableGross = (direction > 0 ? high[bar] : low[bar]);
      const double adverseGross = (direction > 0 ? low[bar] : high[bar]);
      const double favorableExit = NetExitPrice(direction,
                                                favorableGross,
                                                spread[bar],
                                                point,
                                                slippagePrice);
      const double adverseExit = NetExitPrice(direction,
                                              adverseGross,
                                              spread[bar],
                                              point,
                                              slippagePrice);
      const double favorableStep = ((favorableExit - label.entryPrice) * direction) / step;
      const double adverseStep = ((adverseExit - label.entryPrice) * direction) / step;
      runningMfeStep = MathMax(runningMfeStep, favorableStep);
      runningMaeStep = MathMin(runningMaeStep, adverseStep);

      const double currentExit = NetExitPrice(direction,
                                              close[bar],
                                              spread[bar],
                                              point,
                                              slippagePrice);
      const double actionExit = NetExitPrice(direction,
                                             open[bar - 1],
                                             spread[bar - 1],
                                             point,
                                             slippagePrice);
      const double currentNetStep = ((currentExit - label.entryPrice) * direction) / step;
      const double actionExitStep = ((actionExit - label.entryPrice) * direction) / step;

      ArrayResize(observations, count + 1);
      observations[count].barIndex = bar;
      observations[count].holdBars = entryIndex - bar + 1;
      observations[count].currentNetStep = currentNetStep;
      observations[count].actionExitStep = actionExitStep;
      observations[count].runningMfeStep = runningMfeStep;
      observations[count].runningMaeStep = runningMaeStep;
      observations[count].givebackStep = runningMfeStep - currentNetStep;
      observations[count].futureBestActionStep = label.netStepReturn;
      observations[count].peakActionRow = false;
      observations[count].finalMfeAlreadySeen = false;
      count++;
   }

   if (count <= 0)
      return 0;

   double futureBest = label.netStepReturn;
   double peakAction = -DBL_MAX;
   int peakActionIndex = -1;
   for (int i = 0; i < count; ++i)
   {
      if (observations[i].actionExitStep > peakAction)
      {
         peakAction = observations[i].actionExitStep;
         peakActionIndex = i;
      }
   }
   for (int i = count - 1; i >= 0; --i)
   {
      futureBest = MathMax(futureBest, observations[i].actionExitStep);
      observations[i].futureBestActionStep = futureBest;
      observations[i].peakActionRow = (i == peakActionIndex);
      observations[i].finalMfeAlreadySeen =
         (observations[i].runningMfeStep >= label.mfeStep - 1.0e-9);
   }
   return count;
}

int WriteExitPathRows(const int fileHandle,
                      const string symbol,
                      const string timeframeLabel,
                      const int signalIndex,
                      const string signalKind,
                      const int direction,
                      const StateSnapshot &entryFastState,
                      const StateSnapshot &entrySlowState,
                      const BarrierLabel &label,
                      const int fastLastValid,
                      const int slowLastValid,
                      const datetime &time[],
                      const double &open[],
                      const double &high[],
                      const double &low[],
                      const double &close[],
                      const long &tickVolume[],
                      const int &spread[],
                      const double &fastFlagBuffer[],
                      const double &fastScoreBuffer[],
                      const double &slowFlagBuffer[],
                      const double &slowScoreBuffer[],
                      const double point,
                      const StateEngineConfig &fastConfig,
                      const StateEngineConfig &slowConfig)
{
   ExitPathObservation observations[];
   const int observationCount = BuildExitPathObservations(signalIndex,
                                                          direction,
                                                          entryFastState.step,
                                                          label,
                                                          time,
                                                          open,
                                                          high,
                                                          low,
                                                          close,
                                                          spread,
                                                          point,
                                                          observations);
   if (observationCount <= 0)
      return 0;

   const double step = entryFastState.step;
   const double boundary = (direction > 0
                            ? entryFastState.lastBroken.top
                            : entryFastState.lastBroken.bottom);
   StateSnapshot previousFastState = entryFastState;
   StateSnapshot previousSlowState = entrySlowState;
   int written = 0;

   for (int row = 0; row < observationCount; ++row)
   {
      const int bar = observations[row].barIndex;
      const int executionIndex = bar - 1;
      StateSnapshot fastState;
      if (!ComputeStateSnapshotAtIndex(bar,
                                       fastLastValid,
                                       time,
                                       high,
                                       low,
                                       close,
                                       tickVolume,
                                       fastFlagBuffer,
                                       fastScoreBuffer,
                                       point,
                                       Eps(),
                                       fastConfig,
                                       fastState))
      {
         continue;
      }
      StateSnapshot slowState;
      if (!ComputeStateSnapshotAtIndex(bar,
                                       slowLastValid,
                                       time,
                                       high,
                                       low,
                                       close,
                                       tickVolume,
                                       slowFlagBuffer,
                                       slowScoreBuffer,
                                       point,
                                       Eps(),
                                       slowConfig,
                                       slowState))
      {
         continue;
      }

      const double actionExitPrice = label.entryPrice +
                                     (direction * observations[row].actionExitStep * step);
      string line = "";
      CsvAppendString(line, "1");
      CsvAppendTime(line, time[signalIndex]);
      CsvAppendTime(line, label.entryTime);
      CsvAppendTime(line, time[bar]);
      CsvAppendTime(line, time[executionIndex]);
      CsvAppendString(line, symbol);
      CsvAppendString(line, timeframeLabel);
      CsvAppendString(line, signalKind);
      CsvAppendInt(line, direction);
      CsvAppendInt(line, observations[row].holdBars);
      CsvAppendTime(line, label.exitTime);
      CsvAppendString(line, BarrierExitReasonToString(label.exitReason));
      CsvAppendDouble(line, step);
      CsvAppendDouble(line, close[bar]);
      CsvAppendDouble(line, actionExitPrice);
      CsvAppendDouble(line, observations[row].currentNetStep);
      CsvAppendDouble(line, observations[row].actionExitStep);
      CsvAppendDouble(line, observations[row].runningMfeStep);
      CsvAppendDouble(line, observations[row].runningMaeStep);
      CsvAppendDouble(line, observations[row].givebackStep);
      CsvAppendDouble(line, (double)observations[row].holdBars / InpMaxHoldBars);
      CsvAppendDouble(line, ((label.entryPrice - boundary) * direction) / step);
      CsvAppendDouble(line, ((close[bar] - boundary) * direction) / step);
      CsvAppendDouble(line,
                      ((close[bar] - entryFastState.lastBroken.mid) * direction) / step);
      CsvAppendDouble(line, ((close[bar] - open[bar]) * direction) / step);
      CsvAppendDouble(line, (high[bar] - low[bar]) / step);
      CsvAppendDouble(line, DirectionalCloseLocation(bar,
                                                     direction,
                                                     high,
                                                     low,
                                                     close));
      CsvAppendDouble(line, (spread[executionIndex] * point) / step);

      AppendExitHUDFeatures(line, fastState, direction);
      AppendExitHUDFeatures(line, slowState, direction);
      CsvAppendInt(line, OptionalAlignment(fastState.valid,
                                           (int)fastState.regime,
                                           slowState.valid,
                                           (int)slowState.regime));
      CsvAppendInt(line, OptionalAlignment(fastState.mainMetrics.valid,
                                           fastState.biasDir,
                                           slowState.mainMetrics.valid,
                                           slowState.biasDir));
      CsvAppendInt(line, OptionalAlignment(fastState.microMetrics.valid,
                                           fastState.microDir,
                                           slowState.microMetrics.valid,
                                           slowState.microDir));
      CsvAppendInt(line, OptionalAlignment(fastState.hasVolume,
                                           fastState.volumeState.bias,
                                           slowState.hasVolume,
                                           slowState.volumeState.bias));
      AppendExitHUDDeltas(line, fastState, entryFastState);
      AppendExitHUDDeltas(line, fastState, previousFastState);
      AppendExitHUDDeltas(line, slowState, entrySlowState);
      AppendExitHUDDeltas(line, slowState, previousSlowState);

      CsvAppendInt(line, label.success);
      CsvAppendDouble(line, label.netStepReturn);
      CsvAppendDouble(line, label.mfeStep);
      CsvAppendDouble(line, label.maeStep);
      CsvAppendDouble(line, observations[row].futureBestActionStep);
      CsvAppendDouble(line, observations[row].actionExitStep - label.netStepReturn);
      CsvAppendDouble(line,
                      observations[row].futureBestActionStep -
                      observations[row].actionExitStep);
      CsvAppendInt(line, (observations[row].peakActionRow ? 1 : 0));
      CsvAppendInt(line, (observations[row].finalMfeAlreadySeen ? 1 : 0));
      FileWriteString(fileHandle, line + "\r\n");

      previousFastState = fastState;
      previousSlowState = slowState;
      written++;
   }
   return written;
}

bool ValidateInputs()
{
   if (InpStateWindowFast < 2 || InpStateWindowSlow < 2 ||
       InpMicrotrendWindow < 2 || InpShortWindow < 2)
   {
      Print("XAUUSD ML export failed: state windows must be >= 2");
      return false;
   }

   if (InpRecentBreakoutWindow < 0 ||
       InpContinuationStepFraction < 0.0 ||
       InpRetestToleranceStepFraction < 0.0)
   {
      Print("XAUUSD ML export failed: breakout settings cannot be negative");
      return false;
   }

   if (InpStopStepMultiple <= 0.0 ||
       InpTargetStepMultiple <= 0.0 ||
       InpMaxHoldBars < 1 ||
       InpSlippagePoints < 0)
   {
      Print("XAUUSD ML export failed: invalid barrier or execution settings");
      return false;
   }

   if (InpIndicatorExitMinHoldBars < 1 ||
       InpIndicatorExitMinHoldBars >= InpMaxHoldBars ||
       InpExitInsideZoneStepFraction < 0.0 ||
       InpExitInsideZoneStepFraction > 1.0 ||
       InpExitExhaustionThreshold < 0.0 ||
       InpExitExhaustionThreshold > 1.0)
   {
      Print("XAUUSD ML export failed: invalid indicator-exit settings");
      return false;
   }

   if (InpATRLookback < 1 ||
       InpVolatilityLookback < 2 ||
       InpVolumeZScoreLookback < 2)
   {
      Print("XAUUSD ML export failed: invalid feature lookback");
      return false;
   }

   if (InpRequestedBars < 0 ||
       InpStartShift < 0 ||
       InpMaxRows < 0 ||
       StringLen(InpExportFileName) == 0 ||
       (InpExportExitPath && StringLen(InpExitPathFileName) == 0))
   {
      Print("XAUUSD ML export failed: invalid export slice or file name");
      return false;
   }

   if (!InpEnableImmediateBreakout &&
       !InpEnableRecentContinuation &&
       !InpEnableRetestBreakout)
   {
      Print("XAUUSD ML export failed: enable at least one signal kind");
      return false;
   }

   return true;
}

void OnStart()
{
   if (!ValidateInputs())
      return;

   const string symbol = ResolveExportSymbol();
   const ENUM_TIMEFRAMES timeframe = InpExportTimeframe;
   const string timeframeLabel = TimeframeToString(timeframe);

   double point = 0.0;
   if (!SymbolInfoDouble(symbol, SYMBOL_POINT, point) || point <= 0.0)
      point = (_Point > 0.0 ? _Point : 0.00001);

   datetime time[];
   double open[];
   double high[];
   double low[];
   double close[];
   long tickVolume[];
   int spread[];
   int ratesTotal = 0;
   if (!LoadRatesSeries(symbol,
                        timeframe,
                        time,
                        open,
                        high,
                        low,
                        close,
                        tickVolume,
                        spread,
                        ratesTotal))
   {
      return;
   }

   StateEngineConfig fastConfig;
   StateEngineConfig slowConfig;
   ConfigureStateEngine(fastConfig, InpStateWindowFast);
   ConfigureStateEngine(slowConfig, InpStateWindowSlow);

   double fastFlagBuffer[];
   double fastScoreBuffer[];
   ZoneInfo fastZoneCatalog[];
   int fastZoneCount = 0;
   int fastLastValid = -1;
   if (!PrepareStateWindowContext(ratesTotal,
                                  time,
                                  high,
                                  low,
                                  close,
                                  point,
                                  Eps(),
                                  fastConfig,
                                  fastFlagBuffer,
                                  fastScoreBuffer,
                                  fastZoneCatalog,
                                  fastZoneCount,
                                  fastLastValid))
   {
      Print("XAUUSD ML export failed: unable to prepare fast state context");
      return;
   }

   double slowFlagBuffer[];
   double slowScoreBuffer[];
   ZoneInfo slowZoneCatalog[];
   int slowZoneCount = 0;
   int slowLastValid = -1;
   if (!PrepareStateWindowContext(ratesTotal,
                                  time,
                                  high,
                                  low,
                                  close,
                                  point,
                                  Eps(),
                                  slowConfig,
                                  slowFlagBuffer,
                                  slowScoreBuffer,
                                  slowZoneCatalog,
                                  slowZoneCount,
                                  slowLastValid))
   {
      Print("XAUUSD ML export failed: unable to prepare slow state context");
      return;
   }

   const int featureLookback = MathMax(20,
                                       MathMax(InpATRLookback,
                                               MathMax(InpVolatilityLookback,
                                                       InpVolumeZScoreLookback)));
   int oldestIndex = MathMin(fastLastValid, slowLastValid);
   oldestIndex = MathMin(oldestIndex, ratesTotal - featureLookback - 1);
   const int mostRecentIndex = InpMaxHoldBars + InpStartShift;

   if (mostRecentIndex > oldestIndex)
   {
      PrintFormat("XAUUSD ML export failed: no valid rows for %s %s with windows %d/%d",
                  symbol,
                  timeframeLabel,
                  InpStateWindowFast,
                  InpStateWindowSlow);
      return;
   }

   int exportOldestIndex = oldestIndex;
   if (InpMaxRows > 0)
      exportOldestIndex = MathMin(oldestIndex, mostRecentIndex + InpMaxRows - 1);

   BreakoutExitState exitStates[];
   ArrayResize(exitStates, ratesTotal);
   for (int stateIndex = 0; stateIndex < ratesTotal; ++stateIndex)
      ResetBreakoutExitState(exitStates[stateIndex]);

   BreakoutCandidate candidates[];
   int acceptedCandidateCount = 0;
   int candidateEvents = 0;
   int duplicateEvents = 0;
   datetime lastImmediateBreak = 0;
   datetime lastContinuationBreak = 0;
   datetime lastRetestBreak = 0;

   // This first pass caches the compact indicator state needed by future exits.
   // It also collects candidates; labels are evaluated only after future states
   // are available, which avoids recalculating the state engine for every trade.
   for (int index = exportOldestIndex; index >= InpStartShift; --index)
   {
      StateSnapshot fastState;
      if (!ComputeStateSnapshotAtIndex(index,
                                       fastLastValid,
                                       time,
                                       high,
                                       low,
                                       close,
                                       tickVolume,
                                       fastFlagBuffer,
                                       fastScoreBuffer,
                                       point,
                                       Eps(),
                                       fastConfig,
                                       fastState))
      {
         continue;
      }

      BuildBreakoutExitState(fastState, exitStates[index]);
      if (index < mostRecentIndex)
         continue;

      string signalKind = "";
      int direction = 0;
      int breakoutAge = -1;
      if (!EvaluateBreakoutSetup(fastState,
                                 index,
                                 high,
                                 low,
                                 close,
                                 signalKind,
                                 direction,
                                 breakoutAge))
      {
         continue;
      }

      candidateEvents++;
      if (!AcceptUniqueEvent(signalKind,
                             fastState.lastBroken.t_break,
                             lastImmediateBreak,
                             lastContinuationBreak,
                             lastRetestBreak))
      {
         duplicateEvents++;
         continue;
      }

      AppendBreakoutCandidate(candidates,
                              acceptedCandidateCount,
                              index,
                              signalKind,
                              direction,
                              breakoutAge);
   }

   const int fileHandle = OpenExportFile();
   if (fileHandle == INVALID_HANDLE)
      return;

   WriteCsvHeader(fileHandle);

   int exitPathFileHandle = INVALID_HANDLE;
   if (InpExportExitPath)
   {
      exitPathFileHandle = OpenExitPathFile();
      if (exitPathFileHandle == INVALID_HANDLE)
      {
         FileClose(fileHandle);
         return;
      }
      WriteExitPathHeader(exitPathFileHandle);
   }

   int exportedEvents = 0;
   int exportedExitPathRows = 0;
   int ambiguousEvents = 0;
   int positiveEvents = 0;
   int stopExits = 0;
   int targetExits = 0;
   int timeoutExits = 0;
   int structureExits = 0;
   int flowReversalExits = 0;
   int exhaustionReversalExits = 0;

   for (int candidateIndex = 0; candidateIndex < acceptedCandidateCount; ++candidateIndex)
   {
      const int index = candidates[candidateIndex].index;
      const string signalKind = candidates[candidateIndex].signalKind;
      const int direction = candidates[candidateIndex].direction;
      const int breakoutAge = candidates[candidateIndex].breakoutAge;

      StateSnapshot fastState;
      if (!ComputeStateSnapshotAtIndex(index,
                                       fastLastValid,
                                       time,
                                       high,
                                       low,
                                       close,
                                       tickVolume,
                                       fastFlagBuffer,
                                       fastScoreBuffer,
                                       point,
                                       Eps(),
                                       fastConfig,
                                       fastState))
      {
         continue;
      }

      StateSnapshot slowState;
      if (!ComputeStateSnapshotAtIndex(index,
                                       slowLastValid,
                                       time,
                                       high,
                                       low,
                                       close,
                                       tickVolume,
                                       slowFlagBuffer,
                                       slowScoreBuffer,
                                       point,
                                       Eps(),
                                       slowConfig,
                                       slowState))
      {
         continue;
      }

      BarrierLabel label;
      if (!ComputeBarrierLabel(index,
                               direction,
                               fastState.step,
                               fastState.lastBroken,
                               exitStates,
                               time,
                               open,
                               high,
                               low,
                               close,
                               spread,
                               point,
                               label))
      {
         continue;
      }

      WriteEventRow(fileHandle,
                    symbol,
                    timeframeLabel,
                    index,
                    signalKind,
                    direction,
                    breakoutAge,
                    fastState,
                    slowState,
                    time,
                    open,
                    high,
                    low,
                    close,
                    tickVolume,
                    spread,
                    point,
                    label);

      if (exitPathFileHandle != INVALID_HANDLE)
      {
         exportedExitPathRows += WriteExitPathRows(exitPathFileHandle,
                                                   symbol,
                                                   timeframeLabel,
                                                   index,
                                                   signalKind,
                                                   direction,
                                                   fastState,
                                                   slowState,
                                                   label,
                                                   fastLastValid,
                                                   slowLastValid,
                                                   time,
                                                   open,
                                                   high,
                                                   low,
                                                   close,
                                                   tickVolume,
                                                   spread,
                                                   fastFlagBuffer,
                                                   fastScoreBuffer,
                                                   slowFlagBuffer,
                                                   slowScoreBuffer,
                                                   point,
                                                   fastConfig,
                                                   slowConfig);
      }

      exportedEvents++;
      if (label.success == 1)
         positiveEvents++;
      if (label.ambiguousBar)
         ambiguousEvents++;
      if (label.exitReason == BARRIER_EXIT_STOP)
         stopExits++;
      else if (label.exitReason == BARRIER_EXIT_TARGET)
         targetExits++;
      else if (label.exitReason == BARRIER_EXIT_STRUCTURE)
         structureExits++;
      else if (label.exitReason == BARRIER_EXIT_FLOW_REVERSAL)
         flowReversalExits++;
      else if (label.exitReason == BARRIER_EXIT_EXHAUSTION_REVERSAL)
         exhaustionReversalExits++;
      else
         timeoutExits++;
   }

   FileFlush(fileHandle);
   FileClose(fileHandle);
   if (exitPathFileHandle != INVALID_HANDLE)
   {
      FileFlush(exitPathFileHandle);
      FileClose(exitPathFileHandle);
   }

   PrintFormat("XAUUSD ML export complete: events=%d exit_path_rows=%d positive=%d candidates=%d accepted=%d duplicates_skipped=%d ambiguous=%d exits[stop=%d target=%d structure=%d flow=%d exhaustion=%d timeout=%d] file=%s exit_path_file=%s folder=%s symbol=%s timeframe=%s",
               exportedEvents,
               exportedExitPathRows,
               positiveEvents,
               candidateEvents,
               acceptedCandidateCount,
               duplicateEvents,
               ambiguousEvents,
               stopExits,
               targetExits,
               structureExits,
               flowReversalExits,
               exhaustionReversalExits,
               timeoutExits,
               InpExportFileName,
               (InpExportExitPath ? InpExitPathFileName : "DISABLED"),
               (InpUseCommonFolder ? "COMMON" : "LOCAL"),
               symbol,
               timeframeLabel);
}
