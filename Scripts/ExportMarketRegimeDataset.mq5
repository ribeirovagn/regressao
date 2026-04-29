//+------------------------------------------------------------------+
//| ExportMarketRegimeDataset.mq5                                    |
//| Historical dataset export for MarketRegime Zones                 |
//+------------------------------------------------------------------+
#property copyright "Vagner Ribeiro"
#property link "https://www.mql5.com"
#property version "1.00"
#property script_show_inputs
#property strict

#include "../Core/StateEngine.mqh"

input string InpExportSymbol = "";
input ENUM_TIMEFRAMES InpExportTimeframe = PERIOD_M1;

input int InpWindowFast = 120;
input int InpWindowSlow = 180;

input int InpFutureHorizon1 = 10;
input int InpFutureHorizon2 = 20;
input int InpFutureHorizon3 = 50;

input string InpExportFileName = "market_regime_dataset.csv";
input bool InpUseCommonFolder = true;

input int InpStartShift = 0;
input int InpMaxRows = 0;

double ExportMissingNumber()
{
   return -1.0;
}

string ResolveExportSymbol()
{
   if (StringLen(InpExportSymbol) > 0)
      return InpExportSymbol;
   return _Symbol;
}

int MaxInt3(const int a,
            const int b,
            const int c)
{
   return MathMax(a, MathMax(b, c));
}

double OptionalValue(const bool hasValue,
                     const double value)
{
   return (hasValue ? value : ExportMissingNumber());
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
      return ExportMissingNumber();
   return (left - right);
}

double OptionalStepDelta(const StateSnapshot &fastState,
                         const StateSnapshot &slowState)
{
   if (!fastState.hasStep || !slowState.hasStep)
      return 0.0;
   return (fastState.step - slowState.step);
}

double OptionalZoneEnergyDelta(const StateSnapshot &fastState,
                               const StateSnapshot &slowState)
{
   if (!fastState.hasZoneEnergy || !slowState.hasZoneEnergy)
      return 0.0;
   return (fastState.zoneEnergy01 - slowState.zoneEnergy01);
}

string SnapshotVolumeBiasValue(const StateSnapshot &snapshot)
{
   if (!snapshot.hasVolume)
      return "N/A";
   return DirectionToString(snapshot.volumeState.bias);
}

double SnapshotVolumeConfirmValue(const StateSnapshot &snapshot)
{
   return OptionalValue(snapshot.hasVolume, snapshot.volumeState.confirmation01);
}

double SnapshotVolumeR2Value(const StateSnapshot &snapshot)
{
   return OptionalValue(snapshot.hasVolume, snapshot.volumeState.r2);
}

double SnapshotVolumeRatioValue(const StateSnapshot &snapshot)
{
   return OptionalValue(snapshot.hasVolume, snapshot.volumeState.ratio);
}

double SnapshotVolumeSlopeValue(const StateSnapshot &snapshot)
{
   return OptionalValue(snapshot.hasVolume, snapshot.volumeState.slope01);
}

string SnapshotRegimeValue(const StateSnapshot &snapshot)
{
   if (!snapshot.valid)
      return "N/A";
   return RegimeToString(snapshot.regime);
}

string SnapshotBiasValue(const StateSnapshot &snapshot)
{
   if (!snapshot.mainMetrics.valid)
      return "N/A";
   return DirectionToString(snapshot.biasDir);
}

string SnapshotMicrotrendValue(const StateSnapshot &snapshot)
{
   if (!snapshot.microMetrics.valid)
      return "N/A";
   return DirectionToString(snapshot.microDir);
}

string SnapshotStepSourceValue(const StateSnapshot &snapshot)
{
   if (!snapshot.hasStep)
      return "N/A";
   return StepSourceToString(snapshot.stepSource);
}

void ComputeFutureLabels(const int index,
                         const int horizon,
                         const double &close[],
                         double &futureMove,
                         double &mfe,
                         double &mae)
{
   futureMove = ExportMissingNumber();
   mfe = ExportMissingNumber();
   mae = ExportMissingNumber();

   if (horizon < 1 || (index - horizon) < 0)
      return;

   const double currentClose = close[index];
   futureMove = close[index - horizon] - currentClose;
   mfe = -DBL_MAX;
   mae = DBL_MAX;

   for (int step = 1; step <= horizon; ++step)
   {
      const double move = close[index - step] - currentClose;
      if (move > mfe)
         mfe = move;
      if (move < mae)
         mae = move;
   }

   if (mfe == -DBL_MAX)
      mfe = 0.0;
   if (mae == DBL_MAX)
      mae = 0.0;
}

