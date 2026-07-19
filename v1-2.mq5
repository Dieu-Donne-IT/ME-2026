//+------------------------------------------------------------------+
//| SMC ZigZag Structure Logic - Multi-Timeframe Version (All removed)|
//| Modified: removed ALL BOS/CHoCH logic, parameters and confirmation |
//|           rules. Only ZigZag structure labelling (H/L/HH/LL/HL/LH)|
//+------------------------------------------------------------------+
#property copyright "ITRAD SOCIETY"
#property link      "https://www.itrad.com"
#property version   "1.5"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   0

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
    int          trend;
};

struct SBreakEvent
{
    datetime timeStart;
    datetime timeBreak;
    double   level;
    bool     isBullish;
    bool     isCHoCH;
};

input group "═══ PARAMÈTRES ZIGZAG HTF ═══"
input int InpDepthHTF        = 34;
input int InpDeviationHTF    = 5;
input int InpBackstepHTF     = 3;
input int InpFontSizeHTF     = 12;
input int InpObjectWidthHTF  = 5;

input group "═══ TIMEFRAMES ═══"
input ENUM_TIMEFRAMES InpHTF = PERIOD_CURRENT; // Info seulement (calcul HTF = chart courant)

input ENUM_ANCHOR_POINT HTF_Anchor_High = ANCHOR_RIGHT_LOWER;
input ENUM_ANCHOR_POINT HTF_Anchor_Low  = ANCHOR_RIGHT_UPPER;

input group "═══ Structure Settings ═══"
input bool           ShowStructure      = true;
input bool           ShowHighLowLabels  = true;
input bool           ShowHLHHLHLLLabels = true;
input int            MaxZigZagPoints    = 100;

input group "═══ Visual Settings ═══"
input color          Default_Struct_Color   = clrDodgerBlue;
input int            Default_Font_Size      = 10;
input string         Default_Font           = "Courier New";

input group "═══ MULTI-TIMEFRAME SMC ═══"
input bool   EnableMultiTF = false;
input ENUM_TIMEFRAMES LTF_TF = PERIOD_CURRENT;
input bool   ShowLTF = true;
input color  LTF_Color      = clrBlack;
input int    LTF_FontSize   = 11;
input string LTF_Font       = "Courier New";
input ENUM_ANCHOR_POINT LTF_Anchor_High = ANCHOR_LEFT_LOWER;
input ENUM_ANCHOR_POINT LTF_Anchor_Low  = ANCHOR_LEFT_UPPER;

input group "═══ PARAMÈTRES ZIGZAG LTF ═══"
input int InpDepthLTF        = 17;
input int InpDeviationLTF    = 5;
input int InpBackstepLTF     = 3;

double ZigZagHigh_HTF[], ZigZagLow_HTF[];
double ZigZagHigh_LTF[], ZigZagLow_LTF[];
SMarketStructure g_structure_HTF;
SMarketStructure g_structure_LTF;
SBreakEvent g_breaks_HTF[];
SBreakEvent g_breaks_LTF[];

int g_minRatesTotal_HTF;
double g_deviation_HTF;
int g_depth_HTF, g_deviation_int_HTF, g_backstep_HTF;
int g_fontsize, g_objwidth;
const double LEVEL_TOLERANCE_RATIO = 0.0005;
const double LEVEL_TOLERANCE_MIN_POINTS = 5.0;
const double LABEL_OFFSET_RATIO = 0.0002;
const double LABEL_OFFSET_MIN_POINTS = 15.0;
const double MARKER_HALF_RATIO = 0.0001;
const double MARKER_HALF_MIN_POINTS = 8.0;

int FindFirstLabelSourceIndex(const SMarketStructure &structure, const string label)
{
    int n = ArraySize(structure.labels);
    for(int i = 0; i < n; i++)
        if(structure.labels[i] == label)
            return i;
    return -1;
}

