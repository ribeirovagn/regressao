#ifndef MARKETREGIME_CORE_HUMANDECISIONEVENT_MQH
#define MARKETREGIME_CORE_HUMANDECISIONEVENT_MQH

#include "Types.mqh"
#include "Utils.mqh"

HUDDecisionEvent g_hud_decision_event;
HUDState g_hud_latest_state;
bool g_hud_has_latest_state = false;
string g_hud_decision_action = "";
string g_hud_decision_feedback = "";
string g_hud_seen_event_keys[];
datetime g_hud_seen_event_signal_times[];
string g_hud_alerted_event_keys[];
string g_hud_decided_event_keys[];
string g_hud_decided_event_actions[];

string HUDEventKindToString(const ENUM_HUD_EVENT_KIND kind)
{
   if (kind == HUD_EVENT_IMMEDIATE)
      return "IMMEDIATE";
   if (kind == HUD_EVENT_CONTINUATION)
      return "CONTINUATION";
   if (kind == HUD_EVENT_RETEST)
      return "RETEST";
   return "NONE";
}

string HUDEventStatusToString(const ENUM_HUD_EVENT_STATUS status)
{
   if (status == HUD_EVENT_STATUS_NEW)
      return "NOVO";
   if (status == HUD_EVENT_STATUS_EVALUATING)
      return "EM AVALIACAO";
   if (status == HUD_EVENT_STATUS_INVALIDATED)
      return "INVALIDADO";
   if (status == HUD_EVENT_STATUS_EXPIRED)
      return "EXPIRADO";
   return "SEM EVENTO";
}

string HUDDecisionHintToString(const ENUM_HUD_DECISION_HINT hint)
{
   if (hint == HUD_DECISION_EVALUATE)
      return "AVALIAR";
   if (hint == HUD_DECISION_AVOID)
      return "EVITAR";
   return "AGUARDAR";
}

string HUDTradeDirectionToString(const int direction)
{
   if (direction > 0)
      return "COMPRA";
   if (direction < 0)
      return "VENDA";
   return "NEUTRO";
}

void ResetHUDDecisionEvent(HUDDecisionEvent &event)
{
   event.valid = false;
   event.key = "";
   event.kind = HUD_EVENT_NONE;
   event.status = HUD_EVENT_STATUS_NONE;
   event.hint = HUD_DECISION_WAIT;
   event.direction = 0;
   event.signalTime = 0;
   event.breakTime = 0;
   event.ageBars = -1;
   event.boundary = 0.0;
   event.step = 0.0;
   event.signalClose = 0.0;
   event.distanceStep = 0.0;
   event.spreadPoints = 0;
   event.regime = REGIME_MIXED;
   event.biasDir = 0;
   event.microDir = 0;
   event.hasStrength = false;
   event.strengthPct = 0;
   event.hasBreakQuality = false;
   event.breakQualityPct = 0;
   event.hasExhaustion = false;
   event.exhaustionPct = 0;
   event.hasVolume = false;
   event.volumeBiasDir = 0;
   event.volumeConfirmPct = 0;
   event.priceOutside = false;
   event.biasAligned = false;
   event.microAligned = false;
   event.volumeAligned = false;
   event.evidenceVotes = 0;
   event.evidenceTotal = 0;
   event.riskFlags = 0;
   event.evidenceText = "SEM EVENTO CONFIRMADO";
   event.riskText = "AGUARDANDO CANDLE FECHADO";
}

void InitializeHumanDecisionSupport()
{
   ResetHUDDecisionEvent(g_hud_decision_event);
   g_hud_has_latest_state = false;
   g_hud_decision_action = "";
   g_hud_decision_feedback = "";
   ArrayResize(g_hud_seen_event_keys, 0);
   ArrayResize(g_hud_seen_event_signal_times, 0);
   ArrayResize(g_hud_alerted_event_keys, 0);
   ArrayResize(g_hud_decided_event_keys, 0);
   ArrayResize(g_hud_decided_event_actions, 0);
}

bool HUDStringArrayContains(const string &values[], const string value)
{
   for (int i = 0; i < ArraySize(values); ++i)
   {
      if (values[i] == value)
         return true;
   }
   return false;
}

void HUDStringArrayAppendUnique(string &values[], const string value)
{
   if (StringLen(value) == 0 || HUDStringArrayContains(values, value))
      return;
   const int size = ArraySize(values);
   ArrayResize(values, size + 1);
   values[size] = value;
}

