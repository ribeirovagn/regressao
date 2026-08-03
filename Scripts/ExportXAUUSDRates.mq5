//+------------------------------------------------------------------+
//| ExportXAUUSDRates.mq5                                            |
//| Lightweight OHLC export for exit-path execution simulation       |
//+------------------------------------------------------------------+
#property copyright "Vagner Ribeiro"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs
#property strict

input string          InpExportSymbol = "XAUUSD";
input ENUM_TIMEFRAMES InpExportTimeframe = PERIOD_M1;
input int             InpRequestedBars = 500000;
input string          InpExportFileName = "xauusd_m1_rates.csv";
input bool            InpUseCommonFolder = false;

string CsvEscape(string value)
{
   const bool quote = (StringFind(value, ",") >= 0 ||
                       StringFind(value, "\"") >= 0 ||
                       StringFind(value, "\r") >= 0 ||
                       StringFind(value, "\n") >= 0);
   StringReplace(value, "\"", "\"\"");
   return (quote ? "\"" + value + "\"" : value);
}

void CsvAppend(string &line, const string value)
{
   if (StringLen(line) > 0)
      line += ",";
   line += CsvEscape(value);
}

void OnStart()
{
   if (InpRequestedBars < 1 || StringLen(InpExportFileName) == 0)
   {
      Print("XAUUSD rates export failed: invalid bar count or filename");
      return;
   }

   const string symbol = (StringLen(InpExportSymbol) > 0
                          ? InpExportSymbol
                          : _Symbol);
   if (!SymbolSelect(symbol, true))
   {
      PrintFormat("XAUUSD rates export failed: symbol unavailable: %s", symbol);
      return;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   ResetLastError();
   const int copied = CopyRates(symbol,
                                InpExportTimeframe,
                                0,
                                InpRequestedBars,
                                rates);
   if (copied <= 0)
   {
      PrintFormat("XAUUSD rates export failed: CopyRates error=%d", GetLastError());
      return;
   }

   int flags = FILE_WRITE | FILE_TXT | FILE_ANSI;
   if (InpUseCommonFolder)
      flags |= FILE_COMMON;
   ResetLastError();
   const int fileHandle = FileOpen(InpExportFileName, flags);
   if (fileHandle == INVALID_HANDLE)
   {
      PrintFormat("XAUUSD rates export failed: cannot open %s error=%d",
                  InpExportFileName,
                  GetLastError());
      return;
   }

   FileWriteString(fileHandle,
                   "meta_symbol,meta_timeframe,meta_time,open,high,low,close,tick_volume,spread_points\r\n");
   const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   const string timeframeLabel = EnumToString(InpExportTimeframe);
   for (int index = copied - 1; index >= 0; --index)
   {
      string line = "";
      CsvAppend(line, symbol);
      CsvAppend(line, timeframeLabel);
      CsvAppend(line, TimeToString(rates[index].time, TIME_DATE | TIME_MINUTES | TIME_SECONDS));
      CsvAppend(line, DoubleToString(rates[index].open, digits));
      CsvAppend(line, DoubleToString(rates[index].high, digits));
      CsvAppend(line, DoubleToString(rates[index].low, digits));
      CsvAppend(line, DoubleToString(rates[index].close, digits));
      CsvAppend(line, IntegerToString((long)rates[index].tick_volume));
      CsvAppend(line, IntegerToString(rates[index].spread));
      FileWriteString(fileHandle, line + "\r\n");
   }
   FileFlush(fileHandle);
   FileClose(fileHandle);
   PrintFormat("XAUUSD rates export complete: rows=%d file=%s folder=%s symbol=%s timeframe=%s",
               copied,
               InpExportFileName,
               (InpUseCommonFolder ? "COMMON" : "LOCAL"),
               symbol,
               timeframeLabel);
}