datetime FindLevelTime(const SMarketStructure &structure, double level, bool isHigh)
{
    int n = ArraySize(structure.points);
    if(n == 0)
        return 0;

    double adaptiveTolerance = MathMax(MathAbs(level) * LEVEL_TOLERANCE_RATIO, _Point * LEVEL_TOLERANCE_MIN_POINTS);
    int bestIndex = -1;
    double bestDiff = DBL_MAX;

    for(int i = 0; i < n; i++)
    {
        if(structure.points[i].isHigh != isHigh)
            continue;

        double diff = MathAbs(structure.points[i].price - level);
        if(diff <= adaptiveTolerance && diff < bestDiff)
        {
            bestDiff = diff;
            bestIndex = i;
        }
    }

    if(bestIndex == -1)
        return 0;
    return structure.points[bestIndex].time;
}

void AddBreakEvent(SBreakEvent &events[], datetime timeStart, datetime timeBreak, double level, bool isBullish, bool isCHoCH)
{
    int size = ArraySize(events);
    ArrayResize(events, size + 1);
    events[size].timeStart = timeStart;
    events[size].timeBreak = timeBreak;
    events[size].level = level;
    events[size].isBullish = isBullish;
    events[size].isCHoCH = isCHoCH;
}

datetime ResolveSourceTime(const SMarketStructure &structure, int sourceIndex, bool isHigh)
{
    if(sourceIndex < 0 || sourceIndex >= ArraySize(structure.points))
        return 0;

    datetime startTime = structure.points[sourceIndex].time;
    if(startTime == 0)
        startTime = FindLevelTime(structure, structure.points[sourceIndex].price, isHigh);
    return startTime;
}

bool FindBreakCandleIndex(const double &close[], int rates_total, int sourceBarIndex, double level, bool breakUp, int &breakIndex)
{
    breakIndex = -1;
    if(sourceBarIndex <= 1 || sourceBarIndex >= rates_total)
        return false;

    for(int i = sourceBarIndex - 1; i >= 1; i--)
    {
        bool crossed = breakUp
                       ? (close[i] > level && close[i + 1] <= level)
                       : (close[i] < level && close[i + 1] >= level);

        if(crossed)
        {
            breakIndex = i;
            return true;
        }
    }
    return false;
}

void DetectBreaks(const SMarketStructure &structure, const datetime &time[], const double &close[], int rates_total, SBreakEvent &events[])
{
    ArrayResize(events, 0);

    if(ArraySize(structure.points) == 0 || ArraySize(structure.labels) == 0 || rates_total < 3)
        return;

    int idxHH = FindFirstLabelSourceIndex(structure, "HH");
    int idxLL = FindFirstLabelSourceIndex(structure, "LL");
    int idxHL = FindFirstLabelSourceIndex(structure, "HL");
    int idxLH = FindFirstLabelSourceIndex(structure, "LH");

    int breakIndex = -1;
    datetime startTime = 0;

    if(idxHH != -1 && FindBreakCandleIndex(close, rates_total, structure.points[idxHH].index, structure.points[idxHH].price, true, breakIndex))
    {
        startTime = ResolveSourceTime(structure, idxHH, true);
        AddBreakEvent(events, startTime, time[breakIndex], structure.points[idxHH].price, true, false);
    }

    if(idxLL != -1 && FindBreakCandleIndex(close, rates_total, structure.points[idxLL].index, structure.points[idxLL].price, false, breakIndex))
    {
        startTime = ResolveSourceTime(structure, idxLL, false);
        AddBreakEvent(events, startTime, time[breakIndex], structure.points[idxLL].price, false, false);
    }

    if(idxHL != -1 && FindBreakCandleIndex(close, rates_total, structure.points[idxHL].index, structure.points[idxHL].price, false, breakIndex))
    {
        startTime = ResolveSourceTime(structure, idxHL, false);
        AddBreakEvent(events, startTime, time[breakIndex], structure.points[idxHL].price, false, true);
    }

    if(idxLH != -1 && FindBreakCandleIndex(close, rates_total, structure.points[idxLH].index, structure.points[idxLH].price, true, breakIndex))
    {
        startTime = ResolveSourceTime(structure, idxLH, true);
        AddBreakEvent(events, startTime, time[breakIndex], structure.points[idxLH].price, true, true);
    }
}

