//+------------------------------------------------------------------+
//| SMC ZigZag Structure Logic - Multi-Timeframe Version (Optimized) |
//| v1.4.1 -> v1.5 (performance + clarity + normalization fix)       |
//| All .mqh dependencies integrated                                 |
//+------------------------------------------------------------------+
#property copyright "ITRAD SOCIETY"
#property link      "https://www.itrad.com"
#property version   "1.5"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   0

//+------------------------------------------------------------------+
//| STRUCTURES                                                       |
//+------------------------------------------------------------------+
struct SZigZagPoint
{
   datetime time;
   double   price;
   int      index;
   bool     isHigh;
};

struct SMarketStructure
{
   SZigZagPoint points[];
   string       labels[];
   int          trend;          // 1=Bullish, -1=Bearish, 0=Neutral
};

struct SZZParams
{
   int    depth;
   int    deviation_points;
   int    backstep;
   double deviation_price;
   int    minRates;
};

struct SBreakoutInfo
{
   datetime pointA_time;
   double   pointA_price;
   datetime pointB_time;
   bool     isUpperBreakout;
   string   structureType;
   int      pointIndex;
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "═══ HTF STRUCTURE ═══"
input int DepthHTF = 48;
input int DeviationHTF = 48;
input int BackstepHTF = 48;

input group "═══ HTF TIMEFRAMES ═══"
input ENUM_TIMEFRAMES InpHTF = PERIOD_CURRENT;

input group "═══ HTF DISPLAY ═══"
input bool ShowStructure = true;
input int MaxZigZagPoints = 200;
input bool ShowHighLowLabels = true;
input bool ShowHLHHLHLLLabels = true;
input int Default_Font_Size = 13;
input string Default_Font = "Courier New";

input group "═══ HTF BREAKOUT ═══"
input bool ShowBreakoutLines = false;
input int MaxScanBars = 500;
input bool AllowWickBreaks = false;
input bool ConfirmByClose = true;
input color BreakoutLineColor = clrLimeGreen;
input ENUM_LINE_STYLE BreakoutLineStyle = STYLE_SOLID;
input int BreakoutLineWidth = 2;

input group "═══ INTERNAL STRUCTURE ═══"
input bool EnableInternalStructure = true;
input ENUM_TIMEFRAMES Internal_TF = PERIOD_CURRENT;
input bool ShowInternalStructure = true;
input int DepthInternal = 17;
input int DeviationInternal = 17;
input int BackstepInternal = 25;
input int MaxZigZagPoints_Internal = 100;

input group "═══ INTERNAL DISPLAY ═══"
input color Internal_Color = clrBlack;
input int Internal_FontSize = 11;
input string Internal_Font = "Courier New";

input group "═══ INTERNAL BREAKOUT ═══"
input bool Internal_ShowBreakoutLines = true;
input int Internal_MaxScanBars = 300;
input bool Internal_AllowWickBreaks = false;
input bool Internal_ConfirmByClose = true;
input color Internal_BreakoutLineColor = clrMidnightBlue;
input ENUM_LINE_STYLE Internal_BreakoutLineStyle = STYLE_DASHDOT;
input int Internal_BreakoutLineWidth = 1;

input group "═══ RETRACEMENT FILTER ═══"
input bool UseRetracementFilter = false;
input double MaxRetracementPercent = 40.0;

// Fixed (non-editable) anchors
const ENUM_ANCHOR_POINT HTF_Anchor_High = ANCHOR_RIGHT_LOWER;
const ENUM_ANCHOR_POINT HTF_Anchor_Low  = ANCHOR_RIGHT_UPPER;
const ENUM_ANCHOR_POINT Internal_Anchor_High = ANCHOR_LEFT_LOWER;
const ENUM_ANCHOR_POINT Internal_Anchor_Low  = ANCHOR_LEFT_UPPER;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
double ZigZagHigh_HTF[], ZigZagLow_HTF[];
double ZigZagHigh_INT[], ZigZagLow_INT[];
SMarketStructure g_structure_HTF;
SMarketStructure g_structure_INT;
SBreakoutInfo g_breakouts_HTF[];
SBreakoutInfo g_breakouts_INT[];

// Cache for optimization
ulong g_lastVisualSig = 0;
int g_lastHTFCount = -1;
int g_lastINTCount = -1;

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

// Get simple timeframe name (e.g. "M15", "H1", "D1")
string GetSimpleTFName(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_CURRENT) return IntegerToString(Period());
   string s = EnumToString(tf);
   int pos = StringFind(s, "PERIOD_");
   if(pos >= 0) s = StringSubstr(s, pos + 7);
   StringToLower(s);
   return s;
}