void StoreHUDSeenEvent(const string eventKey, const datetime signalTime)
{
   if (HUDStringArrayContains(g_hud_seen_event_keys, eventKey))
      return;
   const int size = ArraySize(g_hud_seen_event_keys);
   ArrayResize(g_hud_seen_event_keys, size + 1);
   ArrayResize(g_hud_seen_event_signal_times, size + 1);
   g_hud_seen_event_keys[size] = eventKey;
   g_hud_seen_event_signal_times[size] = signalTime;
}

datetime HUDSeenEventSignalTime(const string eventKey, const datetime fallbackTime)
{
   for (int i = 0; i < ArraySize(g_hud_seen_event_keys); ++i)
   {
      if (g_hud_seen_event_keys[i] == eventKey && i < ArraySize(g_hud_seen_event_signal_times))
         return g_hud_seen_event_signal_times[i];
   }
   return fallbackTime;
}

bool HUDDecisionWasRecorded(const string eventKey)
{
   return HUDStringArrayContains(g_hud_decided_event_keys, eventKey);
}

string HUDRecordedDecisionAction(const string eventKey)
{
   for (int i = 0; i < ArraySize(g_hud_decided_event_keys); ++i)
   {
      if (g_hud_decided_event_keys[i] == eventKey && i < ArraySize(g_hud_decided_event_actions))
         return g_hud_decided_event_actions[i];
   }
   return "";
}

void StoreHUDRecordedDecision(const string eventKey, const string action)
{
   if (HUDDecisionWasRecorded(eventKey))
      return;
   const int size = ArraySize(g_hud_decided_event_keys);
   ArrayResize(g_hud_decided_event_keys, size + 1);
   ArrayResize(g_hud_decided_event_actions, size + 1);
   g_hud_decided_event_keys[size] = eventKey;
   g_hud_decided_event_actions[size] = action;
}

string AppendHUDListItem(const string current, const string item)
{
   if (StringLen(item) == 0)
      return current;
   if (StringLen(current) == 0)
      return item;
   return current + ", " + item;
}

ENUM_HUD_EVENT_KIND ResolveClosedBarEventKind(const StateSnapshot &snapshot,
                                               const int index,
                                               const double &high[],
                                               const double &low[],
                                               const double &close[],
                                               int &direction,
                                               int &ageBars)
{
   direction = 0;
   ageBars = -1;

   if (!snapshot.valid ||
       !snapshot.hasBrokenZone ||
       !snapshot.lastBroken.valid ||
       snapshot.stepSource != STEP_SOURCE_LAST_BROKEN ||
       !snapshot.hasStep ||
       snapshot.step <= 1.0e-12)
   {
      return HUD_EVENT_NONE;
   }

   if (snapshot.lastBroken.state == Z_BREAK_UP)
      direction = 1;
   else if (snapshot.lastBroken.state == Z_BREAK_DOWN)
      direction = -1;

   if (direction == 0)
      return HUD_EVENT_NONE;

   ageBars = snapshot.lastBroken.breakIndex - index;
   if (ageBars < 0 || ageBars > InpDecisionEventMaxAgeBars)
      return HUD_EVENT_NONE;

   if (ageBars == 0)
      return HUD_EVENT_IMMEDIATE;

   const double retestTolerance = snapshot.step * InpDecisionRetestToleranceStepFraction;
   if (direction > 0 &&
       low[index] <= snapshot.lastBroken.top + retestTolerance &&
       close[index] > snapshot.lastBroken.top)
   {
      return HUD_EVENT_RETEST;
   }
   if (direction < 0 &&
       high[index] >= snapshot.lastBroken.bottom - retestTolerance &&
       close[index] < snapshot.lastBroken.bottom)
   {
      return HUD_EVENT_RETEST;
   }

   const double continuationDistance = snapshot.step * InpDecisionContinuationStepFraction;
   if (direction > 0 && close[index] >= snapshot.lastBroken.top + continuationDistance)
      return HUD_EVENT_CONTINUATION;
   if (direction < 0 && close[index] <= snapshot.lastBroken.bottom - continuationDistance)
      return HUD_EVENT_CONTINUATION;

   return HUD_EVENT_NONE;
}

