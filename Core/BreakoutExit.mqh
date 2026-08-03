#ifndef MARKETREGIME_CORE_BREAKOUTEXIT_MQH
#define MARKETREGIME_CORE_BREAKOUTEXIT_MQH

#include "Types.mqh"

enum ENUM_BREAKOUT_INDICATOR_EXIT
{
   BREAKOUT_INDICATOR_EXIT_NONE = 0,
   BREAKOUT_INDICATOR_EXIT_STRUCTURE = 1,
   BREAKOUT_INDICATOR_EXIT_FLOW_REVERSAL = 2,
   BREAKOUT_INDICATOR_EXIT_EXHAUSTION_REVERSAL = 3
};

struct BreakoutExitState
{
   bool valid;
   ENUM_REGIME_STATE regime;
   int biasDir;
   int microDir;
   bool hasExhaustion;
   double exhaustion01;
};

void ResetBreakoutExitState(BreakoutExitState &state)
{
   state.valid = false;
   state.regime = REGIME_MIXED;
   state.biasDir = 0;
   state.microDir = 0;
   state.hasExhaustion = false;
   state.exhaustion01 = 0.0;
}

void BuildBreakoutExitState(const StateSnapshot &snapshot,
                            BreakoutExitState &state)
{
   ResetBreakoutExitState(state);
   if (!snapshot.valid)
      return;

   state.valid = true;
   state.regime = snapshot.regime;
   state.biasDir = snapshot.biasDir;
   state.microDir = snapshot.microDir;
   state.hasExhaustion = snapshot.hasExhaustion;
   state.exhaustion01 = snapshot.exhaustion01;
}

string BreakoutIndicatorExitToString(const ENUM_BREAKOUT_INDICATOR_EXIT reason)
{
   if (reason == BREAKOUT_INDICATOR_EXIT_STRUCTURE)
      return "STRUCTURE";
   if (reason == BREAKOUT_INDICATOR_EXIT_FLOW_REVERSAL)
      return "FLOW_REVERSAL";
   if (reason == BREAKOUT_INDICATOR_EXIT_EXHAUSTION_REVERSAL)
      return "EXHAUSTION_REVERSAL";
   return "NONE";
}

ENUM_BREAKOUT_INDICATOR_EXIT EvaluateBreakoutIndicatorExit(const int direction,
                                                           const int completedHoldBars,
                                                           const double signalZoneTop,
                                                           const double signalZoneBottom,
                                                           const double signalZoneStep,
                                                           const double closePrice,
                                                           const BreakoutExitState &state,
                                                           const bool enabled,
                                                           const bool enableStructureExit,
                                                           const bool enableFlowReversalExit,
                                                           const bool enableExhaustionReversalExit,
                                                           const int minHoldBars,
                                                           const double insideZoneStepFraction,
                                                           const double exhaustionThreshold,
                                                           const double eps)
{
   if (!enabled ||
       direction == 0 ||
       completedHoldBars < MathMax(1, minHoldBars) ||
       signalZoneStep <= eps)
   {
      return BREAKOUT_INDICATOR_EXIT_NONE;
   }

   const double insideMargin = MathMax(0.0, insideZoneStepFraction) * signalZoneStep;
   const bool structureFailed = (direction > 0
                                 ? closePrice <= (signalZoneTop - insideMargin)
                                 : closePrice >= (signalZoneBottom + insideMargin));
   if (enableStructureExit && structureFailed)
      return BREAKOUT_INDICATOR_EXIT_STRUCTURE;

   if (!state.valid)
      return BREAKOUT_INDICATOR_EXIT_NONE;

   const bool biasOpposes = (state.biasDir == -direction);
   const bool microOpposes = (state.microDir == -direction);
   if (enableFlowReversalExit && biasOpposes && microOpposes)
      return BREAKOUT_INDICATOR_EXIT_FLOW_REVERSAL;

   if (enableExhaustionReversalExit &&
       microOpposes &&
       state.hasExhaustion &&
       state.exhaustion01 >= exhaustionThreshold)
   {
      return BREAKOUT_INDICATOR_EXIT_EXHAUSTION_REVERSAL;
   }

   return BREAKOUT_INDICATOR_EXIT_NONE;
}

#endif
