//+------------------------------------------------------------------+
//| BacktestMarketRegimeBreakout.mq5                                 |
//| Research backtest for MarketRegime breakout continuation         |
//+------------------------------------------------------------------+
#property copyright "Vagner Ribeiro"
#property link "https://www.mql5.com"
#property version "1.00"
#property script_show_inputs
#property strict

#include "../Core/StateEngine.mqh"
#include "../Core/BreakoutExit.mqh"

enum ENUM_BREAKOUT_RESEARCH_MODE
{
   BREAKOUT_MODE_SIMPLE = 0,
   BREAKOUT_MODE_FILTERED = 1,
   BREAKOUT_MODE_BOTH = 2
};

enum ENUM_EXIT_REASON
{
   EXIT_REASON_NONE = 0,
   EXIT_REASON_STOP = 1,
   EXIT_REASON_TARGET = 2,
   EXIT_REASON_TIMEOUT = 3,
   EXIT_REASON_DATA_END = 4,
   EXIT_REASON_STRUCTURE = 5,
   EXIT_REASON_FLOW_REVERSAL = 6,
   EXIT_REASON_EXHAUSTION_REVERSAL = 7
};

struct PendingSignal
{
   bool active;
   string modeLabel;
   string signalKind;
   int direction;
   int signalBar;
   datetime signalTime;
   double strength01;
   double breakQuality01;
   double volumeConfirm01;
   double exhaustion01;
   double step;
   double signalZoneTop;
   double signalZoneBottom;
   ENUM_REGIME_STATE regime;
   int biasDir;
   int volumeBiasDir;
};

struct PositionState
{
   bool active;
   string modeLabel;
   string signalKind;
   int direction;
   int signalBar;
   int entryBar;
   datetime signalTime;
   datetime entryTime;
   double signalStrength01;
   double signalBreakQuality01;
   double signalVolumeConfirm01;
   double signalExhaustion01;
   double step;
   double signalZoneTop;
   double signalZoneBottom;
   ENUM_REGIME_STATE regime;
   int biasDir;
   int volumeBiasDir;
   double grossEntryPrice;
   double netEntryPrice;
   double stopPrice;
   double targetPrice;
   int holdBars;
   ENUM_BREAKOUT_INDICATOR_EXIT pendingIndicatorExit;
};

struct TradeRecord
{
   string modeLabel;
   string signalKind;
   datetime signalTime;
   datetime entryTime;
   datetime exitTime;
   int direction;
   string regimeLabel;
   string biasLabel;
   string volumeBiasLabel;
   double strength01;
   double breakQuality01;
   double volumeConfirm01;
   double exhaustion01;
   double step;
   double grossEntryPrice;
   double entryPrice;
   double stopPrice;
   double targetPrice;
   double grossExitPrice;
   double exitPrice;
   string exitReason;
   int holdBars;
   double grossPoints;
   double netPoints;
   double grossPriceMove;
   double netPriceMove;
};

struct BacktestStats
{
   string modeLabel;
   int trades;
   int wins;
   int losses;
   double grossPointsTotal;
   double netPointsTotal;
   double winNetPointsTotal;
   double lossNetPointsTotalAbs;
   double equityPoints;
   double peakEquityPoints;
   double maxDrawdownPoints;
   int currentLosingStreak;
   int maxLosingStreak;
};

struct ExperimentConfig
{
   string experimentId;
   ENUM_BREAKOUT_RESEARCH_MODE mode;
   string modeLabel;
   double minStrength;
   double minBreakQuality;
   double minVolumeConfirm;
   double maxExhaustion;
   double stopStepMultiple;
   double targetStepMultiple;
   int maxHoldBars;
   bool indicatorExitEnabled;
   bool structureExitEnabled;
   bool flowReversalExitEnabled;
   bool exhaustionReversalExitEnabled;
   int indicatorExitMinHoldBars;
   double exitInsideZoneStepFraction;
   double exitExhaustionThreshold;
   int recentBreakoutWindow;
   double continuationStepFraction;
   double retestToleranceStepFraction;
   string exportFileName;
};

input string InpBacktestSymbol = "XAUUSD";
input ENUM_TIMEFRAMES InpBacktestTimeframe = PERIOD_M1;
input ENUM_BREAKOUT_RESEARCH_MODE InpResearchMode = BREAKOUT_MODE_BOTH;
input bool InpRunExperimentSuite = true;
input string InpSuiteName = "v8";
input string InpExportSummaryFileName = "mrz_v8_summary.csv";

input int InpStateWindow = 120;
input int InpMicrotrendWindow = 30;
input int InpShortWindow = 20;

input double InpMinStrength = 0.05;
input double InpMinBreakQuality = 0.18;
input double InpMinVolumeConfirm = 0.12;
input double InpMaxExhaustion = 0.45;

input double InpStopStepMultiple = 0.80;
input double InpTargetStepMultiple = 0.80;
input int InpMaxHoldBars = 20;

input bool InpEnableIndicatorExit = false;
input bool InpEnableStructureExit = true;
input bool InpEnableFlowReversalExit = false;
input bool InpEnableExhaustionReversalExit = false;
input int InpIndicatorExitMinHoldBars = 1;
input double InpExitInsideZoneStepFraction = 0.50;
input double InpExitExhaustionThreshold = 0.65;

input bool InpEnableImmediateBreakout = true;
input bool InpEnableRecentContinuation = true;
input bool InpEnableRetestBreakout = true;
input int InpRecentBreakoutWindow = 6;
input double InpContinuationStepFraction = 0.05;
input double InpRetestToleranceStepFraction = 0.20;

input int InpSlippagePoints = 5;
input string InpExportFileName = "market_regime_breakout_backtest.csv";
input bool InpUseCommonFolder = false;

input int InpStartShift = 0;
input int InpMaxRows = 0;

double gMinStrength = 0.0;
double gMinBreakQuality = 0.0;
double gMinVolumeConfirm = 0.0;
double gMaxExhaustion = 1.0;
double gStopStepMultiple = 1.0;
double gTargetStepMultiple = 1.5;
int gMaxHoldBars = 12;
bool gEnableIndicatorExit = false;
bool gEnableStructureExit = true;
bool gEnableFlowReversalExit = false;
bool gEnableExhaustionReversalExit = false;
int gIndicatorExitMinHoldBars = 1;
double gExitInsideZoneStepFraction = 0.50;
double gExitExhaustionThreshold = 0.65;
bool gEnableImmediateBreakout = true;
bool gEnableRecentContinuation = true;
bool gEnableRetestBreakout = true;
int gRecentBreakoutWindow = 6;
double gContinuationStepFraction = 0.05;
double gRetestToleranceStepFraction = 0.20;

double Eps()
{
   return 1.0e-12;
}

double MissingNumber()
{
   return -1.0;
}

string ResolveBacktestSymbol()
{
   if (StringLen(InpBacktestSymbol) > 0)
      return InpBacktestSymbol;
   return _Symbol;
}

void ResetPendingSignal(PendingSignal &signal)
{
   signal.active = false;
   signal.modeLabel = "";
   signal.signalKind = "";
   signal.direction = 0;
   signal.signalBar = -1;
   signal.signalTime = 0;
   signal.strength01 = 0.0;
   signal.breakQuality01 = 0.0;
   signal.volumeConfirm01 = 0.0;
   signal.exhaustion01 = 0.0;
   signal.step = 0.0;
   signal.signalZoneTop = 0.0;
   signal.signalZoneBottom = 0.0;
   signal.regime = REGIME_MIXED;
   signal.biasDir = 0;
   signal.volumeBiasDir = 0;
}