void FillHUDDecisionEvidence(const StateSnapshot &snapshot,
                             HUDDecisionEvent &event)
{
   event.regime = snapshot.regime;
   event.biasDir = snapshot.biasDir;
   event.microDir = snapshot.microDir;
   event.hasStrength = snapshot.hasStrength;
   event.strengthPct = (snapshot.hasStrength
                        ? ClampInt((int)MathRound(Clamp01(snapshot.strength01) * 100.0), 0, 100)
                        : 0);
   event.hasBreakQuality = snapshot.hasBreakQuality;
   event.breakQualityPct = (snapshot.hasBreakQuality
                            ? ClampInt((int)MathRound(Clamp01(snapshot.breakQuality01) * 100.0), 0, 100)
                            : 0);
   event.hasExhaustion = snapshot.hasExhaustion;
   event.exhaustionPct = (snapshot.hasExhaustion
                          ? ClampInt((int)MathRound(Clamp01(snapshot.exhaustion01) * 100.0), 0, 100)
                          : 0);
   event.hasVolume = snapshot.hasVolume;
   event.volumeBiasDir = (snapshot.hasVolume ? snapshot.volumeState.bias : 0);
   event.volumeConfirmPct = (snapshot.hasVolume
                             ? ClampInt((int)MathRound(Clamp01(snapshot.volumeState.confirmation01) * 100.0), 0, 100)
                             : 0);

   event.biasAligned = (event.biasDir == event.direction);
   event.microAligned = (event.microDir == event.direction);
   event.volumeAligned = (event.hasVolume && event.volumeBiasDir == event.direction);

   event.evidenceVotes = 0;
   event.evidenceTotal = 4 + (event.hasVolume ? 1 : 0);
   if (event.biasAligned)
      event.evidenceVotes++;
   if (event.microAligned)
      event.evidenceVotes++;
   if (event.hasStrength && event.strengthPct >= InpDecisionMinimumStrengthPct)
      event.evidenceVotes++;
   if (event.hasBreakQuality && event.breakQualityPct >= InpDecisionMinimumBreakQualityPct)
      event.evidenceVotes++;
   if (event.hasVolume &&
       event.volumeAligned &&
       event.volumeConfirmPct >= InpDecisionMinimumVolumeConfirmPct)
   {
      event.evidenceVotes++;
   }

   string evidence = StringFormat("ALINHAMENTO %d/%d | FORCA %d | BREAK %d",
                                  event.evidenceVotes,
                                  event.evidenceTotal,
                                  event.strengthPct,
                                  event.breakQualityPct);
   if (event.hasVolume)
      evidence += StringFormat(" | VOL %d", event.volumeConfirmPct);
   else
      evidence += " | VOL N/A";
   event.evidenceText = evidence;

   event.riskFlags = 0;
   string risks = "";
   if (!event.priceOutside)
   {
      event.riskFlags++;
      risks = AppendHUDListItem(risks, "RETORNO A ZONA");
   }
   if (event.biasDir != 0 && !event.biasAligned)
   {
      event.riskFlags++;
      risks = AppendHUDListItem(risks, "BIAS OPOSTO");
   }
   if (event.microDir != 0 && !event.microAligned)
   {
      event.riskFlags++;
      risks = AppendHUDListItem(risks, "MICRO OPOSTO");
   }
   if (event.hasVolume && event.volumeBiasDir != 0 && !event.volumeAligned)
   {
      event.riskFlags++;
      risks = AppendHUDListItem(risks, "VOLUME OPOSTO");
   }
   if (event.hasExhaustion && event.exhaustionPct >= InpDecisionMaximumExhaustionPct)
   {
      event.riskFlags++;
      risks = AppendHUDListItem(risks, "EXAUSTAO");
   }
   if (InpDecisionMaximumSpreadPoints > 0 && event.spreadPoints > InpDecisionMaximumSpreadPoints)
   {
      event.riskFlags++;
      risks = AppendHUDListItem(risks, "SPREAD ALTO");
   }

   event.riskText = (StringLen(risks) > 0 ? risks : "SEM ALERTAS OBJETIVOS");

   if (!event.priceOutside || event.riskFlags >= 2)
      event.hint = HUD_DECISION_AVOID;
   else if (event.evidenceVotes >= InpDecisionMinimumEvidenceVotes && event.riskFlags == 0)
      event.hint = HUD_DECISION_EVALUATE;
   else
      event.hint = HUD_DECISION_WAIT;
}