// Compute visual signature for redraw detection
ulong ComputeVisualSignature()
{
   ulong sig = 5381;
   sig = ((sig << 5) + sig) ^ (ulong)ShowStructure;
   sig = ((sig << 5) + sig) ^ (ulong)ShowHighLowLabels;
   sig = ((sig << 5) + sig) ^ (ulong)ShowHLHHLHLLLabels;
   sig = ((sig << 5) + sig) ^ (ulong)EnableInternalStructure;
   sig = ((sig << 5) + sig) ^ (ulong)ShowInternalStructure;
   sig = ((sig << 5) + sig) ^ (ulong)ShowBreakoutLines;
   sig = ((sig << 5) + sig) ^ (ulong)Internal_ShowBreakoutLines;
   return sig;
}

// Check if retracement is within allowed %
bool IsRetracementAllowed(double high, double low, double candPrice, double maxRetracePct)
{
   if(!UseRetracementFilter) return true;
   if(high == low) return true;
   double range = high - low;
   double retracement = MathAbs(candPrice - low) / range * 100.0;
   return (retracement <= maxRetracePct);
}

//+------------------------------------------------------------------+
//| ZIGZAG CALCULATION (with SZZParams)                             |
//+------------------------------------------------------------------+
void CalculateZigZag(const double &high[], const double &low[], int rates_total,
                     double &outHigh[], double &outLow[], const SZZParams &params)
{
   ArrayInitialize(outHigh, EMPTY_VALUE);
   ArrayInitialize(outLow, EMPTY_VALUE);
   if(rates_total <= 0) return;

   double lastLow = 0.0, lastHigh = 0.0;
   int limit = rates_total - params.minRates;
   if(limit < 0) limit = 0;

   double highMap[], lowMap[];
   ArrayResize(highMap, rates_total);
   ArrayResize(lowMap, rates_total);
   ArrayInitialize(highMap, EMPTY_VALUE);
   ArrayInitialize(lowMap, EMPTY_VALUE);

   // Forward pass: detect local extremes
   for(int bar = limit; bar >= 0; bar--)
   {
      int depthCount = MathMin(params.depth, rates_total - bar);
      if(depthCount <= 0) depthCount = 1;

      // Find minimum
      int minPos = ArrayMinimum(low, bar, depthCount);
      double valLow = low[minPos];
      if(valLow != lastLow && low[bar] - valLow <= params.deviation_price)
      {
         for(int back = 1; back <= params.backstep; back++)
         {
            int idx = bar + back;
            if(idx < rates_total && lowMap[idx] != EMPTY_VALUE && lowMap[idx] > valLow)
               lowMap[idx] = EMPTY_VALUE;
         }
         if(low[bar] == valLow) lowMap[bar] = valLow;
         lastLow = valLow;
      }

      // Find maximum
      int maxPos = ArrayMaximum(high, bar, depthCount);
      double valHigh = high[maxPos];
      if(valHigh != lastHigh && valHigh - high[bar] <= params.deviation_price)
      {
         for(int back = 1; back <= params.backstep; back++)
         {
            int idx = bar + back;
            if(idx < rates_total && highMap[idx] != EMPTY_VALUE && highMap[idx] < valHigh)
               highMap[idx] = EMPTY_VALUE;
         }
         if(high[bar] == valHigh) highMap[bar] = valHigh;
         lastHigh = valHigh;
      }
   }

   BuildZigZagStructure(highMap, lowMap, rates_total, outHigh, outLow);
}