void ResetPositionState(PositionState &position)
{
   position.active = false;
   position.modeLabel = "";
   position.signalKind = "";
   position.direction = 0;
   position.signalBar = -1;
   position.entryBar = -1;
   position.signalTime = 0;
   position.entryTime = 0;
   position.signalStrength01 = 0.0;
   position.signalBreakQuality01 = 0.0;
   position.signalVolumeConfirm01 = 0.0;
   position.signalExhaustion01 = 0.0;
   position.step = 0.0;
   position.signalZoneTop = 0.0;
   position.signalZoneBottom = 0.0;
   position.regime = REGIME_MIXED;
   position.biasDir = 0;
   position.volumeBiasDir = 0;
   position.grossEntryPrice = 0.0;
   position.netEntryPrice = 0.0;
   position.stopPrice = 0.0;
   position.targetPrice = 0.0;
   position.holdBars = 0;
   position.pendingIndicatorExit = BREAKOUT_INDICATOR_EXIT_NONE;
}

string ExitReasonToString(const ENUM_EXIT_REASON reason)
{
   switch (reason)
   {
      case EXIT_REASON_STOP:
         return "STOP";
      case EXIT_REASON_TARGET:
         return "TARGET";
      case EXIT_REASON_TIMEOUT:
         return "TIMEOUT";
      case EXIT_REASON_DATA_END:
         return "DATA_END";
      case EXIT_REASON_STRUCTURE:
         return "STRUCTURE";
      case EXIT_REASON_FLOW_REVERSAL:
         return "FLOW_REVERSAL";
      case EXIT_REASON_EXHAUSTION_REVERSAL:
         return "EXHAUSTION_REVERSAL";
      default:
         return "N/A";
   }
}