void FireHumanDecisionAlertOnce(const HUDDecisionEvent &event)
{
   if (!event.valid || event.status != HUD_EVENT_STATUS_NEW)
      return;
   if (HUDStringArrayContains(g_hud_alerted_event_keys, event.key))
      return;

   HUDStringArrayAppendUnique(g_hud_alerted_event_keys, event.key);
   const string message = StringFormat("MarketRegime %s %s: %s (%s)",
                                       _Symbol,
                                       EnumToString(_Period),
                                       HUDEventKindToString(event.kind),
                                       HUDTradeDirectionToString(event.direction));
   if (InpDecisionPopupAlert)
      Alert(message);
   if (InpDecisionSoundAlert && StringLen(InpDecisionSoundFile) > 0)
      PlaySound(InpDecisionSoundFile);
}

void UpdateHumanDecisionEvent(const StateSnapshot &snapshot,
                              const int index,
                              const datetime &time[],
                              const double &high[],
                              const double &low[],
                              const double &close[],
                              const int &spread[])
{
   if (!InpEnableDecisionEvents)
   {
      ResetHUDDecisionEvent(g_hud_decision_event);
      return;
   }

   int direction = 0;
   int ageBars = -1;
   const ENUM_HUD_EVENT_KIND candidateKind = ResolveClosedBarEventKind(snapshot,
                                                                        index,
                                                                        high,
                                                                        low,
                                                                        close,
                                                                        direction,
                                                                        ageBars);

   const bool sameBrokenZone = (g_hud_decision_event.valid &&
                                snapshot.hasBrokenZone &&
                                snapshot.lastBroken.valid &&
                                g_hud_decision_event.breakTime == snapshot.lastBroken.t_break);

   if (candidateKind == HUD_EVENT_NONE)
   {
      if (!sameBrokenZone)
      {
         ResetHUDDecisionEvent(g_hud_decision_event);
         return;
      }

      g_hud_decision_event.ageBars = snapshot.lastBroken.breakIndex - index;
      g_hud_decision_event.signalClose = close[index];
      g_hud_decision_event.spreadPoints = spread[index];
      if (g_hud_decision_event.step > 1.0e-12)
      {
         g_hud_decision_event.distanceStep = ((close[index] - g_hud_decision_event.boundary) *
                                              g_hud_decision_event.direction) /
                                             g_hud_decision_event.step;
      }
      g_hud_decision_event.priceOutside = (g_hud_decision_event.direction > 0
                                           ? close[index] > snapshot.lastBroken.top
                                           : close[index] < snapshot.lastBroken.bottom);
      if (g_hud_decision_event.ageBars > InpDecisionEventMaxAgeBars)
      {
         g_hud_decision_event.status = HUD_EVENT_STATUS_EXPIRED;
         g_hud_decision_event.hint = HUD_DECISION_AVOID;
         g_hud_decision_event.riskFlags = 1;
         g_hud_decision_event.riskText = "JANELA DO EVENTO ENCERRADA";
      }
      else if (!g_hud_decision_event.priceOutside)
      {
         g_hud_decision_event.status = HUD_EVENT_STATUS_INVALIDATED;
         g_hud_decision_event.hint = HUD_DECISION_AVOID;
         g_hud_decision_event.riskFlags = 1;
         g_hud_decision_event.riskText = "FECHAMENTO RETORNOU A ZONA";
      }
      else
      {
         g_hud_decision_event.status = HUD_EVENT_STATUS_EVALUATING;
         g_hud_decision_event.hint = HUD_DECISION_WAIT;
         g_hud_decision_event.riskFlags = 0;
         g_hud_decision_event.riskText = "SEM NOVA CONFIRMACAO NESTE CANDLE";
      }
      return;
   }

   const string candidateKey = StringFormat("%I64d_%d_%d",
                                            (long)snapshot.lastBroken.t_break,
                                            (int)candidateKind,
                                            direction);
   const bool isNewEvent = !HUDStringArrayContains(g_hud_seen_event_keys, candidateKey);
   StoreHUDSeenEvent(candidateKey, time[index]);

   HUDDecisionEvent nextEvent;
   ResetHUDDecisionEvent(nextEvent);
   nextEvent.valid = true;
   nextEvent.key = candidateKey;
   nextEvent.kind = candidateKind;
   nextEvent.status = (isNewEvent ? HUD_EVENT_STATUS_NEW : HUD_EVENT_STATUS_EVALUATING);
   nextEvent.direction = direction;
   nextEvent.signalTime = HUDSeenEventSignalTime(candidateKey, time[index]);
   nextEvent.breakTime = snapshot.lastBroken.t_break;
   nextEvent.ageBars = ageBars;
   nextEvent.boundary = (direction > 0 ? snapshot.lastBroken.top : snapshot.lastBroken.bottom);
   nextEvent.step = snapshot.step;
   nextEvent.signalClose = close[index];
   nextEvent.distanceStep = ((close[index] - nextEvent.boundary) * direction) / snapshot.step;
   nextEvent.spreadPoints = spread[index];
   nextEvent.priceOutside = (direction > 0
                             ? close[index] > snapshot.lastBroken.top
                             : close[index] < snapshot.lastBroken.bottom);
   FillHUDDecisionEvidence(snapshot, nextEvent);

   if (HUDDecisionWasRecorded(nextEvent.key))
   {
      g_hud_decision_action = HUDRecordedDecisionAction(nextEvent.key);
      g_hud_decision_feedback = "REGISTRADO: " + g_hud_decision_action;
   }
   else
   {
      g_hud_decision_feedback = "";
      g_hud_decision_action = "";
   }

   g_hud_decision_event = nextEvent;
   FireHumanDecisionAlertOnce(g_hud_decision_event);
}