void DrawBreakEvents(const string prefix, const SBreakEvent &events[])
{
    int count = ArraySize(events);
    for(int i = 0; i < count; i++)
    {
        if(events[i].timeStart == 0 || events[i].timeBreak == 0 || events[i].timeStart >= events[i].timeBreak)
            continue;

        color eventColor = events[i].isCHoCH
                           ? (events[i].isBullish ? clrLimeGreen : clrOrangeRed)
                           : (events[i].isBullish ? clrDodgerBlue : clrTomato);

        int lineStyle = events[i].isCHoCH ? STYLE_SOLID : STYLE_DOT;
        int lineWidth = events[i].isCHoCH ? 2 : 1;

        string lineName = prefix + "_LINE_" + IntegerToString(i);
        if(ObjectCreate(0, lineName, OBJ_TREND, 0, events[i].timeStart, events[i].level, events[i].timeBreak, events[i].level))
        {
            ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, lineName, OBJPROP_RAY_LEFT, false);
            ObjectSetInteger(0, lineName, OBJPROP_STYLE, lineStyle);
            ObjectSetInteger(0, lineName, OBJPROP_WIDTH, lineWidth);
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, eventColor);
        }

        double labelOffset = MathMax(MathAbs(events[i].level) * LABEL_OFFSET_RATIO, _Point * LABEL_OFFSET_MIN_POINTS);
        double labelPrice = events[i].isBullish ? (events[i].level + labelOffset) : (events[i].level - labelOffset);
        string labelText = events[i].isCHoCH ? "CHoCH" : "BOS";

        string labelName = prefix + "_TEXT_" + IntegerToString(i);
        if(ObjectCreate(0, labelName, OBJ_TEXT, 0, events[i].timeBreak, labelPrice))
        {
            ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
            ObjectSetInteger(0, labelName, OBJPROP_COLOR, eventColor);
            ObjectSetString(0, labelName, OBJPROP_FONT, Default_Font);
            ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, Default_Font_Size);
            ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, events[i].isBullish ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
        }

        double markerHalf = MathMax(MathAbs(events[i].level) * MARKER_HALF_RATIO, _Point * MARKER_HALF_MIN_POINTS);
        string markerName = prefix + "_MARK_" + IntegerToString(i);
        if(ObjectCreate(0, markerName, OBJ_TREND, 0, events[i].timeBreak, events[i].level - markerHalf, events[i].timeBreak, events[i].level + markerHalf))
        {
            ObjectSetInteger(0, markerName, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, markerName, OBJPROP_RAY_LEFT, false);
            ObjectSetInteger(0, markerName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, markerName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, markerName, OBJPROP_COLOR, eventColor);
        }
    }
}

string GetTimeFrameName(ENUM_TIMEFRAMES timeframe)
{
    if(timeframe == PERIOD_CURRENT)
        return EnumToString(Period());
    return EnumToString(timeframe);
}