void BuildZigZagStructure(const double &highMap[], const double &lowMap[], int rates_total,
                          double &outHigh[], double &outLow[])
{
   ArrayInitialize(outHigh, EMPTY_VALUE);
   ArrayInitialize(outLow, EMPTY_VALUE);

   int state = 0;
   double curHigh = 0.0, curLow = 0.0;
   int lastHighPos = -1, lastLowPos = -1;

   for(int bar = rates_total - 1; bar >= 0; bar--)
   {
      switch(state)
      {
         case 0: // Initial state: look for first extreme
            if(highMap[bar] != EMPTY_VALUE)
            {
               curHigh = highMap[bar];
               lastHighPos = bar;
               outHigh[bar] = curHigh;
               state = -1;
            }
            if(lowMap[bar] != EMPTY_VALUE)
            {
               curLow = lowMap[bar];
               lastLowPos = bar;
               outLow[bar] = curLow;
               state = 1;
            }
            break;

         case 1: // Looking for lower low (or high to reverse)
            if(lowMap[bar] != EMPTY_VALUE && lowMap[bar] < curLow)
            {
               if(lastLowPos != -1) outLow[lastLowPos] = EMPTY_VALUE;
               lastLowPos = bar;
               curLow = lowMap[bar];
               outLow[bar] = curLow;
            }
            if(highMap[bar] != EMPTY_VALUE)
            {
               curHigh = highMap[bar];
               lastHighPos = bar;
               outHigh[bar] = curHigh;
               state = -1;
            }
            break;

         case -1: // Looking for higher high (or low to reverse)
            if(highMap[bar] != EMPTY_VALUE && highMap[bar] > curHigh)
            {
               if(lastHighPos != -1) outHigh[lastHighPos] = EMPTY_VALUE;
               lastHighPos = bar;
               curHigh = highMap[bar];
               outHigh[bar] = curHigh;
            }
            if(lowMap[bar] != EMPTY_VALUE)
            {
               curLow = lowMap[bar];
               lastLowPos = bar;
               outLow[bar] = curLow;
               state = 1;
            }
            break;
      }
   }
}

//+------------------------------------------------------------------+
//| STRUCTURE SORTING & NORMALIZATION (KEY FIX)                     |
//+------------------------------------------------------------------+

// Sort points by time ascending (oldest -> newest) using insertion sort
void SortStructurePointsByTime(SMarketStructure &structure)
{
   int n = ArraySize(structure.points);
   if(n <= 1) return;

   for(int i = 1; i < n; i++)
   {
      SZigZagPoint key = structure.points[i];
      int j = i - 1;
      while(j >= 0 && structure.points[j].time > key.time)
      {
         structure.points[j + 1] = structure.points[j];
         j--;
      }
      structure.points[j + 1] = key;
   }
}

// Normalize: ensure High/Low alternation by keeping extremes
// If two Highs consecutive -> keep the higher high
// If two Lows consecutive -> keep the lower low
void NormalizeStructurePoints(SMarketStructure &structure)
{
   int n = ArraySize(structure.points);
   if(n <= 1) return;

   SZigZagPoint normalized[];
   ArrayResize(normalized, 1);
   normalized[0] = structure.points[0];

   for(int i = 1; i < n; i++)
   {
      SZigZagPoint current = structure.points[i];
      int normCount = ArraySize(normalized);
      SZigZagPoint last = normalized[normCount - 1];  // FIXED: Removed & reference

      if(current.isHigh == last.isHigh)
      {
         // Same type: keep the extreme
         if(current.isHigh && current.price > last.price)
         {
            // Higher high -> replace
            normalized[normCount - 1] = current;
         }
         else if(!current.isHigh && current.price < last.price)
         {
            // Lower low -> replace
            normalized[normCount - 1] = current;
         }
         // Else: skip (less extreme)
      }
      else
      {
         // Different type: add (alternation maintained)
         ArrayResize(normalized, normCount + 1);
         normalized[normCount] = current;
      }
   }

   // Copy back
   ArrayResize(structure.points, ArraySize(normalized));
   for(int k = 0; k < ArraySize(normalized); k++)
      structure.points[k] = normalized[k];
}

//+------------------------------------------------------------------+
//| LABELING (SIMPLIFIED & CORRECT)                                 |
//+------------------------------------------------------------------+

