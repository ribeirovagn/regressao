#ifndef MARKETREGIME_CORE_TYPES_MQH
#define MARKETREGIME_CORE_TYPES_MQH

enum ENUM_SLOPE_NORM_MODE
{
   SLOPE_NORM_MEAN = 0,
   SLOPE_NORM_STD = 1
};

enum ENUM_ZONE_STATE
{
   Z_ACTIVE = 0,
   Z_BREAK_UP = 1,
   Z_BREAK_DOWN = 2
};

enum ENUM_REGIME_STATE
{
   REGIME_RANGE = 0,
   REGIME_TREND = 1,
   REGIME_MIXED = 2
};

enum ENUM_STEP_SOURCE
{
   STEP_SOURCE_NONE = 0,
   STEP_SOURCE_ACTIVE = 1,
   STEP_SOURCE_LAST_BROKEN = 2
};

struct LRMetrics
{
   bool valid;
   double b_norm;
   double r2;
   double er;
};

struct ZoneInfo
{
   bool valid;
   datetime t_left;
   datetime t_right;
   datetime t_cluster_right;
   datetime t_break;
   double top;
   double bottom;
   double mid;
   int length;
   double avgScore;
   double path;
   double netClose;
   int touchTop;
   int touchBot;
   int startIndex;
   int endIndex;
   int breakIndex;
   ENUM_ZONE_STATE state;
};

struct ZoneSelectionState
{
   ZoneInfo lastActive;
   ZoneInfo lastBroken;
   ZoneInfo projectionZone;
   double lastActiveNetClose;
   double lastBrokenNetClose;
   bool hasProjectionZone;
};

struct TrendState
{
   LRMetrics mainMetrics;
   LRMetrics microMetrics;
   LRMetrics shortMetrics;
   double slope01;
   double strength01;
   double shortStrength01;
   int biasDir;
   int microDir;
   ENUM_REGIME_STATE regime;
};

struct VolumeState
{
   bool valid;
   int bias;
   double confirmation01;
   double b_norm;
   double r2;
   double ratio;
   double slope01;
};

struct HUDState
{
   ENUM_REGIME_STATE regime;
   int biasDir;
   int microDir;
   double strength01;
   bool hasTrendExhaustion;
   int trendExhaustionPct;
   bool hasBreakQuality;
   int breakQualityPct;
   double step;
   string stepSource;
   double r2;
   double er;
   double slope01;
   bool hasZoneEnergy;
   int zoneEnergyPct;
   bool hasVolume;
   int volumeBiasDir;
   int volumeConfirmPct;
   double volumeR2;
   double volumeRatio;
   double volumeSlope01;
};

struct StateEngineConfig
{
   int window;
   int microtrendWindow;
   int shortWindow;
   ENUM_SLOPE_NORM_MODE slopeNormMode;
   double slopeThresholdMean;
   double slopeThresholdStd;
   double r2Threshold;
   double scoreSlopeWeight;
   int minZoneBars;
   int gapTolerance;
   bool extendUntilBreak;
   double breakMarginPoints;
   double trendThreshold;
   double trendWeightSlope;
   double trendWeightR2;
   double trendWeightER;
   bool enableTrendExhaustion;
   double exhaustDistanceScale;
   double exhaustWeightDistance;
   double exhaustWeightStrength;
   double exhaustWeightNoise;
   bool enableBreakQuality;
   bool enableZoneEnergy;
   int zoneEnergyLenScale;
   int zoneEnergyTouchMarginPoints;
   int zoneEnergyTouchScale;
   double zoneEnergyWeightLen;
   double zoneEnergyWeightComp;
   double zoneEnergyWeightChop;
   double zoneEnergyWeightTouch;
   double breakQualityWeightStrength;
   double breakQualityWeightEnergy;
   double breakQualityWeightPenetr;
   double breakQualityWeightFresh;
   bool enableVolumeConfirmation;
   int volumeWindowShort;
   int volumeWindowLong;
   double volumeWeightSlope;
   double volumeWeightR2;
   double volumeWeightRatio;
   double volumeRatioScale;
   double volumeSlopeThreshold;
   bool showVolumeDetails;
};

struct StateSnapshot
{
   bool valid;
   ENUM_REGIME_STATE regime;
   int biasDir;
   int microDir;
   bool hasStrength;
   double strength01;
   bool hasExhaustion;
   double exhaustion01;
   bool hasBreakQuality;
   double breakQuality01;
   bool hasStep;
   double step;
   double stepMid;
   ENUM_STEP_SOURCE stepSource;
   bool hasZoneEnergy;
   double zoneEnergy01;
   bool hasActiveZone;
   bool hasBrokenZone;
   double slope01;
   bool hasVolume;
   VolumeState volumeState;
   LRMetrics mainMetrics;
   LRMetrics microMetrics;
   LRMetrics shortMetrics;
   ZoneInfo lastActive;
   ZoneInfo lastBroken;
};

#endif