int OnInit()
{
    g_depth_HTF         = InpDepthHTF;
    g_deviation_int_HTF = InpDeviationHTF;
    g_backstep_HTF      = InpBackstepHTF;
    g_fontsize          = InpFontSizeHTF;
    g_objwidth          = InpObjectWidthHTF;

    g_minRatesTotal_HTF = g_depth_HTF + g_backstep_HTF;
    g_deviation_HTF     = g_deviation_int_HTF * _Point;

    SetIndexBuffer(0, ZigZagHigh_HTF, INDICATOR_DATA);
    SetIndexBuffer(1, ZigZagLow_HTF, INDICATOR_DATA);
    SetIndexBuffer(2, ZigZagHigh_LTF, INDICATOR_DATA);
    SetIndexBuffer(3, ZigZagLow_LTF, INDICATOR_DATA);

    ArraySetAsSeries(ZigZagHigh_HTF, true);
    ArraySetAsSeries(ZigZagLow_HTF, true);
    ArraySetAsSeries(ZigZagHigh_LTF, true);
    ArraySetAsSeries(ZigZagLow_LTF, true);

    IndicatorSetString(INDICATOR_SHORTNAME, "SMC STRUCTURE MARKET MTF");
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    DeleteIndicatorObjects();
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if(rates_total < g_minRatesTotal_HTF)
        return 0;

    ArraySetAsSeries(time, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);

    if(prev_calculated == 0)
    {
        ArrayInitialize(ZigZagHigh_HTF, EMPTY_VALUE);
        ArrayInitialize(ZigZagLow_HTF, EMPTY_VALUE);
        ArrayInitialize(ZigZagHigh_LTF, EMPTY_VALUE);
        ArrayInitialize(ZigZagLow_LTF, EMPTY_VALUE);
    }

    // HTF (chart courant) avec paramètres HTF
    CalculateZigZagWithParams(high, low, rates_total, ZigZagHigh_HTF, ZigZagLow_HTF,
                              g_depth_HTF, g_deviation_HTF, g_backstep_HTF);
    UpdateMarketStructure(time, high, low, close, rates_total, g_structure_HTF, ZigZagHigh_HTF, ZigZagLow_HTF);
    DetectBreaks(g_structure_HTF, time, close, rates_total, g_breaks_HTF);

    // LTF (TF séparé) avec paramètres LTF
    if(EnableMultiTF)
    {
        MqlRates rates_LTF[];
        int copied = CopyRates(_Symbol, LTF_TF, 0, MaxZigZagPoints * 5, rates_LTF);
        if(copied > 0)
        {
            double high_LTF[], low_LTF[], close_LTF[];
            datetime time_LTF[];
            ArrayResize(high_LTF, copied);
            ArrayResize(low_LTF, copied);
            ArrayResize(close_LTF, copied);
            ArrayResize(time_LTF, copied);

            for(int i=0; i<copied; i++)
            {
                high_LTF[i] = rates_LTF[i].high;
                low_LTF[i]  = rates_LTF[i].low;
                close_LTF[i]= rates_LTF[i].close;
                time_LTF[i] = rates_LTF[i].time;
            }

            ArraySetAsSeries(high_LTF, true);
            ArraySetAsSeries(low_LTF, true);
            ArraySetAsSeries(close_LTF, true);
            ArraySetAsSeries(time_LTF, true);

            int minRatesLTF = InpDepthLTF + InpBackstepLTF;
            if(copied >= minRatesLTF)
            {
                double deviationLTF = InpDeviationLTF * _Point;
                CalculateZigZagWithParams(high_LTF, low_LTF, copied, ZigZagHigh_LTF, ZigZagLow_LTF,
                                          InpDepthLTF, deviationLTF, InpBackstepLTF);
                UpdateMarketStructure(time_LTF, high_LTF, low_LTF, close_LTF, copied,
                                      g_structure_LTF, ZigZagHigh_LTF, ZigZagLow_LTF);
                DetectBreaks(g_structure_LTF, time_LTF, close_LTF, copied, g_breaks_LTF);
            }
            else
            {
                ArrayInitialize(ZigZagHigh_LTF, EMPTY_VALUE);
                ArrayInitialize(ZigZagLow_LTF, EMPTY_VALUE);
                ArrayResize(g_structure_LTF.points, 0);
                ArrayResize(g_structure_LTF.labels, 0);
                g_structure_LTF.trend = 0;
                ArrayResize(g_breaks_LTF, 0);
            }
        }
        else
        {
            ArrayInitialize(ZigZagHigh_LTF, EMPTY_VALUE);
            ArrayInitialize(ZigZagLow_LTF, EMPTY_VALUE);
            ArrayResize(g_structure_LTF.points, 0);
            ArrayResize(g_structure_LTF.labels, 0);
            g_structure_LTF.trend = 0;
            ArrayResize(g_breaks_LTF, 0);
        }
    }
    else
    {
        ArrayInitialize(ZigZagHigh_LTF, EMPTY_VALUE);
        ArrayInitialize(ZigZagLow_LTF, EMPTY_VALUE);
        ArrayResize(g_structure_LTF.points, 0);
        ArrayResize(g_structure_LTF.labels, 0);
        g_structure_LTF.trend = 0;
        ArrayResize(g_breaks_LTF, 0);
    }

    DrawMarketElements();
    return rates_total;
}