bool LoadRatesSeries(const string symbol,
                     const ENUM_TIMEFRAMES timeframe,
                     datetime &time[],
                     double &high[],
                     double &low[],
                     double &close[],
                     long &tickVolume[],
                     int &ratesTotal)
{
   ratesTotal = 0;

   if (!SymbolSelect(symbol, true))
   {
      PrintFormat("Dataset export failed: unable to select symbol %s", symbol);
      return false;
   }

   const int requestedBars = Bars(symbol, timeframe);
   if (requestedBars <= 0)
   {
      PrintFormat("Dataset export failed: no bars available for %s %s", symbol, TimeframeToString(timeframe));
      return false;
   }

   MqlRates rates[];
   ResetLastError();
   const int copied = CopyRates(symbol, timeframe, 0, requestedBars, rates);
   if (copied <= 0)
   {
      PrintFormat("Dataset export failed: CopyRates returned %d for %s %s (error %d)",
                  copied,
                  symbol,
                  TimeframeToString(timeframe),
                  GetLastError());
      return false;
   }

   ArrayResize(time, copied);
   ArrayResize(high, copied);
   ArrayResize(low, copied);
   ArrayResize(close, copied);
   ArrayResize(tickVolume, copied);

   for (int i = 0; i < copied; ++i)
   {
      time[i] = rates[i].time;
      high[i] = rates[i].high;
      low[i] = rates[i].low;
      close[i] = rates[i].close;
      tickVolume[i] = rates[i].tick_volume;
   }

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tickVolume, true);

   ratesTotal = copied;
   return true;
}

void WriteCsvHeader(const int fileHandle,
                    const int horizon1,
                    const int horizon2,
                    const int horizon3)
{
   FileWrite(fileHandle,
             "time",
             "symbol",
             "timeframe",
             "close",
             "regime_fast",
             "bias_fast",
             "microtrend_fast",
             "strength_fast",
             "exhaustion_fast",
             "break_quality_fast",
             "step_fast",
             "step_src_fast",
             "zone_energy_fast",
             "volume_bias_fast",
             "volume_confirm_fast",
             "volume_r2_fast",
             "volume_ratio_fast",
             "volume_s_fast",
             "regime_slow",
             "bias_slow",
             "microtrend_slow",
             "strength_slow",
             "exhaustion_slow",
             "break_quality_slow",
             "step_slow",
             "step_src_slow",
             "zone_energy_slow",
             "volume_bias_slow",
             "volume_confirm_slow",
             "volume_r2_slow",
             "volume_ratio_slow",
             "volume_s_slow",
             "bias_alignment",
             "volume_bias_alignment",
             "microtrend_alignment",
             "regime_alignment",
             "strength_delta",
             "volume_confirm_delta",
             "exhaustion_delta",
             "break_quality_delta",
             "step_delta",
             "zone_energy_delta",
             StringFormat("future_move_%d", horizon1),
             StringFormat("future_move_%d", horizon2),
             StringFormat("future_move_%d", horizon3),
             StringFormat("mfe_%d", horizon1),
             StringFormat("mae_%d", horizon1),
             StringFormat("mfe_%d", horizon2),
             StringFormat("mae_%d", horizon2),
             StringFormat("mfe_%d", horizon3),
             StringFormat("mae_%d", horizon3));
}

int OpenExportFile()
{
   int flags = FILE_WRITE | FILE_CSV | FILE_ANSI;
   if (InpUseCommonFolder)
      flags |= FILE_COMMON;

   ResetLastError();
   const int fileHandle = FileOpen(InpExportFileName, flags, ',');
   if (fileHandle == INVALID_HANDLE)
      PrintFormat("Dataset export failed: unable to open %s (error %d)", InpExportFileName, GetLastError());

   return fileHandle;
}

