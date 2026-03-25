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
   double top;
   double bottom;
   double mid;
   int length;
   double avgScore;
   double path;
   int touchTop;
   int touchBot;
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
};

#endif