void CalculateZigZagWithParams(const double &high[], const double &low[], int rates_total,
                               double &outHigh[], double &outLow[],
                               int depth, double deviation, int backstep)
{
    double lastlow = 0, lasthigh = 0;
    int minRatesTotal = depth + backstep;
    int limit = rates_total - minRatesTotal;

    ArrayInitialize(outHigh, EMPTY_VALUE);
    ArrayInitialize(outLow, EMPTY_VALUE);

    if(limit < 0) return;

    double highMap[], lowMap[];
    ArrayResize(highMap, rates_total);
    ArrayResize(lowMap, rates_total);
    ArrayInitialize(highMap, EMPTY_VALUE);
    ArrayInitialize(lowMap, EMPTY_VALUE);

    for(int bar = limit; bar >= 0; bar--)
    {
        double val = low[ArrayMinimum(low, bar, depth)];
        if(val == lastlow) val = EMPTY_VALUE;
        else
        {
            lastlow = val;
            if(low[bar] - val > deviation) val = EMPTY_VALUE;
            else
            {
                for(int back = 1; back <= backstep; back++)
                {
                    int idx = bar + back;
                    if(idx < rates_total)
                    {
                        double res = lowMap[idx];
                        if(res != EMPTY_VALUE && res > val)
                            lowMap[idx] = EMPTY_VALUE;
                    }
                }
            }
        }
        if(low[bar] == val) lowMap[bar] = val;

        val = high[ArrayMaximum(high, bar, depth)];
        if(val == lasthigh) val = EMPTY_VALUE;
        else
        {
            lasthigh = val;
            if(val - high[bar] > deviation) val = EMPTY_VALUE;
            else
            {
                for(int back = 1; back <= backstep; back++)
                {
                    int idx = bar + back;
                    if(idx < rates_total)
                    {
                        double res = highMap[idx];
                        if(res != EMPTY_VALUE && res < val)
                            highMap[idx] = EMPTY_VALUE;
                    }
                }
            }
        }
        if(high[bar] == val) highMap[bar] = val;
    }

    BuildZigZagStructureWithParams(highMap, lowMap, rates_total, outHigh, outLow, minRatesTotal);
}

void BuildZigZagStructureWithParams(const double &highMap[], const double &lowMap[], int rates_total,
                                    double &outHigh[], double &outLow[], int minRatesTotal)
{
    int whatlookfor = 0;
    int lasthighpos = 0, lastlowpos = 0;
    double curlow = 0, curhigh = 0;
    int limit = rates_total - minRatesTotal;

    for(int bar = limit; bar >= 0; bar--)
    {
        switch(whatlookfor)
        {
            case 0:
                if(highMap[bar] != EMPTY_VALUE) { curhigh = highMap[bar]; lasthighpos = bar; outHigh[bar] = curhigh; whatlookfor = -1; }
                if(lowMap[bar]  != EMPTY_VALUE) { curlow  = lowMap[bar];  lastlowpos = bar;  outLow[bar]  = curlow;  whatlookfor = 1;  }
                break;
            case 1:
                if(lowMap[bar] != EMPTY_VALUE && lowMap[bar] < curlow) { outLow[lastlowpos] = EMPTY_VALUE; lastlowpos = bar; curlow = lowMap[bar]; outLow[bar] = curlow; }
                if(highMap[bar] != EMPTY_VALUE) { curhigh = highMap[bar]; lasthighpos = bar; outHigh[bar] = curhigh; whatlookfor = -1; }
                break;
            case -1:
                if(highMap[bar] != EMPTY_VALUE && highMap[bar] > curhigh) { outHigh[lasthighpos] = EMPTY_VALUE; lasthighpos = bar; curhigh = highMap[bar]; outHigh[bar] = curhigh; }
                if(lowMap[bar] != EMPTY_VALUE) { curlow = lowMap[bar]; lastlowpos = bar; outLow[bar] = curlow; whatlookfor = 1; }
                break;
        }
    }
}