ENUM_EXIT_REASON IndicatorExitToExitReason(const ENUM_BREAKOUT_INDICATOR_EXIT reason)
{
   if (reason == BREAKOUT_INDICATOR_EXIT_STRUCTURE)
      return EXIT_REASON_STRUCTURE;
   if (reason == BREAKOUT_INDICATOR_EXIT_FLOW_REVERSAL)
      return EXIT_REASON_FLOW_REVERSAL;
   if (reason == BREAKOUT_INDICATOR_EXIT_EXHAUSTION_REVERSAL)
      return EXIT_REASON_EXHAUSTION_REVERSAL;
   return EXIT_REASON_NONE;
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
      PrintFormat("Breakout backtest failed: unable to select symbol %s", symbol);
      return false;
   }

   const int availableBars = Bars(symbol, timeframe);
   if (availableBars <= 0)
   {
      PrintFormat("Breakout backtest failed: no bars available for %s %s", symbol, TimeframeToString(timeframe));
      return false;
   }

   int requestedBars = availableBars;
   if (InpMaxRows > 0)
   {
      const int stateMargin = MathMax(InpStateWindow,
                                      MathMax(InpMicrotrendWindow,
                                              MathMax(InpShortWindow, 60)));
      requestedBars = MathMin(availableBars, InpMaxRows + stateMargin + 2);
   }

   MqlRates rates[];
   ResetLastError();
   const int copied = CopyRates(symbol, timeframe, 0, requestedBars, rates);
   if (copied <= 0)
   {
      PrintFormat("Breakout backtest failed: CopyRates returned %d for %s %s (error %d)",
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

bool ModeEnabled(const ENUM_BREAKOUT_RESEARCH_MODE selectedMode,
                 const ENUM_BREAKOUT_RESEARCH_MODE checkMode)
{
   return (selectedMode == BREAKOUT_MODE_BOTH || selectedMode == checkMode);
}

void ConfigureStateEngine(StateEngineConfig &config)
{
   InitializeStateEngineConfig(config, InpStateWindow);
   config.microtrendWindow = MathMax(2, InpMicrotrendWindow);
   config.shortWindow = MathMax(2, InpShortWindow);
}

void LoadRuntimeParametersFromInputs()
{
   gMinStrength = InpMinStrength;
   gMinBreakQuality = InpMinBreakQuality;
   gMinVolumeConfirm = InpMinVolumeConfirm;
   gMaxExhaustion = InpMaxExhaustion;
   gStopStepMultiple = InpStopStepMultiple;
   gTargetStepMultiple = InpTargetStepMultiple;
   gMaxHoldBars = InpMaxHoldBars;
   gEnableIndicatorExit = InpEnableIndicatorExit;
   gEnableStructureExit = InpEnableStructureExit;
   gEnableFlowReversalExit = InpEnableFlowReversalExit;
   gEnableExhaustionReversalExit = InpEnableExhaustionReversalExit;
   gIndicatorExitMinHoldBars = InpIndicatorExitMinHoldBars;
   gExitInsideZoneStepFraction = InpExitInsideZoneStepFraction;
   gExitExhaustionThreshold = InpExitExhaustionThreshold;
   gEnableImmediateBreakout = InpEnableImmediateBreakout;
   gEnableRecentContinuation = InpEnableRecentContinuation;
   gEnableRetestBreakout = InpEnableRetestBreakout;
   gRecentBreakoutWindow = InpRecentBreakoutWindow;
   gContinuationStepFraction = InpContinuationStepFraction;
   gRetestToleranceStepFraction = InpRetestToleranceStepFraction;
}

void LoadRuntimeParametersFromExperiment(const ExperimentConfig &config)
{
   gMinStrength = config.minStrength;
   gMinBreakQuality = config.minBreakQuality;
   gMinVolumeConfirm = config.minVolumeConfirm;
   gMaxExhaustion = config.maxExhaustion;
   gStopStepMultiple = config.stopStepMultiple;
   gTargetStepMultiple = config.targetStepMultiple;
   gMaxHoldBars = config.maxHoldBars;
   gEnableIndicatorExit = config.indicatorExitEnabled;
   gEnableStructureExit = config.structureExitEnabled;
   gEnableFlowReversalExit = config.flowReversalExitEnabled;
   gEnableExhaustionReversalExit = config.exhaustionReversalExitEnabled;
   gIndicatorExitMinHoldBars = config.indicatorExitMinHoldBars;
   gExitInsideZoneStepFraction = config.exitInsideZoneStepFraction;
   gExitExhaustionThreshold = config.exitExhaustionThreshold;
   gEnableImmediateBreakout = true;
   gEnableRecentContinuation = true;
   gEnableRetestBreakout = true;
   gRecentBreakoutWindow = config.recentBreakoutWindow;
   gContinuationStepFraction = config.continuationStepFraction;
   gRetestToleranceStepFraction = config.retestToleranceStepFraction;
}

void InitializeStats(BacktestStats &stats,
                     const string modeLabel)
{
   stats.modeLabel = modeLabel;
   stats.trades = 0;
   stats.wins = 0;
   stats.losses = 0;
   stats.grossPointsTotal = 0.0;
   stats.netPointsTotal = 0.0;
   stats.winNetPointsTotal = 0.0;
   stats.lossNetPointsTotalAbs = 0.0;
   stats.equityPoints = 0.0;
   stats.peakEquityPoints = 0.0;
   stats.maxDrawdownPoints = 0.0;
   stats.currentLosingStreak = 0;
   stats.maxLosingStreak = 0;
}

int OpenCsvFile(const string fileName)
{
   int flags = FILE_WRITE | FILE_CSV | FILE_ANSI;
   if (InpUseCommonFolder)
      flags |= FILE_COMMON;

   ResetLastError();
   const int fileHandle = FileOpen(fileName, flags, ',');
   if (fileHandle == INVALID_HANDLE)
      PrintFormat("Breakout backtest failed: unable to open %s (error %d)", fileName, GetLastError());

   return fileHandle;
}

int OpenTradesFile(const string fileName)
{
   return OpenCsvFile(fileName);
}

void WriteTradesHeader(const int fileHandle)
{
   FileWrite(fileHandle,
             "mode",
             "signal_kind",
             "signal_time",
             "entry_time",
             "exit_time",
             "direction",
             "regime",
             "bias",
             "volume_bias",
             "strength",
             "break_quality",
             "volume_confirm",
             "exhaustion",
             "step",
             "gross_entry_price",
             "entry_price",
             "stop_price",
             "target_price",
             "gross_exit_price",
             "exit_price",
             "exit_reason",
             "hold_bars",
             "gross_points",
             "net_points",
             "gross_price_move",
             "net_price_move");
}

void WriteSummaryHeader(const int fileHandle)
{
   FileWrite(fileHandle,
             "experiment_id",
             "mode",
             "min_strength",
             "min_break_quality",
             "min_volume_confirm",
             "max_exhaustion",
             "stop_step_multiple",
             "target_step_multiple",
             "max_hold_bars",
             "indicator_exit_enabled",
             "structure_exit_enabled",
             "flow_reversal_exit_enabled",
             "exhaustion_reversal_exit_enabled",
             "indicator_exit_min_hold_bars",
             "exit_inside_zone_step_fraction",
             "exit_exhaustion_threshold",
             "recent_breakout_window",
             "continuation_step_fraction",
             "retest_tolerance_step_fraction",
             "trades",
             "wins",
             "losses",
             "win_rate",
             "net_points",
             "avg_net_points",
             "avg_win_points",
             "avg_loss_points",
             "payoff",
             "profit_factor",
             "max_drawdown_points",
             "max_losing_streak");
}

void AppendTrade(TradeRecord &trades[],
                 int &tradeCount,
                 const TradeRecord &trade)
{
   ArrayResize(trades, tradeCount + 1);
   trades[tradeCount] = trade;
   ++tradeCount;
}

void UpdateStats(BacktestStats &stats,
                 const TradeRecord &trade)
{
   stats.trades++;
   stats.grossPointsTotal += trade.grossPoints;
   stats.netPointsTotal += trade.netPoints;
   stats.equityPoints += trade.netPoints;

   if (stats.equityPoints > stats.peakEquityPoints)
      stats.peakEquityPoints = stats.equityPoints;

   const double drawdown = stats.peakEquityPoints - stats.equityPoints;
   if (drawdown > stats.maxDrawdownPoints)
      stats.maxDrawdownPoints = drawdown;

   if (trade.netPoints > 0.0)
   {
      stats.wins++;
      stats.winNetPointsTotal += trade.netPoints;
      stats.currentLosingStreak = 0;
   }
   else if (trade.netPoints < 0.0)
   {
      stats.losses++;
      stats.lossNetPointsTotalAbs += MathAbs(trade.netPoints);
      stats.currentLosingStreak++;
      if (stats.currentLosingStreak > stats.maxLosingStreak)
         stats.maxLosingStreak = stats.currentLosingStreak;
   }
}

void WriteTradeRow(const int fileHandle,
                   const TradeRecord &trade)
{
   FileWrite(fileHandle,
             trade.modeLabel,
             trade.signalKind,
             TimeToString(trade.signalTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
             TimeToString(trade.entryTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
             TimeToString(trade.exitTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
             DirectionToString(trade.direction),
             trade.regimeLabel,
             trade.biasLabel,
             trade.volumeBiasLabel,
             trade.strength01,
             trade.breakQuality01,
             trade.volumeConfirm01,
             trade.exhaustion01,
             trade.step,
             trade.grossEntryPrice,
             trade.entryPrice,
             trade.stopPrice,
             trade.targetPrice,
             trade.grossExitPrice,
             trade.exitPrice,
             trade.exitReason,
             trade.holdBars,
             trade.grossPoints,
             trade.netPoints,
             trade.grossPriceMove,
             trade.netPriceMove);
}

double StatsWinRate(const BacktestStats &stats)
{
   return (stats.trades > 0 ? (100.0 * stats.wins / stats.trades) : 0.0);
}

double StatsAverageWin(const BacktestStats &stats)
{
   return (stats.wins > 0 ? stats.winNetPointsTotal / stats.wins : 0.0);
}

double StatsAverageLossAbs(const BacktestStats &stats)
{
   return (stats.losses > 0 ? stats.lossNetPointsTotalAbs / stats.losses : 0.0);
}

double StatsPayoff(const BacktestStats &stats)
{
   const double avgLossAbs = StatsAverageLossAbs(stats);
   return (avgLossAbs > Eps() ? StatsAverageWin(stats) / avgLossAbs : 0.0);
}

double StatsExpectancy(const BacktestStats &stats)
{
   return (stats.trades > 0 ? stats.netPointsTotal / stats.trades : 0.0);
}

double StatsProfitFactor(const BacktestStats &stats)
{
   return (stats.lossNetPointsTotalAbs > Eps() ? stats.winNetPointsTotal / stats.lossNetPointsTotalAbs : 0.0);
}

void WriteSummaryRow(const int fileHandle,
                     const ExperimentConfig &config,
                     const BacktestStats &stats)
{
   FileWrite(fileHandle,
             config.experimentId,
             config.modeLabel,
             config.minStrength,
             config.minBreakQuality,
             config.minVolumeConfirm,
             config.maxExhaustion,
             config.stopStepMultiple,
             config.targetStepMultiple,
             config.maxHoldBars,
             (config.indicatorExitEnabled ? 1 : 0),
             (config.structureExitEnabled ? 1 : 0),
             (config.flowReversalExitEnabled ? 1 : 0),
             (config.exhaustionReversalExitEnabled ? 1 : 0),
             config.indicatorExitMinHoldBars,
             config.exitInsideZoneStepFraction,
             config.exitExhaustionThreshold,
             config.recentBreakoutWindow,
             config.continuationStepFraction,
             config.retestToleranceStepFraction,
             stats.trades,
             stats.wins,
             stats.losses,
             StatsWinRate(stats),
             stats.netPointsTotal,
             StatsExpectancy(stats),
             StatsAverageWin(stats),
             -StatsAverageLossAbs(stats),
             StatsPayoff(stats),
             StatsProfitFactor(stats),
             stats.maxDrawdownPoints,
             stats.maxLosingStreak);
}

bool IsBreakoutDirectionMatch(const StateSnapshot &snapshot,
                              const int direction)
{
   if (!snapshot.hasBrokenZone)
      return false;

   if (direction > 0)
      return (snapshot.lastBroken.state == Z_BREAK_UP);
   if (direction < 0)
      return (snapshot.lastBroken.state == Z_BREAK_DOWN);
   return false;
}

bool HasFreshBreakout(const StateSnapshot &snapshot,
                      const int index)
{
   return (snapshot.hasBrokenZone &&
           snapshot.lastBroken.breakIndex == index &&
           snapshot.hasStep &&
           snapshot.step > Eps() &&
           snapshot.stepSource == STEP_SOURCE_LAST_BROKEN);
}

bool HasRecentBreakout(const StateSnapshot &snapshot,
                       const int index,
                       int &direction,
                       int &breakoutAge)
{
   direction = 0;
   breakoutAge = -1;

   if (!snapshot.valid || !snapshot.hasBrokenZone || !snapshot.hasStep || snapshot.step <= Eps() || snapshot.stepSource != STEP_SOURCE_LAST_BROKEN)
      return false;

   if (snapshot.lastBroken.state == Z_BREAK_UP)
      direction = 1;
   else if (snapshot.lastBroken.state == Z_BREAK_DOWN)
      direction = -1;

   if (direction == 0)
      return false;

   breakoutAge = snapshot.lastBroken.breakIndex - index;
   return (breakoutAge >= 0 && breakoutAge <= gRecentBreakoutWindow);
}

bool PassesFilteredGate(const StateSnapshot &snapshot,
                        const int direction)
{
   if (!snapshot.valid || snapshot.regime == REGIME_RANGE)
      return false;
   if (!snapshot.hasStrength || snapshot.strength01 < gMinStrength)
      return false;
   if (!snapshot.hasBreakQuality || snapshot.breakQuality01 < gMinBreakQuality)
      return false;
   if (!snapshot.hasExhaustion || snapshot.exhaustion01 > gMaxExhaustion)
      return false;
   if (!snapshot.hasVolume || snapshot.volumeState.confirmation01 < gMinVolumeConfirm)
      return false;
   if (snapshot.biasDir != 0 && snapshot.biasDir != direction)
      return false;

   return true;
}

bool EvaluateBreakoutSetup(const StateSnapshot &snapshot,
                           const int index,
                           const double &high[],
                           const double &low[],
                           const double &close[],
                           string &signalKind,
                           int &direction)
{
   signalKind = "";
   direction = 0;

   int breakoutAge = -1;
   if (!HasRecentBreakout(snapshot, index, direction, breakoutAge))
      return false;

   const double step = snapshot.step;
   const double retestTol = step * gRetestToleranceStepFraction;
   const double continuationLevel = step * gContinuationStepFraction;

   if (breakoutAge == 0 && gEnableImmediateBreakout)
   {
      signalKind = "IMMEDIATE";
      return true;
   }

   if (breakoutAge > 0 && gEnableRetestBreakout)
   {
      if (direction > 0 &&
          low[index] <= (snapshot.lastBroken.top + retestTol) &&
          close[index] > snapshot.lastBroken.top)
      {
         signalKind = "RETEST";
         return true;
      }

      if (direction < 0 &&
          high[index] >= (snapshot.lastBroken.bottom - retestTol) &&
          close[index] < snapshot.lastBroken.bottom)
      {
         signalKind = "RETEST";
         return true;
      }
   }

   if (breakoutAge > 0 && gEnableRecentContinuation)
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

bool HasSimpleSignal(const StateSnapshot &snapshot,
                     const int index,
                     const double &high[],
                     const double &low[],
                     const double &close[],
                     string &signalKind,
                     int &direction)
{
   return EvaluateBreakoutSetup(snapshot, index, high, low, close, signalKind, direction);
}

bool HasFilteredSignal(const StateSnapshot &snapshot,
                       const int index,
                       const double &high[],
                       const double &low[],
                       const double &close[],
                       string &signalKind,
                       int &direction)
{
   if (!EvaluateBreakoutSetup(snapshot, index, high, low, close, signalKind, direction))
      return false;
   return PassesFilteredGate(snapshot, direction);
}

bool BuildSignal(const string modeLabel,
                 const ENUM_BREAKOUT_RESEARCH_MODE mode,
                 const StateSnapshot &snapshot,
                 const int index,
                 const double &high[],
                 const double &low[],
                 const double &close[],
                 const datetime signalTime,
                 PendingSignal &signal)
{
   int direction = 0;
   bool hasSignal = false;
   string signalKind = "";

   if (mode == BREAKOUT_MODE_SIMPLE)
      hasSignal = HasSimpleSignal(snapshot, index, high, low, close, signalKind, direction);
   else if (mode == BREAKOUT_MODE_FILTERED)
      hasSignal = HasFilteredSignal(snapshot, index, high, low, close, signalKind, direction);

   if (!hasSignal)
      return false;

   signal.active = true;
   signal.modeLabel = modeLabel;
   signal.signalKind = signalKind;
   signal.direction = direction;
   signal.signalBar = index;
   signal.signalTime = signalTime;
   signal.strength01 = (snapshot.hasStrength ? snapshot.strength01 : MissingNumber());
   signal.breakQuality01 = (snapshot.hasBreakQuality ? snapshot.breakQuality01 : MissingNumber());
   signal.volumeConfirm01 = (snapshot.hasVolume ? snapshot.volumeState.confirmation01 : MissingNumber());
   signal.exhaustion01 = (snapshot.hasExhaustion ? snapshot.exhaustion01 : MissingNumber());
   signal.step = snapshot.step;
   signal.signalZoneTop = snapshot.lastBroken.top;
   signal.signalZoneBottom = snapshot.lastBroken.bottom;
   signal.regime = snapshot.regime;
   signal.biasDir = snapshot.biasDir;
   signal.volumeBiasDir = (snapshot.hasVolume ? snapshot.volumeState.bias : 0);
   return true;
}

void OpenPositionFromSignal(const PendingSignal &signal,
                            const int entryBar,
                            const datetime &time[],
                            const double &open[],
                            const int &spread[],
                            const double point,
                            PositionState &position)
{
   ResetPositionState(position);

   const double slippagePrice = InpSlippagePoints * point;
   const double entrySpreadPrice = spread[entryBar] * point;

   position.active = true;
   position.modeLabel = signal.modeLabel;
   position.signalKind = signal.signalKind;
   position.direction = signal.direction;
   position.signalBar = signal.signalBar;
   position.entryBar = entryBar;
   position.signalTime = signal.signalTime;
   position.entryTime = time[entryBar];
   position.signalStrength01 = signal.strength01;
   position.signalBreakQuality01 = signal.breakQuality01;
   position.signalVolumeConfirm01 = signal.volumeConfirm01;
   position.signalExhaustion01 = signal.exhaustion01;
   position.step = signal.step;
   position.signalZoneTop = signal.signalZoneTop;
   position.signalZoneBottom = signal.signalZoneBottom;
   position.regime = signal.regime;
   position.biasDir = signal.biasDir;
   position.volumeBiasDir = signal.volumeBiasDir;
   position.grossEntryPrice = open[entryBar];

   if (position.direction > 0)
      position.netEntryPrice = open[entryBar] + entrySpreadPrice + slippagePrice;
   else
      position.netEntryPrice = open[entryBar] - slippagePrice;

   position.stopPrice = position.netEntryPrice - (position.direction * (gStopStepMultiple * position.step));
   position.targetPrice = position.netEntryPrice + (position.direction * (gTargetStepMultiple * position.step));
   position.holdBars = 0;
   position.pendingIndicatorExit = BREAKOUT_INDICATOR_EXIT_NONE;
}

void FinalizeTrade(PositionState &position,
                   const int bar,
                   const datetime exitTime,
                   const double grossExitPrice,
                   const double netExitPrice,
                   const ENUM_EXIT_REASON exitReason,
                   const double point,
                   TradeRecord &trade)
{
   trade.modeLabel = position.modeLabel;
   trade.signalKind = position.signalKind;
   trade.signalTime = position.signalTime;
   trade.entryTime = position.entryTime;
   trade.exitTime = exitTime;
   trade.direction = position.direction;
   trade.regimeLabel = RegimeToString(position.regime);
   trade.biasLabel = DirectionToString(position.biasDir);
   trade.volumeBiasLabel = DirectionToString(position.volumeBiasDir);
   trade.strength01 = position.signalStrength01;
   trade.breakQuality01 = position.signalBreakQuality01;
   trade.volumeConfirm01 = position.signalVolumeConfirm01;
   trade.exhaustion01 = position.signalExhaustion01;
   trade.step = position.step;
   trade.grossEntryPrice = position.grossEntryPrice;
   trade.entryPrice = position.netEntryPrice;
   trade.stopPrice = position.stopPrice;
   trade.targetPrice = position.targetPrice;
   trade.grossExitPrice = grossExitPrice;
   trade.exitPrice = netExitPrice;
   trade.exitReason = ExitReasonToString(exitReason);
   trade.holdBars = position.holdBars;
   trade.grossPriceMove = (grossExitPrice - position.grossEntryPrice) * position.direction;
   trade.netPriceMove = (netExitPrice - position.netEntryPrice) * position.direction;
   trade.grossPoints = trade.grossPriceMove / point;
   trade.netPoints = trade.netPriceMove / point;

   ResetPositionState(position);
}

bool ExecutePendingIndicatorExitAtOpen(PositionState &position,
                                       const int bar,
                                       const datetime &time[],
                                       const double &open[],
                                       const int &spread[],
                                       const double point,
                                       TradeRecord &trade)
{
   if (!position.active || position.pendingIndicatorExit == BREAKOUT_INDICATOR_EXIT_NONE)
      return false;

   const ENUM_EXIT_REASON exitReason = IndicatorExitToExitReason(position.pendingIndicatorExit);
   if (exitReason == EXIT_REASON_NONE)
      return false;

   const double slippagePrice = InpSlippagePoints * point;
   const double exitSpreadPrice = spread[bar] * point;
   const double grossExitPrice = open[bar];
   const double netExitPrice = (position.direction > 0
                                ? open[bar] - slippagePrice
                                : open[bar] + exitSpreadPrice + slippagePrice);
   FinalizeTrade(position,
                 bar,
                 time[bar],
                 grossExitPrice,
                 netExitPrice,
                 exitReason,
                 point,
                 trade);
   return true;
}

void ScheduleIndicatorExitOnClose(PositionState &position,
                                  const int bar,
                                  const double &close[],
                                  const StateSnapshot &snapshot)
{
   if (!position.active || position.pendingIndicatorExit != BREAKOUT_INDICATOR_EXIT_NONE)
      return;

   BreakoutExitState exitState;
   BuildBreakoutExitState(snapshot, exitState);
   position.pendingIndicatorExit = EvaluateBreakoutIndicatorExit(position.direction,
                                                                  position.holdBars,
                                                                  position.signalZoneTop,
                                                                  position.signalZoneBottom,
                                                                  position.step,
                                                                  close[bar],
                                                                  exitState,
                                                                  gEnableIndicatorExit,
                                                                  gEnableStructureExit,
                                                                  gEnableFlowReversalExit,
                                                                  gEnableExhaustionReversalExit,
                                                                  gIndicatorExitMinHoldBars,
                                                                  gExitInsideZoneStepFraction,
                                                                  gExitExhaustionThreshold,
                                                                  Eps());
}

bool EvaluateExitOnBar(PositionState &position,
                       const int bar,
                       const datetime &time[],
                       const double &high[],
                       const double &low[],
                       const double &close[],
                       const int &spread[],
                       const double point,
                       TradeRecord &trade)
{
   if (!position.active)
      return false;

   const double slippagePrice = InpSlippagePoints * point;
   const double exitSpreadPrice = spread[bar] * point;
   position.holdBars++;

   const bool stopHit = (position.direction > 0 ? low[bar] <= position.stopPrice : high[bar] >= position.stopPrice);
   const bool targetHit = (position.direction > 0 ? high[bar] >= position.targetPrice : low[bar] <= position.targetPrice);

   if (stopHit)
   {
      const double grossExitPrice = position.stopPrice;
      const double netExitPrice = (position.direction > 0
                                   ? position.stopPrice - slippagePrice
                                   : position.stopPrice + exitSpreadPrice + slippagePrice);
      FinalizeTrade(position, bar, time[bar], grossExitPrice, netExitPrice, EXIT_REASON_STOP, point, trade);
      return true;
   }

   if (targetHit)
   {
      const double grossExitPrice = position.targetPrice;
      const double netExitPrice = (position.direction > 0
                                   ? position.targetPrice - slippagePrice
                                   : position.targetPrice + exitSpreadPrice + slippagePrice);
      FinalizeTrade(position, bar, time[bar], grossExitPrice, netExitPrice, EXIT_REASON_TARGET, point, trade);
      return true;
   }

   if (position.holdBars >= gMaxHoldBars)
   {
      const double grossExitPrice = close[bar];
      const double netExitPrice = (position.direction > 0
                                   ? close[bar] - slippagePrice
                                   : close[bar] + exitSpreadPrice + slippagePrice);
      FinalizeTrade(position, bar, time[bar], grossExitPrice, netExitPrice, EXIT_REASON_TIMEOUT, point, trade);
      return true;
   }

   return false;
}

void RunBacktestMode(const string modeLabel,
                     const ENUM_BREAKOUT_RESEARCH_MODE mode,
                     const datetime &time[],
                     const double &open[],
                     const double &high[],
                     const double &low[],
                     const double &close[],
                     const long &tickVolume[],
                     const int &spread[],
                     const double &flagBuffer[],
                     const double &scoreBuffer[],
                     const int lastValid,
                     const double point,
                     const StateEngineConfig &config,
                     const int oldestBar,
                     const int mostRecentBar,
                     const int fileHandle,
                     TradeRecord &trades[],
                     int &tradeCount,
                     BacktestStats &stats)
{
   InitializeStats(stats, modeLabel);

   PendingSignal pending;
   ResetPendingSignal(pending);

   PositionState position;
   ResetPositionState(position);

   for (int bar = oldestBar; bar >= mostRecentBar; --bar)
   {
      if ((bar & 1023) == 0 && IsStopped())
         break;

      if (position.active && position.pendingIndicatorExit != BREAKOUT_INDICATOR_EXIT_NONE)
      {
         TradeRecord indicatorExitTrade;
         if (ExecutePendingIndicatorExitAtOpen(position,
                                               bar,
                                               time,
                                               open,
                                               spread,
                                               point,
                                               indicatorExitTrade))
         {
            AppendTrade(trades, tradeCount, indicatorExitTrade);
            UpdateStats(stats, indicatorExitTrade);
            WriteTradeRow(fileHandle, indicatorExitTrade);
         }
      }

      if (!position.active && pending.active)
      {
         OpenPositionFromSignal(pending, bar, time, open, spread, point, position);
         ResetPendingSignal(pending);
      }

      if (position.active)
      {
         TradeRecord closedTrade;
         if (EvaluateExitOnBar(position, bar, time, high, low, close, spread, point, closedTrade))
         {
            AppendTrade(trades, tradeCount, closedTrade);
            UpdateStats(stats, closedTrade);
            WriteTradeRow(fileHandle, closedTrade);
         }
      }

      StateSnapshot snapshot;
      if (!ComputeStateSnapshotAtIndex(bar,
                                       lastValid,
                                       time,
                                       high,
                                       low,
                                       close,
                                       tickVolume,
                                       flagBuffer,
                                       scoreBuffer,
                                       point,
                                       Eps(),
                                       config,
                                       snapshot))
      {
         continue;
      }

      if (position.active)
         ScheduleIndicatorExitOnClose(position, bar, close, snapshot);

      if (!position.active && bar > mostRecentBar)
      {
         PendingSignal nextSignal;
         ResetPendingSignal(nextSignal);
         if (BuildSignal(modeLabel, mode, snapshot, bar, high, low, close, time[bar], nextSignal))
            pending = nextSignal;
      }
   }

   if (position.active)
   {
      const double slippagePrice = InpSlippagePoints * point;
      const double exitSpreadPrice = spread[mostRecentBar] * point;
      const double grossExitPrice = close[mostRecentBar];
      const double netExitPrice = (position.direction > 0
                                   ? close[mostRecentBar] - slippagePrice
                                   : close[mostRecentBar] + exitSpreadPrice + slippagePrice);

      TradeRecord closedTrade;
      FinalizeTrade(position,
                    mostRecentBar,
                    time[mostRecentBar],
                    grossExitPrice,
                    netExitPrice,
                    EXIT_REASON_DATA_END,
                    point,
                    closedTrade);
      AppendTrade(trades, tradeCount, closedTrade);
      UpdateStats(stats, closedTrade);
      WriteTradeRow(fileHandle, closedTrade);
   }
}

void PrintStatsSummary(const BacktestStats &stats)
{
   PrintFormat("[%s] trades=%d wins=%d losses=%d win_rate=%.2f%% net_points=%.2f expectancy=%.2f payoff=%.2f profit_factor=%.2f max_dd=%.2f max_losing_streak=%d",
               stats.modeLabel,
               stats.trades,
               stats.wins,
               stats.losses,
               StatsWinRate(stats),
               stats.netPointsTotal,
               StatsExpectancy(stats),
               StatsPayoff(stats),
               StatsProfitFactor(stats),
               stats.maxDrawdownPoints,
               stats.maxLosingStreak);
}

void AddExperimentConfig(ExperimentConfig &experiments[],
                         int &count,
                         const string experimentId,
                         const double minStrength,
                         const double minBreakQuality,
                         const double minVolumeConfirm,
                         const double maxExhaustion,
                         const double stopStepMultiple,
                         const double targetStepMultiple,
                         const int maxHoldBars,
                         const int recentBreakoutWindow,
                         const double continuationStepFraction,
                         const double retestToleranceStepFraction,
                         const string exportFileName)
{
   ArrayResize(experiments, count + 1);
   experiments[count].experimentId = experimentId;
   experiments[count].mode = BREAKOUT_MODE_FILTERED;
   experiments[count].modeLabel = "filtered_breakout";
   experiments[count].minStrength = minStrength;
   experiments[count].minBreakQuality = minBreakQuality;
   experiments[count].minVolumeConfirm = minVolumeConfirm;
   experiments[count].maxExhaustion = maxExhaustion;
   experiments[count].stopStepMultiple = stopStepMultiple;
   experiments[count].targetStepMultiple = targetStepMultiple;
   experiments[count].maxHoldBars = maxHoldBars;
   experiments[count].indicatorExitEnabled = false;
   experiments[count].structureExitEnabled = InpEnableStructureExit;
   experiments[count].flowReversalExitEnabled = InpEnableFlowReversalExit;
   experiments[count].exhaustionReversalExitEnabled = InpEnableExhaustionReversalExit;
   experiments[count].indicatorExitMinHoldBars = InpIndicatorExitMinHoldBars;
   experiments[count].exitInsideZoneStepFraction = InpExitInsideZoneStepFraction;
   experiments[count].exitExhaustionThreshold = InpExitExhaustionThreshold;
   experiments[count].recentBreakoutWindow = recentBreakoutWindow;
   experiments[count].continuationStepFraction = continuationStepFraction;
   experiments[count].retestToleranceStepFraction = retestToleranceStepFraction;
   experiments[count].exportFileName = exportFileName;
   ++count;
}

void ConfigureExperimentIndicatorExit(ExperimentConfig &config,
                                      const bool enabled,
                                      const bool structureEnabled,
                                      const bool flowReversalEnabled,
                                      const bool exhaustionReversalEnabled,
                                      const int minHoldBars,
                                      const double insideZoneStepFraction,
                                      const double exhaustionThreshold)
{
   config.indicatorExitEnabled = enabled;
   config.structureExitEnabled = structureEnabled;
   config.flowReversalExitEnabled = flowReversalEnabled;
   config.exhaustionReversalExitEnabled = exhaustionReversalEnabled;
   config.indicatorExitMinHoldBars = minHoldBars;
   config.exitInsideZoneStepFraction = insideZoneStepFraction;
   config.exitExhaustionThreshold = exhaustionThreshold;
}

bool BuildExperimentSuite(const string suiteName,
                          ExperimentConfig &experiments[],
                          int &experimentCount)
{
   ArrayResize(experiments, 0);
   experimentCount = 0;

   string normalizedSuiteName = suiteName;
   StringToLower(normalizedSuiteName);
   if (StringCompare(normalizedSuiteName, "v2") == 0)
   {
      AddExperimentConfig(experiments, experimentCount, "V2_01", 0.10, 0.30, 0.25, 0.27, 1.00, 1.50, 8, 1, 0.00, 0.00, "mrz_v2_01_base.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_02", 0.08, 0.30, 0.25, 0.27, 1.00, 1.50, 8, 1, 0.00, 0.00, "mrz_v2_02_str008.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_03", 0.12, 0.30, 0.25, 0.27, 1.00, 1.50, 8, 1, 0.00, 0.00, "mrz_v2_03_str012.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_04", 0.10, 0.28, 0.25, 0.27, 1.00, 1.50, 8, 1, 0.00, 0.00, "mrz_v2_04_bq028.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_05", 0.10, 0.32, 0.25, 0.27, 1.00, 1.50, 8, 1, 0.00, 0.00, "mrz_v2_05_bq032.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_06", 0.10, 0.30, 0.20, 0.27, 1.00, 1.50, 8, 1, 0.00, 0.00, "mrz_v2_06_vol020.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_07", 0.10, 0.30, 0.30, 0.27, 1.00, 1.50, 8, 1, 0.00, 0.00, "mrz_v2_07_vol030.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_08", 0.10, 0.30, 0.25, 0.24, 1.00, 1.50, 8, 1, 0.00, 0.00, "mrz_v2_08_exh024.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_09", 0.10, 0.30, 0.25, 0.30, 1.00, 1.50, 8, 1, 0.00, 0.00, "mrz_v2_09_exh030.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_10", 0.10, 0.30, 0.25, 0.27, 1.00, 1.25, 8, 1, 0.00, 0.00, "mrz_v2_10_t125.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_11", 0.10, 0.30, 0.25, 0.27, 1.00, 1.50, 6, 1, 0.00, 0.00, "mrz_v2_11_hold6.csv");
      AddExperimentConfig(experiments, experimentCount, "V2_12", 0.10, 0.30, 0.25, 0.27, 1.00, 1.25, 6, 1, 0.00, 0.00, "mrz_v2_12_t125_hold6.csv");
      return true;
   }

   if (StringCompare(normalizedSuiteName, "v3") == 0)
   {
      AddExperimentConfig(experiments, experimentCount, "V3_01", 0.10, 0.30, 0.25, 0.27, 1.00, 1.25, 6, 1, 0.00, 0.00, "mrz_v3_01_base.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_02", 0.09, 0.30, 0.25, 0.27, 1.00, 1.25, 6, 1, 0.00, 0.00, "mrz_v3_02_str009.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_03", 0.11, 0.30, 0.25, 0.27, 1.00, 1.25, 6, 1, 0.00, 0.00, "mrz_v3_03_str011.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_04", 0.10, 0.28, 0.25, 0.27, 1.00, 1.25, 6, 1, 0.00, 0.00, "mrz_v3_04_bq028.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_05", 0.10, 0.32, 0.25, 0.27, 1.00, 1.25, 6, 1, 0.00, 0.00, "mrz_v3_05_bq032.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_06", 0.10, 0.30, 0.20, 0.27, 1.00, 1.25, 6, 1, 0.00, 0.00, "mrz_v3_06_vol020.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_07", 0.10, 0.30, 0.30, 0.27, 1.00, 1.25, 6, 1, 0.00, 0.00, "mrz_v3_07_vol030.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_08", 0.10, 0.30, 0.25, 0.26, 1.00, 1.25, 6, 1, 0.00, 0.00, "mrz_v3_08_exh026.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_09", 0.10, 0.30, 0.25, 0.28, 1.00, 1.25, 6, 1, 0.00, 0.00, "mrz_v3_09_exh028.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_10", 0.10, 0.30, 0.25, 0.27, 1.00, 1.20, 6, 1, 0.00, 0.00, "mrz_v3_10_t120.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_11", 0.10, 0.30, 0.25, 0.27, 1.00, 1.30, 6, 1, 0.00, 0.00, "mrz_v3_11_t130.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_12", 0.10, 0.30, 0.25, 0.27, 1.00, 1.25, 5, 1, 0.00, 0.00, "mrz_v3_12_hold5.csv");
      AddExperimentConfig(experiments, experimentCount, "V3_13", 0.10, 0.30, 0.25, 0.27, 1.00, 1.25, 7, 1, 0.00, 0.00, "mrz_v3_13_hold7.csv");
      return true;
   }

   if (StringCompare(normalizedSuiteName, "v4") == 0)
   {
      AddExperimentConfig(experiments, experimentCount, "V4_01", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v4_01_base.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_02", 0.04, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v4_02_str004.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_03", 0.06, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v4_03_str006.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_04", 0.05, 0.15, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v4_04_bq015.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_05", 0.05, 0.22, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v4_05_bq022.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_06", 0.05, 0.18, 0.08, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v4_06_vol008.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_07", 0.05, 0.18, 0.16, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v4_07_vol016.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_08", 0.05, 0.18, 0.12, 0.35, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v4_08_exh035.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_09", 0.05, 0.18, 0.12, 0.55, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v4_09_exh055.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_10", 0.05, 0.18, 0.12, 0.45, 0.80, 0.60, 20, 6, 0.05, 0.20, "mrz_v4_10_t060.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_11", 0.05, 0.18, 0.12, 0.45, 0.80, 1.00, 20, 6, 0.05, 0.20, "mrz_v4_11_t100.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_12", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 15, 6, 0.05, 0.20, "mrz_v4_12_hold15.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_13", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 25, 6, 0.05, 0.20, "mrz_v4_13_hold25.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_14", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 4, 0.05, 0.20, "mrz_v4_14_recent4.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_15", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 8, 0.05, 0.20, "mrz_v4_15_recent8.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_16", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.02, 0.20, "mrz_v4_16_cont002.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_17", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.08, 0.20, "mrz_v4_17_cont008.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_18", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.10, "mrz_v4_18_retest010.csv");
      AddExperimentConfig(experiments, experimentCount, "V4_19", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.30, "mrz_v4_19_retest030.csv");
      return true;
   }

   if (StringCompare(normalizedSuiteName, "v5") == 0)
   {
      AddExperimentConfig(experiments, experimentCount, "V5_01", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_01_no_indicator_exit.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], false, false, false, false, 1, 0.50, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V5_02", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_02_structure005_all.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, true, true, true, 1, 0.05, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V5_03", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_03_structure025_all.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, true, true, true, 1, 0.25, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V5_04", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_04_structure050_all.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, true, true, true, 1, 0.50, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V5_05", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_05_structure100_all.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, true, true, true, 1, 1.00, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V5_06", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_06_structure050_only.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, true, false, false, 1, 0.50, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V5_07", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_07_flow_only.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, false, true, false, 1, 0.50, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V5_08", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_08_exhaustion050_only.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, false, false, true, 1, 0.50, 0.50);

      AddExperimentConfig(experiments, experimentCount, "V5_09", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_09_flow_exhaustion050.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, false, true, true, 1, 0.50, 0.50);

      AddExperimentConfig(experiments, experimentCount, "V5_10", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_10_structure050_confirm3.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, true, true, true, 3, 0.50, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V5_11", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v5_11_structure100_flow_exhaustion.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, true, true, true, 1, 1.00, 0.50);

      return true;
   }

   // V6 validates the V5 winner on the complete history.  The structure
   // threshold is fixed at 0.50 here (selected on the recent 100k bars), so
   // this suite acts as a broader confirmation rather than another search.
   if (StringCompare(normalizedSuiteName, "v6") == 0)
   {
      AddExperimentConfig(experiments, experimentCount, "V6_01", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v6_01_no_indicator_exit.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], false, false, false, false, 1, 0.50, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V6_02", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v6_02_structure050_only.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, true, false, false, 1, 0.50, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V6_03", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v6_03_flow_only.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, false, true, false, 1, 0.50, 0.65);

      AddExperimentConfig(experiments, experimentCount, "V6_04", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v6_04_exhaustion050_only.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, false, false, true, 1, 0.50, 0.50);

      AddExperimentConfig(experiments, experimentCount, "V6_05", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v6_05_structure050_all.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, true, true, true, 1, 0.50, 0.50);

      return true;
   }

   // Full-history confirmation of the V5 structure candidate.
   if (StringCompare(normalizedSuiteName, "v7") == 0)
   {
      AddExperimentConfig(experiments, experimentCount, "V7_01", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v7_01_structure050_only.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], true, true, false, false, 1, 0.50, 0.65);
      return true;
   }

   // Matching full-history baseline for V7.  This suite stays isolated so a
   // cancelled multi-experiment run cannot leave a partial baseline that is
   // accidentally compared with a complete structure-exit result.
   if (StringCompare(normalizedSuiteName, "v8") == 0)
   {
      AddExperimentConfig(experiments, experimentCount, "V8_01", 0.05, 0.18, 0.12, 0.45, 0.80, 0.80, 20, 6, 0.05, 0.20, "mrz_v8_01_no_indicator_exit.csv");
      ConfigureExperimentIndicatorExit(experiments[experimentCount - 1], false, false, false, false, 1, 0.50, 0.65);
      return true;
   }

   return false;
}

bool ValidateThresholdInputs()
{
   if (InpMinStrength < 0.0 || InpMinStrength > 1.0 ||
       InpMinBreakQuality < 0.0 || InpMinBreakQuality > 1.0 ||
       InpMinVolumeConfirm < 0.0 || InpMinVolumeConfirm > 1.0 ||
       InpMaxExhaustion < 0.0 || InpMaxExhaustion > 1.0)
   {
      Print("Breakout backtest failed: score thresholds must stay inside 0..1");
      return false;
   }
   if (InpStopStepMultiple <= 0.0 || InpTargetStepMultiple <= 0.0)
   {
      Print("Breakout backtest failed: stop and target multiples must be > 0");
      return false;
   }
   return true;
}

bool ValidateCommonInputs()
{
   if (InpStateWindow < 2 || InpMicrotrendWindow < 2 || InpShortWindow < 2)
   {
      Print("Breakout backtest failed: state windows must be >= 2");
      return false;
   }
   if (InpMaxHoldBars < 1 || InpSlippagePoints < 0 || InpStartShift < 0 || InpMaxRows < 0)
   {
      Print("Breakout backtest failed: hold bars must be >= 1 and integer inputs cannot be negative");
      return false;
   }
   if (InpIndicatorExitMinHoldBars < 1 ||
       InpIndicatorExitMinHoldBars >= InpMaxHoldBars ||
       InpExitInsideZoneStepFraction < 0.0 ||
       InpExitInsideZoneStepFraction > 1.0 ||
       InpExitExhaustionThreshold < 0.0 ||
       InpExitExhaustionThreshold > 1.0)
   {
      Print("Breakout backtest failed: indicator-exit settings are invalid");
      return false;
   }
   if (InpRecentBreakoutWindow < 1 || InpContinuationStepFraction < 0.0 || InpRetestToleranceStepFraction < 0.0)
   {
      Print("Breakout backtest failed: breakout-window and step fractions must be valid");
      return false;
   }
   if (!InpRunExperimentSuite && StringLen(InpExportFileName) == 0)
   {
      Print("Breakout backtest failed: InpExportFileName cannot be empty");
      return false;
   }
   return true;
}

void RunSingleModeBacktests(const datetime &time[],
                            const double &open[],
                            const double &high[],
                            const double &low[],
                            const double &close[],
                            const long &tickVolume[],
                            const int &spread[],
                            const double &flagBuffer[],
                            const double &scoreBuffer[],
                            const int lastValid,
                            const double point,
                            const StateEngineConfig &config,
                            const int oldestBar,
                            const int mostRecentBar,
                            const string exportFileName)
{
   PrintFormat("MRZ backtest mode=MANUAL export=%s common_folder=%s research_mode=%d",
               exportFileName,
               (InpUseCommonFolder ? "true" : "false"),
               (int)InpResearchMode);

   const int fileHandle = OpenTradesFile(exportFileName);
   if (fileHandle == INVALID_HANDLE)
      return;
   WriteTradesHeader(fileHandle);

   TradeRecord trades[];
   int tradeCount = 0;

   if (ModeEnabled(InpResearchMode, BREAKOUT_MODE_SIMPLE))
   {
      BacktestStats simpleStats;
      RunBacktestMode("simple_breakout",
                      BREAKOUT_MODE_SIMPLE,
                      time,
                      open,
                      high,
                      low,
                      close,
                      tickVolume,
                      spread,
                      flagBuffer,
                      scoreBuffer,
                      lastValid,
                      point,
                      config,
                      oldestBar,
                      mostRecentBar,
                      fileHandle,
                      trades,
                      tradeCount,
                      simpleStats);
      PrintStatsSummary(simpleStats);
   }

   if (ModeEnabled(InpResearchMode, BREAKOUT_MODE_FILTERED))
   {
      BacktestStats filteredStats;
      RunBacktestMode("filtered_breakout",
                      BREAKOUT_MODE_FILTERED,
                      time,
                      open,
                      high,
                      low,
                      close,
                      tickVolume,
                      spread,
                      flagBuffer,
                      scoreBuffer,
                      lastValid,
                      point,
                      config,
                      oldestBar,
                      mostRecentBar,
                      fileHandle,
                      trades,
                      tradeCount,
                      filteredStats);
      PrintStatsSummary(filteredStats);
   }

   FileClose(fileHandle);
}

void RunExperimentSuiteBacktests(const datetime &time[],
                                 const double &open[],
                                 const double &high[],
                                 const double &low[],
                                 const double &close[],
                                 const long &tickVolume[],
                                 const int &spread[],
                                 const double &flagBuffer[],
                                 const double &scoreBuffer[],
                                 const int lastValid,
                                 const double point,
                                 const StateEngineConfig &config,
                                 const int oldestBar,
                                 const int mostRecentBar)
{
   ExperimentConfig experiments[];
   int experimentCount = 0;
   if (!BuildExperimentSuite(InpSuiteName, experiments, experimentCount) || experimentCount <= 0)
   {
      PrintFormat("Breakout backtest failed: unknown experiment suite '%s'", InpSuiteName);
      return;
   }

   if (StringLen(InpExportSummaryFileName) == 0)
   {
      Print("Breakout backtest failed: InpExportSummaryFileName cannot be empty when suite mode is enabled");
      return;
   }

   PrintFormat("MRZ backtest mode=SUITE suite=%s experiments=%d summary=%s common_folder=%s",
               InpSuiteName,
               experimentCount,
               InpExportSummaryFileName,
               (InpUseCommonFolder ? "true" : "false"));

   const int summaryHandle = OpenCsvFile(InpExportSummaryFileName);
   if (summaryHandle == INVALID_HANDLE)
      return;
   WriteSummaryHeader(summaryHandle);

   for (int i = 0; i < experimentCount; ++i)
   {
      LoadRuntimeParametersFromExperiment(experiments[i]);
      PrintFormat("MRZ suite experiment=%s export=%s strength=%.2f break_quality=%.2f volume_confirm=%.2f exhaustion=%.2f target=%.2f hold=%d",
                  experiments[i].experimentId,
                  experiments[i].exportFileName,
                  experiments[i].minStrength,
                  experiments[i].minBreakQuality,
                  experiments[i].minVolumeConfirm,
                  experiments[i].maxExhaustion,
                  experiments[i].targetStepMultiple,
                  experiments[i].maxHoldBars);

      const int fileHandle = OpenTradesFile(experiments[i].exportFileName);
      if (fileHandle == INVALID_HANDLE)
         continue;
      WriteTradesHeader(fileHandle);

      TradeRecord trades[];
      int tradeCount = 0;
      BacktestStats stats;
      RunBacktestMode(experiments[i].experimentId,
                      experiments[i].mode,
                      time,
                      open,
                      high,
                      low,
                      close,
                      tickVolume,
                      spread,
                      flagBuffer,
                      scoreBuffer,
                      lastValid,
                      point,
                      config,
                      oldestBar,
                      mostRecentBar,
                      fileHandle,
                      trades,
                      tradeCount,
                      stats);

      FileClose(fileHandle);
      PrintStatsSummary(stats);
      WriteSummaryRow(summaryHandle, experiments[i], stats);
   }

   FileClose(summaryHandle);
}

int DetermineMostRecentProcessBar()
{
   return MathMax(0, InpStartShift);
}

int DetermineOldestProcessBar(const int lastValid,
                              const int mostRecentBar)
{
   int oldestBar = lastValid;
   if (InpMaxRows > 0)
      oldestBar = MathMin(lastValid, mostRecentBar + InpMaxRows - 1);
   return oldestBar;
}

void OnStart()
{
   if (!ValidateCommonInputs())
      return;
   if (!InpRunExperimentSuite && !ValidateThresholdInputs())
      return;
   if (InpRunExperimentSuite && StringLen(InpSuiteName) == 0)
   {
      Print("Breakout backtest failed: InpSuiteName cannot be empty when suite mode is enabled");
      return;
   }

   const string symbol = ResolveBacktestSymbol();
   const ENUM_TIMEFRAMES timeframe = InpBacktestTimeframe;
   PrintFormat("MRZ OnStart suite_enabled=%s suite=%s export=%s summary=%s symbol=%s timeframe=%s",
               (InpRunExperimentSuite ? "true" : "false"),
               InpSuiteName,
               InpExportFileName,
               InpExportSummaryFileName,
               symbol,
               TimeframeToString(timeframe));

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
   if (!LoadRatesSeries(symbol, timeframe, time, open, high, low, close, tickVolume, spread, ratesTotal))
      return;

   StateEngineConfig config;
   ConfigureStateEngine(config);

   double flagBuffer[];
   double scoreBuffer[];
   ZoneInfo zoneCatalog[];
   int zoneCount = 0;
   int lastValid = -1;
   if (!PrepareStateWindowContext(ratesTotal,
                                  time,
                                  high,
                                  low,
                                  close,
                                  point,
                                  Eps(),
                                  config,
                                  flagBuffer,
                                  scoreBuffer,
                                  zoneCatalog,
                                  zoneCount,
                                  lastValid))
   {
      Print("Breakout backtest failed: unable to prepare state engine context");
      return;
   }

   const int mostRecentBar = DetermineMostRecentProcessBar();
   const int oldestBar = DetermineOldestProcessBar(lastValid, mostRecentBar);
   if (mostRecentBar >= oldestBar)
   {
      PrintFormat("Breakout backtest failed: no valid process range for %s %s with window %d",
                  symbol,
                  TimeframeToString(timeframe),
                  InpStateWindow);
      return;
   }

   if (InpRunExperimentSuite)
   {
      RunExperimentSuiteBacktests(time,
                                  open,
                                  high,
                                  low,
                                  close,
                                  tickVolume,
                                  spread,
                                  flagBuffer,
                                  scoreBuffer,
                                  lastValid,
                                  point,
                                  config,
                                  oldestBar,
                                  mostRecentBar);
      PrintFormat("Breakout suite finished: symbol=%s timeframe=%s rows=%d suite=%s summary=%s",
                  symbol,
                  TimeframeToString(timeframe),
                  (oldestBar - mostRecentBar + 1),
                  InpSuiteName,
                  InpExportSummaryFileName);
      return;
   }

   LoadRuntimeParametersFromInputs();
   RunSingleModeBacktests(time,
                          open,
                          high,
                          low,
                          close,
                          tickVolume,
                          spread,
                          flagBuffer,
                          scoreBuffer,
                          lastValid,
                          point,
                          config,
                          oldestBar,
                          mostRecentBar,
                          InpExportFileName);
   PrintFormat("Breakout backtest finished: symbol=%s timeframe=%s rows=%d file=%s",
               symbol,
               TimeframeToString(timeframe),
               (oldestBar - mostRecentBar + 1),
               InpExportFileName);
}