string HUDRegimeCsvText(const ENUM_REGIME_STATE regime)
{
   if (regime == REGIME_RANGE)
      return "RANGE";
   if (regime == REGIME_TREND)
      return "TREND";
   return "MIXED";
}

bool WriteHumanDecisionCsv(const string action)
{
   if (!InpDecisionLogHumanActions)
      return true;
   if (StringLen(InpDecisionLogFileName) == 0)
      return false;

   int flags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if (InpDecisionUseCommonFolder)
      flags |= FILE_COMMON;

   ResetLastError();
   const int handle = FileOpen(InpDecisionLogFileName, flags, ';');
   if (handle == INVALID_HANDLE)
   {
      PrintFormat("MarketRegime: nao foi possivel abrir %s (erro %d)",
                  InpDecisionLogFileName,
                  GetLastError());
      return false;
   }

   if (FileSize(handle) == 0)
   {
      FileWrite(handle,
                "decision_time", "symbol", "timeframe", "action", "event_key",
                "signal_time", "break_time", "event_kind", "direction", "status", "hint",
                "age_bars", "boundary", "step", "signal_close", "distance_step", "signal_spread_points",
                "event_regime", "event_bias", "event_micro", "event_strength_pct", "event_break_quality_pct",
                "event_exhaustion_pct", "event_volume_bias", "event_volume_confirm_pct",
                "evidence_votes", "evidence_total", "risk_flags", "evidence", "risks",
                "live_regime", "live_bias", "live_micro", "live_strength_pct", "live_break_quality_pct",
                "live_exhaustion_pct", "live_volume_bias", "live_volume_confirm_pct", "bid", "ask", "live_spread_points");
   }

   FileSeek(handle, 0, SEEK_END);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const int liveSpreadPoints = (_Point > 0.0 ? (int)MathRound((ask - bid) / _Point) : 0);
   const int liveStrengthPct = (g_hud_has_latest_state
                                ? ClampInt((int)MathRound(Clamp01(g_hud_latest_state.strength01) * 100.0), 0, 100)
                                : 0);

   FileWrite(handle,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
             _Symbol,
             EnumToString(_Period),
             action,
             g_hud_decision_event.key,
             TimeToString(g_hud_decision_event.signalTime, TIME_DATE | TIME_SECONDS),
             TimeToString(g_hud_decision_event.breakTime, TIME_DATE | TIME_SECONDS),
             HUDEventKindToString(g_hud_decision_event.kind),
             HUDTradeDirectionToString(g_hud_decision_event.direction),
             HUDEventStatusToString(g_hud_decision_event.status),
             HUDDecisionHintToString(g_hud_decision_event.hint),
             g_hud_decision_event.ageBars,
             DoubleToString(g_hud_decision_event.boundary, _Digits),
             DoubleToString(g_hud_decision_event.step, _Digits),
             DoubleToString(g_hud_decision_event.signalClose, _Digits),
             DoubleToString(g_hud_decision_event.distanceStep, 6),
             g_hud_decision_event.spreadPoints,
             HUDRegimeCsvText(g_hud_decision_event.regime),
             g_hud_decision_event.biasDir,
             g_hud_decision_event.microDir,
             g_hud_decision_event.strengthPct,
             g_hud_decision_event.breakQualityPct,
             g_hud_decision_event.exhaustionPct,
             g_hud_decision_event.volumeBiasDir,
             g_hud_decision_event.volumeConfirmPct,
             g_hud_decision_event.evidenceVotes,
             g_hud_decision_event.evidenceTotal,
             g_hud_decision_event.riskFlags,
             g_hud_decision_event.evidenceText,
             g_hud_decision_event.riskText,
             (g_hud_has_latest_state ? HUDRegimeCsvText(g_hud_latest_state.regime) : "N/A"),
             (g_hud_has_latest_state ? g_hud_latest_state.biasDir : 0),
             (g_hud_has_latest_state ? g_hud_latest_state.microDir : 0),
             liveStrengthPct,
             (g_hud_has_latest_state && g_hud_latest_state.hasBreakQuality ? g_hud_latest_state.breakQualityPct : 0),
             (g_hud_has_latest_state && g_hud_latest_state.hasTrendExhaustion ? g_hud_latest_state.trendExhaustionPct : 0),
             (g_hud_has_latest_state && g_hud_latest_state.hasVolume ? g_hud_latest_state.volumeBiasDir : 0),
             (g_hud_has_latest_state && g_hud_latest_state.hasVolume ? g_hud_latest_state.volumeConfirmPct : 0),
             DoubleToString(bid, _Digits),
             DoubleToString(ask, _Digits),
             liveSpreadPoints);
   FileFlush(handle);
   FileClose(handle);
   return true;
}