void LabelZigZagStructure(SMarketStructure &structure, const datetime &time[], const double &close[])
{
    int n = ArraySize(structure.points);
    ArrayResize(structure.labels, n);

    for(int i=0; i<n; i++)
        structure.labels[i] = (structure.points[i].isHigh ? "H" : "L");

    if(n < 2) { structure.trend = 0; return; }

    int firstHigh = -1, firstLow = -1;
    for(int i=n-1; i>=0; i--)
    {
        if(structure.points[i].isHigh && firstHigh == -1) firstHigh = i;
        if(!structure.points[i].isHigh && firstLow == -1) firstLow = i;
        if(firstHigh != -1 && firstLow != -1) break;
    }
    if(firstHigh == -1 || firstLow == -1) { structure.trend = 0; return; }

    bool isBullish = (firstLow > firstHigh);
    structure.trend = isBullish ? 1 : -1;
    if(isBullish) LabelBullishStructure(structure);
    else LabelBearishStructure(structure);
}

void LabelBullishStructure(SMarketStructure &structure)
{
    int n = ArraySize(structure.points);
    if(n < 2) return;

    int firstHighIndex = -1, firstLowIndex = -1;
    for(int i = n-1; i >= 0; i--)
    {
        if(structure.points[i].isHigh && firstHighIndex == -1) { firstHighIndex = i; structure.labels[i] = "H"; }
        if(!structure.points[i].isHigh && firstLowIndex == -1) { firstLowIndex = i; structure.labels[i] = "L"; }
        if(firstHighIndex != -1 && firstLowIndex != -1) break;
    }
    if(firstHighIndex == -1 || firstLowIndex == -1) return;

    double lastHigh = structure.points[firstHighIndex].price;
    double lastLow  = structure.points[firstLowIndex].price;

    for(int i = firstHighIndex-1; i >= 0; i--)
        if(structure.points[i].isHigh) { structure.labels[i] = (structure.points[i].price > lastHigh) ? "HH" : "LH"; lastHigh = structure.points[i].price; }

    for(int i = firstLowIndex-1; i >= 0; i--)
        if(!structure.points[i].isHigh) { structure.labels[i] = (structure.points[i].price > lastLow) ? "HL" : "LL"; lastLow = structure.points[i].price; }
}

void LabelBearishStructure(SMarketStructure &structure)
{
    int n = ArraySize(structure.points);
    if(n < 2) return;

    int firstHighIndex = -1, firstLowIndex = -1;
    for(int i = n-1; i >= 0; i--)
    {
        if(structure.points[i].isHigh && firstHighIndex == -1) { firstHighIndex = i; structure.labels[i] = "H"; }
        if(!structure.points[i].isHigh && firstLowIndex == -1) { firstLowIndex = i; structure.labels[i] = "L"; }
        if(firstHighIndex != -1 && firstLowIndex != -1) break;
    }
    if(firstHighIndex == -1 || firstLowIndex == -1) return;

    double lastHigh = structure.points[firstHighIndex].price;
    double lastLow  = structure.points[firstLowIndex].price;

    for(int i = firstHighIndex-1; i >= 0; i--)
        if(structure.points[i].isHigh) { structure.labels[i] = (structure.points[i].price < lastHigh) ? "LH" : "HH"; lastHigh = structure.points[i].price; }

    for(int i = firstLowIndex-1; i >= 0; i--)
        if(!structure.points[i].isHigh) { structure.labels[i] = (structure.points[i].price < lastLow) ? "LL" : "HL"; lastLow = structure.points[i].price; }
}