void OnStart()
{
   if (InpWindowFast < 2 || InpWindowSlow < 2)
   {
      Print("Dataset export failed: windows must be >= 2");
      return;
   }
   if (InpFutureHorizon1 < 1 || InpFutureHorizon2 < 1 || InpFutureHorizon3 < 1)
   {
      Print("Dataset export failed: future horizons must be >= 1");
      return;
   }
   if (InpStartShift < 0 || InpMaxRows < 0)
   {
      Print("Dataset export failed: InpStartShift and InpMaxRows must be >= 0");
      return;
   }
   if (StringLen(InpExportFileName) == 0)
   {
      Print("Dataset export failed: InpExportFileName cannot be empty");
      return;
   }

   const string symbol = ResolveExportSymbol();
   const ENUM_TIMEFRAMES timeframe = InpExportTimeframe;
   const string timeframeLabel = TimeframeToString(timeframe);

   double point = 0.0;
   if (!SymbolInfoDouble(symbol, SYMBOL_POINT, point) || point <= 0.0)
      point = (_Point > 0.0 ? _Point : 0.00001);

   datetime time[];
   double high[];
   double low[];
   double close[];
   long tickVolume[];
   int ratesTotal = 0;
   if (!LoadRatesSeries(symbol, timeframe, time, high, low, close, tickVolume, ratesTotal))
      return;

   StateEngineConfig fastConfig;
   StateEngineConfig slowConfig;
   InitializeStateEngineConfig(fastConfig, InpWindowFast);
   InitializeStateEngineConfig(slowConfig, InpWindowSlow);

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
                                  1.0e-12,
                                  fastConfig,
                                  fastFlagBuffer,
                                  fastScoreBuffer,
                                  fastZoneCatalog,
                                  fastZoneCount,
                                  fastLastValid))
   {
      Print("Dataset export failed: unable to prepare fast window context");
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
                                  1.0e-12,
                                  slowConfig,
                                  slowFlagBuffer,
                                  slowScoreBuffer,
                                  slowZoneCatalog,
                                  slowZoneCount,
                                  slowLastValid))
   {
      Print("Dataset export failed: unable to prepare slow window context");
      return;
   }

   const int maxFutureHorizon = MaxInt3(InpFutureHorizon1, InpFutureHorizon2, InpFutureHorizon3);
   const int mostRecentIndex = maxFutureHorizon + InpStartShift;
   const int oldestIndex = MathMin(fastLastValid, slowLastValid);

   if (mostRecentIndex > oldestIndex)
   {
      PrintFormat("Dataset export failed: no valid rows for %s %s with windows %d/%d and horizons %d/%d/%d",
                  symbol,
                  timeframeLabel,
                  InpWindowFast,
                  InpWindowSlow,
                  InpFutureHorizon1,
                  InpFutureHorizon2,
                  InpFutureHorizon3);
      return;
   }

   int exportOldestIndex = oldestIndex;
   if (InpMaxRows > 0)
      exportOldestIndex = MathMin(oldestIndex, mostRecentIndex + InpMaxRows - 1);

   const int fileHandle = OpenExportFile();
   if (fileHandle == INVALID_HANDLE)
      return;

   WriteCsvHeader(fileHandle, InpFutureHorizon1, InpFutureHorizon2, InpFutureHorizon3);

   int exportedRows = 0;
   for (int i = exportOldestIndex; i >= mostRecentIndex; --i)
   {
      StateSnapshot fastState;
      StateSnapshot slowState;
      if (!ComputeStateSnapshotAtIndex(i,
                                       fastLastValid,
                                       time,
                                       high,
                                       low,
                                       close,
                                       tickVolume,
                                       fastFlagBuffer,
                                       fastScoreBuffer,
                                       point,
                                       1.0e-12,
                                       fastConfig,
                                       fastState))
      {
         continue;
      }

      if (!ComputeStateSnapshotAtIndex(i,
                                       slowLastValid,
                                       time,
                                       high,
                                       low,
                                       close,
                                       tickVolume,
                                       slowFlagBuffer,
                                       slowScoreBuffer,
                                       point,
                                       1.0e-12,
                                       slowConfig,
                                       slowState))
      {
         continue;
      }

      double futureMove1 = 0.0;
      double futureMove2 = 0.0;
      double futureMove3 = 0.0;
      double mfe1 = 0.0;
      double mfe2 = 0.0;
      double mfe3 = 0.0;
      double mae1 = 0.0;
      double mae2 = 0.0;
      double mae3 = 0.0;
      ComputeFutureLabels(i, InpFutureHorizon1, close, futureMove1, mfe1, mae1);
      ComputeFutureLabels(i, InpFutureHorizon2, close, futureMove2, mfe2, mae2);
      ComputeFutureLabels(i, InpFutureHorizon3, close, futureMove3, mfe3, mae3);

      FileWrite(fileHandle,
                TimeToString(time[i], TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                symbol,
                timeframeLabel,
                close[i],
                SnapshotRegimeValue(fastState),
                SnapshotBiasValue(fastState),
                SnapshotMicrotrendValue(fastState),
                OptionalValue(fastState.hasStrength, fastState.strength01),
                OptionalValue(fastState.hasExhaustion, fastState.exhaustion01),
                OptionalValue(fastState.hasBreakQuality, fastState.breakQuality01),
                OptionalValue(fastState.hasStep, fastState.step),
                SnapshotStepSourceValue(fastState),
                OptionalValue(fastState.hasZoneEnergy, fastState.zoneEnergy01),
                SnapshotVolumeBiasValue(fastState),
                SnapshotVolumeConfirmValue(fastState),
                SnapshotVolumeR2Value(fastState),
                SnapshotVolumeRatioValue(fastState),
                SnapshotVolumeSlopeValue(fastState),
                SnapshotRegimeValue(slowState),
                SnapshotBiasValue(slowState),
                SnapshotMicrotrendValue(slowState),
                OptionalValue(slowState.hasStrength, slowState.strength01),
                OptionalValue(slowState.hasExhaustion, slowState.exhaustion01),
                OptionalValue(slowState.hasBreakQuality, slowState.breakQuality01),
                OptionalValue(slowState.hasStep, slowState.step),
                SnapshotStepSourceValue(slowState),
                OptionalValue(slowState.hasZoneEnergy, slowState.zoneEnergy01),
                SnapshotVolumeBiasValue(slowState),
                SnapshotVolumeConfirmValue(slowState),
                SnapshotVolumeR2Value(slowState),
                SnapshotVolumeRatioValue(slowState),
                SnapshotVolumeSlopeValue(slowState),
                OptionalAlignment(fastState.mainMetrics.valid, fastState.biasDir, slowState.mainMetrics.valid, slowState.biasDir),
                OptionalAlignment(fastState.hasVolume, fastState.volumeState.bias, slowState.hasVolume, slowState.volumeState.bias),
                OptionalAlignment(fastState.microMetrics.valid, fastState.microDir, slowState.microMetrics.valid, slowState.microDir),
                OptionalAlignment(fastState.valid, (int)fastState.regime, slowState.valid, (int)slowState.regime),
                OptionalDelta(fastState.hasStrength, fastState.strength01, slowState.hasStrength, slowState.strength01),
                OptionalDelta(fastState.hasVolume, fastState.volumeState.confirmation01, slowState.hasVolume, slowState.volumeState.confirmation01),
                OptionalDelta(fastState.hasExhaustion, fastState.exhaustion01, slowState.hasExhaustion, slowState.exhaustion01),
                OptionalDelta(fastState.hasBreakQuality, fastState.breakQuality01, slowState.hasBreakQuality, slowState.breakQuality01),
                OptionalStepDelta(fastState, slowState),
                OptionalZoneEnergyDelta(fastState, slowState),
                futureMove1,
                futureMove2,
                futureMove3,
                mfe1,
                mae1,
                mfe2,
                mae2,
                mfe3,
                mae3);

      exportedRows++;
   }

   FileFlush(fileHandle);
   FileClose(fileHandle);

   PrintFormat("Dataset export complete: rows=%d file=%s folder=%s symbol=%s timeframe=%s windows=%d/%d",
               exportedRows,
               InpExportFileName,
               (InpUseCommonFolder ? "COMMON" : "LOCAL"),
               symbol,
               timeframeLabel,
               InpWindowFast,
               InpWindowSlow);
}