bool HandleHumanDecisionChartEvent(const int id, const string objectName)
{
   if (id != CHARTEVENT_OBJECT_CLICK)
      return false;
   if (objectName != "LZ_HUD_BTN_MARK_ENTRY" && objectName != "LZ_HUD_BTN_IGNORE")
      return false;

   ObjectSetInteger(0, objectName, OBJPROP_STATE, false);

   const bool actionable = (InpEnableDecisionEvents &&
                            g_hud_decision_event.valid &&
                            (g_hud_decision_event.status == HUD_EVENT_STATUS_NEW ||
                             g_hud_decision_event.status == HUD_EVENT_STATUS_EVALUATING));
   if (!actionable)
   {
      g_hud_decision_feedback = "SEM EVENTO ATIVO PARA REGISTRAR";
      ObjectSetString(0, "LZ_HUD_EVENT_FEEDBACK", OBJPROP_TEXT, g_hud_decision_feedback);
      ChartRedraw(0);
      return true;
   }

   if (HUDDecisionWasRecorded(g_hud_decision_event.key))
   {
      g_hud_decision_action = HUDRecordedDecisionAction(g_hud_decision_event.key);
      g_hud_decision_feedback = "DECISAO JA REGISTRADA: " + g_hud_decision_action;
      ObjectSetString(0, "LZ_HUD_EVENT_FEEDBACK", OBJPROP_TEXT, g_hud_decision_feedback);
      ChartRedraw(0);
      return true;
   }

   const string action = (objectName == "LZ_HUD_BTN_MARK_ENTRY" ? "MARCAR_ENTRADA" : "IGNORAR");
   if (!WriteHumanDecisionCsv(action))
   {
      g_hud_decision_feedback = "FALHA AO GRAVAR CSV - CONSULTE EXPERTS";
      ObjectSetString(0, "LZ_HUD_EVENT_FEEDBACK", OBJPROP_TEXT, g_hud_decision_feedback);
      ChartRedraw(0);
      return true;
   }

   StoreHUDRecordedDecision(g_hud_decision_event.key, action);
   g_hud_decision_action = action;
   g_hud_decision_feedback = "REGISTRADO: " + action;
   ObjectSetString(0, "LZ_HUD_EVENT_FEEDBACK", OBJPROP_TEXT, g_hud_decision_feedback);
   ChartRedraw(0);
   return true;
}

#endif