void UpdateMarketStructure(const datetime &time[], const double &high[],
                           const double &low[], const double &close[], int rates_total,
                           SMarketStructure &structure,
                           const double &ZigZagHigh[], const double &ZigZagLow[])
{
    ArrayResize(structure.points, 0);
    ArrayResize(structure.labels, 0);
    structure.trend = 0;

    int count = 0;
    for(int i = 0; i < rates_total && count < MaxZigZagPoints; i++)
    {
        if(ZigZagHigh[i] != EMPTY_VALUE)
        {
            SZigZagPoint p; p.time = time[i]; p.price = ZigZagHigh[i]; p.index = i; p.isHigh = true;
            int size = ArraySize(structure.points); ArrayResize(structure.points, size + 1); structure.points[size] = p; count++;
        }
        if(ZigZagLow[i] != EMPTY_VALUE)
        {
            SZigZagPoint p; p.time = time[i]; p.price = ZigZagLow[i]; p.index = i; p.isHigh = false;
            int size = ArraySize(structure.points); ArrayResize(structure.points, size + 1); structure.points[size] = p; count++;
        }
    }
    LabelZigZagStructure(structure, time, close);
}

void DeleteIndicatorObjects()
{
    string prefix = "SMC_";
    int total = ObjectsTotal(0, 0, -1);
    for(int i=total-1; i>=0; i--)
    {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, prefix) == 0)
            ObjectDelete(0, name);
    }
}