void LabelZigZagStructure(SMarketStructure &structure, const datetime &series_time[], const double &series_close[])
{
   int n = ArraySize(structure.points);
   ArrayResize(structure.labels, n);

   // Default base labels
   for(int i = 0; i < n; i++)
      structure.labels[i] = (structure.points[i].isHigh ? "H" : "L");

   if(n < 2) { structure.trend = 0; return; }

   // Find most recent high and low
   int lastHighIdx = -1, lastLowIdx = -1;
   for(int i = n - 1; i >= 0; i--)
   {
      if(structure.points[i].isHigh && lastHighIdx == -1) lastHighIdx = i;
      if(!structure.points[i].isHigh && lastLowIdx == -1) lastLowIdx = i;
      if(lastHighIdx != -1 && lastLowIdx != -1) break;
   }

   if(lastHighIdx == -1 || lastLowIdx == -1) { structure.trend = 0; return; }

   // Determine direction: if last low is newer than last high -> bullish candidate
   bool candidateBullish = (lastLowIdx > lastHighIdx);
   structure.trend = candidateBullish ? 1 : -1;

   // Now label HH/HL/LH/LL based on direction
   if(candidateBullish)
   {
      // Bullish: compare each high to previous highs, each low to previous lows
      double lastHigh = EMPTY_VALUE, lastLow = EMPTY_VALUE;
      for(int i = 0; i < n; i++)
      {
         if(structure.points[i].isHigh)
         {
            if(lastHigh == EMPTY_VALUE)
               structure.labels[i] = "H";
            else
               structure.labels[i] = (structure.points[i].price > lastHigh) ? "HH" : "LH";
            lastHigh = structure.points[i].price;
         }
         else
         {
            if(lastLow == EMPTY_VALUE)
               structure.labels[i] = "L";
            else
               structure.labels[i] = (structure.points[i].price > lastLow) ? "HL" : "LL";
            lastLow = structure.points[i].price;
         }
      }
   }
   else
   {
      // Bearish: compare each high to previous highs, each low to previous lows
      double lastHigh = EMPTY_VALUE, lastLow = EMPTY_VALUE;
      for(int i = 0; i < n; i++)
      {
         if(structure.points[i].isHigh)
         {
            if(lastHigh == EMPTY_VALUE)
               structure.labels[i] = "H";
            else
               structure.labels[i] = (structure.points[i].price < lastHigh) ? "LH" : "HH";
            lastHigh = structure.points[i].price;
         }
         else
         {
            if(lastLow == EMPTY_VALUE)
               structure.labels[i] = "L";
            else
               structure.labels[i] = (structure.points[i].price < lastLow) ? "LL" : "HL";
            lastLow = structure.points[i].price;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| UPDATE MARKET STRUCTURE (collect, sort, normalize, label)       |
//+------------------------------------------------------------------+

void UpdateMarketStructure(const datetime &series_time[], const double &series_high[],
                           const double &series_low[], const double &series_close[], int rates_total,
                           SMarketStructure &structure,
                           const double &ZigZagHigh[], const double &ZigZagLow[], int maxPoints)
{
   ArrayResize(structure.points, 0);
   ArrayResize(structure.labels, 0);
   structure.trend = 0;

   // Collect all zigzag points
   int count = 0;
   for(int i = 0; i < rates_total && count < maxPoints; i++)
   {
      if(ZigZagHigh[i] != EMPTY_VALUE)
      {
         SZigZagPoint p;
         p.time = series_time[i];
         p.price = ZigZagHigh[i];
         p.index = i;
         p.isHigh = true;
         int sz = ArraySize(structure.points);
         ArrayResize(structure.points, sz + 1);
         structure.points[sz] = p;
         count++;
      }
      if(count < maxPoints && ZigZagLow[i] != EMPTY_VALUE)
      {
         SZigZagPoint p;
         p.time = series_time[i];
         p.price = ZigZagLow[i];
         p.index = i;
         p.isHigh = false;
         int sz = ArraySize(structure.points);
         ArrayResize(structure.points, sz + 1);
         structure.points[sz] = p;
         count++;
      }
   }

   // KEY STEPS: sort, normalize, label
   SortStructurePointsByTime(structure);
   NormalizeStructurePoints(structure);   // <-- This fixes the HH/HL/LL mélange
   LabelZigZagStructure(structure, series_time, series_close);
}

//+------------------------------------------------------------------+
//| BREAKOUT DETECTION                                               |
//+------------------------------------------------------------------+

void DetectBreakouts(const datetime &series_time[], const double &series_high[], const double &series_low[], const double &series_close[],
                     SMarketStructure &structure, SBreakoutInfo &breakouts[], int maxScanBars, bool allowWickBreaks)
{
   ArrayResize(breakouts, 0);
   int n = ArraySize(structure.points);
   if(n <= 0) return;

   for(int i = 0; i < n; i++)
   {
      SZigZagPoint pt = structure.points[i];
      int ptIndex = pt.index;
      if(ptIndex <= 0) continue;

      int maxBars = MathMin(ptIndex, maxScanBars);
      bool foundBreak = false;

      if(pt.isHigh)
      {
         // High: look for close above or wick above
         for(int j = ptIndex - 1; j >= MathMax(0, ptIndex - maxBars) && !foundBreak; j--)
         {
            if(series_close[j] > pt.price || (allowWickBreaks && series_high[j] > pt.price))
            {
               SBreakoutInfo bo;
               bo.pointA_time = pt.time;
               bo.pointA_price = pt.price;
               bo.pointB_time = series_time[j];
               bo.isUpperBreakout = true;
               bo.structureType = (i < ArraySize(structure.labels)) ? structure.labels[i] : "";
               bo.pointIndex = i;
               int sz = ArraySize(breakouts);
               ArrayResize(breakouts, sz + 1);
               breakouts[sz] = bo;
               foundBreak = true;
            }
         }
      }
      else
      {
         // Low: look for close below or wick below
         for(int j = ptIndex - 1; j >= MathMax(0, ptIndex - maxBars) && !foundBreak; j--)
         {
            if(series_close[j] < pt.price || (allowWickBreaks && series_low[j] < pt.price))
            {
               SBreakoutInfo bo;
               bo.pointA_time = pt.time;
               bo.pointA_price = pt.price;
               bo.pointB_time = series_time[j];
               bo.isUpperBreakout = false;
               bo.structureType = (i < ArraySize(structure.labels)) ? structure.labels[i] : "";
               bo.pointIndex = i;
               int sz = ArraySize(breakouts);
               ArrayResize(breakouts, sz + 1);
               breakouts[sz] = bo;
               foundBreak = true;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DRAW BREAKOUT LINES                                              |
//+------------------------------------------------------------------+

void DrawBreakoutLines(SBreakoutInfo &breakouts[], SMarketStructure &structure, string prefix, 
                       color lineColor, ENUM_LINE_STYLE lineStyle, int lineWidth)
{
   int n = ArraySize(breakouts);
   for(int i = 0; i < n; i++)
   {
      int pIndex = breakouts[i].pointIndex;
      if(pIndex < 0 || pIndex >= ArraySize(structure.points)) continue;

      string nameLine = prefix + "Breakout_" + IntegerToString(i);
      datetime tA = breakouts[i].pointA_time;
      double pA = breakouts[i].pointA_price;
      datetime tB = breakouts[i].pointB_time;

      if(ObjectFind(0, nameLine) == -1)
      {
         ObjectCreate(0, nameLine, OBJ_TREND, 0, tA, pA, tB, pA);
         ObjectSetInteger(0, nameLine, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, nameLine, OBJPROP_STYLE, lineStyle);
         ObjectSetInteger(0, nameLine, OBJPROP_WIDTH, lineWidth);
         ObjectSetInteger(0, nameLine, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, nameLine, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, nameLine, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nameLine, OBJPROP_HIDDEN, false);
      }
      else
      {
         ObjectMove(0, nameLine, 0, tA, pA);
         ObjectMove(0, nameLine, 1, tB, pA);
      }
   }
}

//+------------------------------------------------------------------+
//| VISUAL: DELETE & DRAW                                            |
//+------------------------------------------------------------------+

void DeleteIndicatorObjects()
{
   string prefix = "SMC_";
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringLen(name) > 0 && StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void DrawMarketElements()
{
   // Check if we need to redraw (caching)
   ulong currentSig = ComputeVisualSignature();
   int htfCount = ArraySize(g_structure_HTF.points);
   int intCount = ArraySize(g_structure_INT.points);
   int htfBreakouts = ArraySize(g_breakouts_HTF);
   int intBreakouts = ArraySize(g_breakouts_INT);

   if(g_lastVisualSig == currentSig && g_lastHTFCount == htfCount && g_lastINTCount == intCount)
      return; // Nothing changed, skip redraw

   g_lastVisualSig = currentSig;
   g_lastHTFCount = htfCount;
   g_lastINTCount = intCount;

   DeleteIndicatorObjects();
   string prefix = "SMC_";

   // Info label
   string infoName = prefix + "Info";
   if(ObjectCreate(0, infoName, OBJ_LABEL, 0, 0, 0))
   {
      string info = "HTF: " + IntegerToString(htfCount) + " pts | INT: " + IntegerToString(intCount) + " pts | HTF-BO: " + IntegerToString(htfBreakouts) + " | INT-BO: " + IntegerToString(intBreakouts);
      ObjectSetString(0, infoName, OBJPROP_TEXT, info);
      ObjectSetInteger(0, infoName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, infoName, OBJPROP_FONTSIZE, Default_Font_Size + 2);
      ObjectSetInteger(0, infoName, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, infoName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, infoName, OBJPROP_YDISTANCE, 10);
   }

   // Draw HTF labels
   if(ShowStructure && htfCount > 0)
   {
      int limit = MathMin(htfCount, MaxZigZagPoints);
      for(int i = 0; i < limit; i++)
      {
         string label = g_structure_HTF.labels[i];
         if(StringLen(label) == 0) continue;

         bool show = false;
         if(ShowHighLowLabels && (label == "H" || label == "L")) show = true;
         if(ShowHLHHLHLLLabels && (label == "HH" || label == "LL" || label == "HL" || label == "LH")) show = true;
         if(!show) continue;

         string name = prefix + "HTF_" + IntegerToString(i);
         datetime t = g_structure_HTF.points[i].time;
         double p = g_structure_HTF.points[i].price;
         bool isHigh = g_structure_HTF.points[i].isHigh;

         if(ObjectFind(0, name) == -1)
         {
            ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
            ObjectSetString(0, name, OBJPROP_TEXT, label);
            ObjectSetString(0, name, OBJPROP_FONT, Default_Font);
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, Default_Font_Size);
            ObjectSetInteger(0, name, OBJPROP_COLOR, isHigh ? clrBlue : clrRed);
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, isHigh ? HTF_Anchor_High : HTF_Anchor_Low);
         }
         else
         {
            ObjectMove(0, name, 0, t, p);
         }
      }
   }

   // Draw Internal labels
   if(EnableInternalStructure && ShowInternalStructure && intCount > 0)
   {
      int limit = MathMin(intCount, MaxZigZagPoints_Internal);
      for(int i = 0; i < limit; i++)
      {
         string label = g_structure_INT.labels[i];
         if(StringLen(label) == 0) continue;

         bool show = false;
         if(ShowHighLowLabels && (label == "H" || label == "L")) show = true;
         if(ShowHLHHLHLLLabels && (label == "HH" || label == "LL" || label == "HL" || label == "LH")) show = true;
         if(!show) continue;

         string name = prefix + "INT_" + IntegerToString(i);
         datetime t = g_structure_INT.points[i].time;
         double p = g_structure_INT.points[i].price;
         bool isHigh = g_structure_INT.points[i].isHigh;

         if(ObjectFind(0, name) == -1)
         {
            ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
            ObjectSetString(0, name, OBJPROP_TEXT, label);
            ObjectSetString(0, name, OBJPROP_FONT, Internal_Font);
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, Internal_FontSize);
            ObjectSetInteger(0, name, OBJPROP_COLOR, Internal_Color);
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, isHigh ? Internal_Anchor_High : Internal_Anchor_Low);
         }
         else
         {
            ObjectMove(0, name, 0, t, p);
         }
      }
   }

   // Draw breakout lines
   if(ShowBreakoutLines && htfBreakouts > 0)
      DrawBreakoutLines(g_breakouts_HTF, g_structure_HTF, prefix + "HTF_BO_", BreakoutLineColor, BreakoutLineStyle, BreakoutLineWidth);

   if(EnableInternalStructure && Internal_ShowBreakoutLines && intBreakouts > 0)
      DrawBreakoutLines(g_breakouts_INT, g_structure_INT, prefix + "INT_BO_", Internal_BreakoutLineColor, Internal_BreakoutLineStyle, Internal_BreakoutLineWidth);
}

//+------------------------------------------------------------------+
//| INIT / DEINIT / CALCULATE                                        |
//+------------------------------------------------------------------+

int OnInit()
{
   SetIndexBuffer(0, ZigZagHigh_HTF, INDICATOR_DATA);
   SetIndexBuffer(1, ZigZagLow_HTF, INDICATOR_DATA);
   SetIndexBuffer(2, ZigZagHigh_INT, INDICATOR_DATA);
   SetIndexBuffer(3, ZigZagLow_INT, INDICATOR_DATA);

   ArraySetAsSeries(ZigZagHigh_HTF, true);
   ArraySetAsSeries(ZigZagLow_HTF, true);
   ArraySetAsSeries(ZigZagHigh_INT, true);
   ArraySetAsSeries(ZigZagLow_INT, true);

   IndicatorSetString(INDICATOR_SHORTNAME, "SMC STRUCTURE MTF v1.5 (Optimized + Breakouts)");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteIndicatorObjects();
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total < 50) return 0;

   if(prev_calculated == 0)
   {
      ArrayInitialize(ZigZagHigh_HTF, EMPTY_VALUE);
      ArrayInitialize(ZigZagLow_HTF, EMPTY_VALUE);
      ArrayInitialize(ZigZagHigh_INT, EMPTY_VALUE);
      ArrayInitialize(ZigZagLow_INT, EMPTY_VALUE);
   }

   // Build HTF params
   SZZParams htfParams;
   htfParams.depth = DepthHTF;
   htfParams.deviation_points = DeviationHTF;
   htfParams.backstep = BackstepHTF;
   htfParams.deviation_price = DeviationHTF * _Point;
   htfParams.minRates = htfParams.depth + htfParams.backstep;

   // Calculate HTF
   if(InpHTF == PERIOD_CURRENT)
   {
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(time, true);

      CalculateZigZag(high, low, rates_total, ZigZagHigh_HTF, ZigZagLow_HTF, htfParams);
      UpdateMarketStructure(time, high, low, close, rates_total, g_structure_HTF, ZigZagHigh_HTF, ZigZagLow_HTF, MaxZigZagPoints);
   }
   else
   {
      // Copy HTF rates
      int barsToReq = MathMax(MaxZigZagPoints * 5, htfParams.minRates + 10);
      MqlRates rates_HTF[];
      int copiedHTF = CopyRates(_Symbol, InpHTF, 0, barsToReq, rates_HTF);

      if(copiedHTF > htfParams.minRates)
      {
         double high_HTF[], low_HTF[], close_HTF[];
         datetime time_HTF[];
         ArrayResize(high_HTF, copiedHTF);
         ArrayResize(low_HTF, copiedHTF);
         ArrayResize(close_HTF, copiedHTF);
         ArrayResize(time_HTF, copiedHTF);

         for(int i = 0; i < copiedHTF; i++)
         {
            high_HTF[i] = rates_HTF[i].high;
            low_HTF[i] = rates_HTF[i].low;
            close_HTF[i] = rates_HTF[i].close;
            time_HTF[i] = rates_HTF[i].time;
         }

         ArraySetAsSeries(high_HTF, true);
         ArraySetAsSeries(low_HTF, true);
         ArraySetAsSeries(close_HTF, true);
         ArraySetAsSeries(time_HTF, true);

         CalculateZigZag(high_HTF, low_HTF, copiedHTF, ZigZagHigh_HTF, ZigZagLow_HTF, htfParams);
         UpdateMarketStructure(time_HTF, high_HTF, low_HTF, close_HTF, copiedHTF, g_structure_HTF, ZigZagHigh_HTF, ZigZagLow_HTF, MaxZigZagPoints);
      }
   }

   // Detect HTF breakouts FIXED: Added missing call
   if(ShowBreakoutLines && ArraySize(g_structure_HTF.points) > 0)
   {
      DetectBreakouts(time, high, low, close, g_structure_HTF, g_breakouts_HTF, MaxScanBars, AllowWickBreaks);
   }
   else
   {
      ArrayResize(g_breakouts_HTF, 0);
   }

   // Calculate Internal Structure
   if(EnableInternalStructure)
   {
      SZZParams intParams;
      intParams.depth = DepthInternal;
      intParams.deviation_points = DeviationInternal;
      intParams.backstep = BackstepInternal;
      intParams.deviation_price = DeviationInternal * _Point;
      intParams.minRates = intParams.depth + intParams.backstep;

      int barsToReq = MathMax(MaxZigZagPoints_Internal * 5, intParams.minRates + 10);
      MqlRates rates_INT[];
      int copiedINT = CopyRates(_Symbol, Internal_TF, 0, barsToReq, rates_INT);

      if(copiedINT > intParams.minRates)
      {
         double high_INT[], low_INT[], close_INT[];
         datetime time_INT[];
         ArrayResize(high_INT, copiedINT);
         ArrayResize(low_INT, copiedINT);
         ArrayResize(close_INT, copiedINT);
         ArrayResize(time_INT, copiedINT);

         for(int i = 0; i < copiedINT; i++)
         {
            high_INT[i] = rates_INT[i].high;
            low_INT[i] = rates_INT[i].low;
            close_INT[i] = rates_INT[i].close;
            time_INT[i] = rates_INT[i].time;
         }

         ArraySetAsSeries(high_INT, true);
         ArraySetAsSeries(low_INT, true);
         ArraySetAsSeries(close_INT, true);
         ArraySetAsSeries(time_INT, true);

         CalculateZigZag(high_INT, low_INT, copiedINT, ZigZagHigh_INT, ZigZagLow_INT, intParams);
         UpdateMarketStructure(time_INT, high_INT, low_INT, close_INT, copiedINT, g_structure_INT, ZigZagHigh_INT, ZigZagLow_INT, MaxZigZagPoints_Internal);
      }
   }
   else
   {
      ArrayResize(g_structure_INT.points, 0);
      ArrayResize(g_structure_INT.labels, 0);
      ArrayResize(g_breakouts_INT, 0);
   }

   // Detect Internal breakouts FIXED: Added missing call for Internal structure
   if(EnableInternalStructure && Internal_ShowBreakoutLines && ArraySize(g_structure_INT.points) > 0)
   {
      MqlRates rates_INT[];
      int copiedINT = CopyRates(_Symbol, Internal_TF, 0, MaxZigZagPoints_Internal * 5, rates_INT);
      if(copiedINT > 0)
      {
         double high_INT[], low_INT[], close_INT[];
         datetime time_INT[];
         ArrayResize(high_INT, copiedINT);
         ArrayResize(low_INT, copiedINT);
         ArrayResize(close_INT, copiedINT);
         ArrayResize(time_INT, copiedINT);
         for(int i = 0; i < copiedINT; i++)
         {
            high_INT[i] = rates_INT[i].high;
            low_INT[i] = rates_INT[i].low;
            close_INT[i] = rates_INT[i].close;
            time_INT[i] = rates_INT[i].time;
         }
         ArraySetAsSeries(high_INT, true);
         ArraySetAsSeries(low_INT, true);
         ArraySetAsSeries(close_INT, true);
         ArraySetAsSeries(time_INT, true);
         DetectBreakouts(time_INT, high_INT, low_INT, close_INT, g_structure_INT, g_breakouts_INT, Internal_MaxScanBars, Internal_AllowWickBreaks);
      }
   }
   else
   {
      ArrayResize(g_breakouts_INT, 0);
   }

   // Draw
   DrawMarketElements();

   return rates_total;
}
//+------------------------------------------------------------------+
//| End of file                                                      |
//+------------------------------------------------------------------+