void DrawMarketElements()
{
    DeleteIndicatorObjects();
    string prefix = "SMC_";

    if(ShowStructure && ArraySize(g_structure_HTF.points) > 0)
    {
        for(int i = 0; i < MathMin(ArraySize(g_structure_HTF.points), MaxZigZagPoints); i++)
        {
            string label = g_structure_HTF.labels[i];
            if(label == "") continue;

            bool showThisLabel = false;
            if(ShowHighLowLabels && (label == "H" || label == "L")) showThisLabel = true;
            if(ShowHLHHLHLLLabels && (label == "HL" || label == "HH" || label == "LH" || label == "LL")) showThisLabel = true;

            if(showThisLabel)
            {
                string name = prefix + "HTF_ZZ_" + IntegerToString(i);
                if(ObjectCreate(0, name, OBJ_TEXT, 0, g_structure_HTF.points[i].time, g_structure_HTF.points[i].price))
                {
                    ObjectSetString(0, name, OBJPROP_TEXT, label);
                    ObjectSetString(0, name, OBJPROP_FONT, Default_Font);
                    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, Default_Font_Size);
                    ObjectSetInteger(0, name, OBJPROP_COLOR, g_structure_HTF.points[i].isHigh ? clrBlue : clrRed);
                    ObjectSetInteger(0, name, OBJPROP_ANCHOR, g_structure_HTF.points[i].isHigh ? HTF_Anchor_High : HTF_Anchor_Low);
                }
            }
        }
    }

    if(EnableMultiTF && ShowLTF && ArraySize(g_structure_LTF.points) > 0)
    {
        for(int i = 0; i < MathMin(ArraySize(g_structure_LTF.points), MaxZigZagPoints); i++)
        {
            string label = g_structure_LTF.labels[i];
            if(label == "") continue;

            bool showThisLabel = false;
            if(ShowHighLowLabels && (label == "H" || label == "L")) showThisLabel = true;
            if(ShowHLHHLHLLLabels && (label == "HL" || label == "HH" || label == "LH" || label == "LL")) showThisLabel = true;

            if(showThisLabel)
            {
                string name = prefix + "LTF_ZZ_" + IntegerToString(i);
                if(ObjectCreate(0, name, OBJ_TEXT, 0, g_structure_LTF.points[i].time, g_structure_LTF.points[i].price))
                {
                    ObjectSetString(0, name, OBJPROP_TEXT, label);
                    ObjectSetString(0, name, OBJPROP_FONT, LTF_Font);
                    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, LTF_FontSize);
                    ObjectSetInteger(0, name, OBJPROP_COLOR, LTF_Color);
                    ObjectSetInteger(0, name, OBJPROP_ANCHOR, g_structure_LTF.points[i].isHigh ? LTF_Anchor_High : LTF_Anchor_Low);
                }
            }
        }
    }

    if(ArraySize(g_breaks_HTF) > 0)
        DrawBreakEvents(prefix + "HTF_BREAK", g_breaks_HTF);

    if(EnableMultiTF && ShowLTF && ArraySize(g_breaks_LTF) > 0)
        DrawBreakEvents(prefix + "LTF_BREAK", g_breaks_LTF);

    string trendHTF = "Neutre";
    if(g_structure_HTF.trend == 1) trendHTF = "Bullish";
    else if(g_structure_HTF.trend == -1) trendHTF = "Bearish";

    string trendObjNameHTF = prefix + "Trend_HTF";
    if(ObjectCreate(0, trendObjNameHTF, OBJ_LABEL, 0, 0, 0))
    {
        ObjectSetString(0, trendObjNameHTF, OBJPROP_TEXT, "Structure HTF: " + trendHTF);
        ObjectSetInteger(0, trendObjNameHTF, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, trendObjNameHTF, OBJPROP_FONTSIZE, g_fontsize + 2);
        ObjectSetInteger(0, trendObjNameHTF, OBJPROP_COLOR, g_structure_HTF.trend == 1 ? clrGreen : (g_structure_HTF.trend == -1 ? clrRed : clrDarkOrange));
        ObjectSetInteger(0, trendObjNameHTF, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, trendObjNameHTF, OBJPROP_YDISTANCE, 10);
    }

    if(EnableMultiTF)
    {
        string trendLTF = "Neutre";
        if(g_structure_LTF.trend == 1) trendLTF = "Bullish";
        else if(g_structure_LTF.trend == -1) trendLTF = "Bearish";

        string trendObjNameLTF = prefix + "Trend_LTF";
        if(ObjectCreate(0, trendObjNameLTF, OBJ_LABEL, 0, 0, 0))
        {
            ObjectSetString(0, trendObjNameLTF, OBJPROP_TEXT, "Structure LTF: " + trendLTF);
            ObjectSetInteger(0, trendObjNameLTF, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, trendObjNameLTF, OBJPROP_FONTSIZE, g_fontsize + 1);
            ObjectSetInteger(0, trendObjNameLTF, OBJPROP_COLOR, g_structure_LTF.trend == 1 ? clrGreen : (g_structure_LTF.trend == -1 ? clrRed : clrDarkOrange));
            ObjectSetInteger(0, trendObjNameLTF, OBJPROP_XDISTANCE, 10);
            ObjectSetInteger(0, trendObjNameLTF, OBJPROP_YDISTANCE, 40);
        }
    }

    string tfInfo = prefix + "TF_Info";
    if(ObjectCreate(0, tfInfo, OBJ_LABEL, 0, 0, 0))
    {
        string htfName = GetTimeFrameName(InpHTF);
        string ltfName = EnableMultiTF ? GetTimeFrameName(LTF_TF) : "Désactivé";
        ObjectSetString(0, tfInfo, OBJPROP_TEXT, "HTF: " + htfName + " | LTF: " + ltfName);
        ObjectSetInteger(0, tfInfo, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, tfInfo, OBJPROP_FONTSIZE, g_fontsize);
        ObjectSetInteger(0, tfInfo, OBJPROP_COLOR, clrDarkSlateGray);
        ObjectSetInteger(0, tfInfo, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, tfInfo, OBJPROP_YDISTANCE, 70);
    }
}
