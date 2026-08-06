//+------------------------------------------------------------------+
//|                                                    SolidCore.mq5 |
//|                                                      SOLID-CORE  |
//|                     5銘柄対応・固定8pipsナンピンEA                |
//+------------------------------------------------------------------+
#property copyright "SOLID-CORE"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

#define MAX_SYMBOLS 5
#define FIXED_NANPIN_PIPS 8.0

CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| 入力パラメーター                                                  |
//+------------------------------------------------------------------+
input group "===== 取引銘柄1 ====="
input bool   銘柄1稼働     = true;       // 銘柄1 ON/OFF
input string 銘柄1名称     = "EURUSD";  // 基本銘柄名(サフィックス自動検出)
input double 銘柄1初期ロット = 0.10;

input group "===== 取引銘柄2 ====="
input bool   銘柄2稼働     = true;
input string 銘柄2名称     = "EURJPY";
input double 銘柄2初期ロット = 0.10;

input group "===== 取引銘柄3 ====="
input bool   銘柄3稼働     = true;
input string 銘柄3名称     = "GBPUSD";
input double 銘柄3初期ロット = 0.10;

input group "===== 取引銘柄4 ====="
input bool   銘柄4稼働     = true;
input string 銘柄4名称     = "USDCAD";
input double 銘柄4初期ロット = 0.10;

input group "===== 取引銘柄5 ====="
input bool   銘柄5稼働     = true;
input string 銘柄5名称     = "AUDUSD";
input double 銘柄5初期ロット = 0.10;

enum ENUM_TRADE_DIRECTION
{
   両方向       = 0,
   ロングのみ   = 1,
   ショートのみ = 2
};

input group "===== 基本設定 ====="
input ENUM_TRADE_DIRECTION 売買方向 = 両方向;
input long   ロングマジック番号  = 20260101;  // 既存LONG引継ぎ用(変更しない)
input long   ショートマジック番号 = 20260102;  // 既存SHORT引継ぎ用(変更しない)
input string EAコメント          = "SOLID-CORE";
input int    許容スリッページ     = 30;

input group "===== RSI設定 ====="
input ENUM_TIMEFRAMES RSI時間足 = PERIOD_M5;
input int    RSI期間          = 14;
input double 買いRSI上限      = 35.0;
input double 買いRSI下限      = 20.0;
input double 売りRSI上限      = 80.0;
input double 売りRSI下限      = 65.0;

input group "===== ナンピン設定 ====="
// ナンピン間隔はFIXED_NANPIN_PIPSで8pips固定
input int    最大保有ポジション数 = 30; // 1方向・1銘柄あたり
input int    追加待機時間_分       = 60;
input bool   見送り加算機能        = true;
input int    最大見送り加算回数    = 2;

input group "===== ロット設定 ====="
input double ロット倍率 = 1.5;
input double ロット刻み = 0.01;

input group "===== TP設定(加重平均からのpips) ====="
input double TP_1段目から2段目 = 15.0;
input double TP_3段目以降       = 18.0;

input group "===== トレール設定 ====="
input bool   トレーリング機能       = true;
input int    浅段境界               = 3;
input int    中段境界               = 6;
input int    深段境界               = 10;
input double 浅段トレール発動pips    = 6.0;
input double 浅段トレール幅pips      = 4.0;
input double 浅段最低確保pips        = 3.0;
input double 中段トレール発動pips    = 5.0;
input double 中段トレール幅pips      = 3.0;
input double 中段最低確保pips        = 2.0;
input double 深段トレール発動pips    = 4.0;
input double 深段トレール幅pips      = 2.0;
input double 深段最低確保pips        = 2.0;
input double 最深段トレール発動pips  = 3.0;
input double 最深段トレール幅pips    = 1.0;
input double 最深段最低確保pips      = 2.0;

input group "===== 合計損益チェック(決済時) ====="
input bool   決済時利益チェック = true;
input double 最低合計利益_円    = 0;

input group "===== 含み損損切り ====="
input bool   含み損損切り機能 = false;
input double 最大含み損_円    = 100000;

input group "===== 曜日フィルター ====="
input bool 月曜日稼働 = true;
input bool 火曜日稼働 = true;
input bool 水曜日稼働 = true;
input bool 木曜日稼働 = true;
input bool 金曜日稼働 = true;
input bool 土曜日稼働 = false;
input bool 日曜日稼働 = false;

input group "===== 時間フィルター(日本時間) ====="
input bool 時間フィルター使用 = true;
input int  取引開始時刻_時    = 9;
input int  取引開始時刻_分    = 0;
input int  取引終了時刻_時    = 16;
input int  取引終了時刻_分    = 0;
input bool 時間外ナンピン許可 = true;

// 内部ロジック互換用エイリアス。MT5のパラメーター画面には日本語名を表示する。
#define Symbol1Enabled 銘柄1稼働
#define Symbol1Name 銘柄1名称
#define Symbol1Lot 銘柄1初期ロット
#define Symbol2Enabled 銘柄2稼働
#define Symbol2Name 銘柄2名称
#define Symbol2Lot 銘柄2初期ロット
#define Symbol3Enabled 銘柄3稼働
#define Symbol3Name 銘柄3名称
#define Symbol3Lot 銘柄3初期ロット
#define Symbol4Enabled 銘柄4稼働
#define Symbol4Name 銘柄4名称
#define Symbol4Lot 銘柄4初期ロット
#define Symbol5Enabled 銘柄5稼働
#define Symbol5Name 銘柄5名称
#define Symbol5Lot 銘柄5初期ロット
#define DIR_BOTH 両方向
#define DIR_ONLY_LONG ロングのみ
#define DIR_ONLY_SHORT ショートのみ
#define TradeDirection 売買方向
#define MagicNumberLong ロングマジック番号
#define MagicNumberShort ショートマジック番号
#define EAComment EAコメント
#define SlippagePoints 許容スリッページ
#define RSI_Timeframe RSI時間足
#define RSI_Period RSI期間
#define RSI_BuyEntryUpper 買いRSI上限
#define RSI_BuyEntryLower 買いRSI下限
#define RSI_SellEntryUpper 売りRSI上限
#define RSI_SellEntryLower 売りRSI下限
#define MaxStages 最大保有ポジション数
#define EntryWaitMinutes 追加待機時間_分
#define UseSkipBonus 見送り加算機能
#define MaxSkipBonus 最大見送り加算回数
#define LotMultiplier ロット倍率
#define LotStep ロット刻み
#define TP_Stage1to2 TP_1段目から2段目
#define TP_Stage3Plus TP_3段目以降
#define UseTrailingStop トレーリング機能
#define TrailStage_Boundary1 浅段境界
#define TrailStage_Boundary2 中段境界
#define TrailStage_Boundary3 深段境界
#define Trail_Shallow_Trigger 浅段トレール発動pips
#define Trail_Shallow_Width 浅段トレール幅pips
#define Trail_Shallow_MinLock 浅段最低確保pips
#define Trail_Middle_Trigger 中段トレール発動pips
#define Trail_Middle_Width 中段トレール幅pips
#define Trail_Middle_MinLock 中段最低確保pips
#define Trail_Deep_Trigger 深段トレール発動pips
#define Trail_Deep_Width 深段トレール幅pips
#define Trail_Deep_MinLock 深段最低確保pips
#define Trail_Extreme_Trigger 最深段トレール発動pips
#define Trail_Extreme_Width 最深段トレール幅pips
#define Trail_Extreme_MinLock 最深段最低確保pips
#define UseProfitCheck 決済時利益チェック
#define MinTotalProfitJPY 最低合計利益_円
#define UseMaxLoss 含み損損切り機能
#define MaxLoss_JPY 最大含み損_円
#define UseTimeFilter 時間フィルター使用
#define TradeStartHour 取引開始時刻_時
#define TradeStartMin 取引開始時刻_分
#define TradeEndHour 取引終了時刻_時
#define TradeEndMin 取引終了時刻_分
#define NanpinOutsideHours 時間外ナンピン許可

#define AUTH_URL "https://script.google.com/macros/s/AKfycbx7acPhcHcCGbk5VABcbjgW39VAoPD5sohfsUD_zWXt3dVCQKv0bS43rYImjhT_S53DmA/exec"

//+------------------------------------------------------------------+
//| 銘柄別状態                                                        |
//+------------------------------------------------------------------+
bool     g_Enabled[MAX_SYMBOLS];
string   g_InputSymbol[MAX_SYMBOLS];
string   g_Symbol[MAX_SYMBOLS];
double   g_StartLot[MAX_SYMBOLS];
double   g_PipsToPrice[MAX_SYMBOLS];
int      g_Digits[MAX_SYMBOLS];
int      g_RSIHandle[MAX_SYMBOLS];
datetime g_LastLongEntry[MAX_SYMBOLS];
datetime g_LastShortEntry[MAX_SYMBOLS];
bool     g_TrailActiveLong[MAX_SYMBOLS];
bool     g_TrailActiveShort[MAX_SYMBOLS];
double   g_TrailHighLong[MAX_SYMBOLS];
double   g_TrailLowShort[MAX_SYMBOLS];
double   g_BasketStartLotLong[MAX_SYMBOLS];
double   g_BasketStartLotShort[MAX_SYMBOLS];
bool     g_AuthOK = false;
bool     g_Processing = false;
uint     g_LastProcessMs = 0;

//+------------------------------------------------------------------+
string UpperText(string value)
{
   StringToUpper(value);
   return value;
}

string SymbolBaseKey(string value)
{
   string upper = UpperText(value);
   string key = "";
   for(int i=0; i<StringLen(upper); i++)
   {
      ushort ch = StringGetCharacter(upper, i);
      if((ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9'))
         key += ShortToString(ch);
   }
   if(StringLen(key) >= 6)
      return StringSubstr(key, 0, 6);
   return key;
}

// 入力名をブローカーの実銘柄名へ変換。EURUSD→EURUSD.micro等に対応。
string ResolveBrokerSymbol(string requested)
{
   StringTrimLeft(requested);
   StringTrimRight(requested);
   if(requested == "") return "";

   if(SymbolSelect(requested, true))
      return requested;

   string requestedUpper = UpperText(requested);
   string base = SymbolBaseKey(requested);
   string best = "";
   int bestExtra = 100000;
   int total = SymbolsTotal(false);
   for(int i=0; i<total; i++)
   {
      string candidate = SymbolName(i, false);
      string candidateUpper = UpperText(candidate);
      if(candidateUpper == requestedUpper)
      {
         SymbolSelect(candidate, true);
         return candidate;
      }

      string candidateKey = SymbolBaseKey(candidate);
      if(base != "" && candidateKey == base && StringFind(candidateUpper, base) >= 0)
      {
         int extra = StringLen(candidate) - StringLen(base);
         if(extra < 0) extra = 0;
         if(best == "" || extra < bestExtra)
         {
            best = candidate;
            bestExtra = extra;
         }
      }
   }

   if(best != "")
   {
      SymbolSelect(best, true);
      return best;
   }
   return "";
}

double DetectPipsToPrice(string symbol)
{
   string base = SymbolBaseKey(symbol);
   if(base == "BTCUSD") return 1.0;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return point * ((digits == 5 || digits == 3) ? 10.0 : 1.0);
}

void LoadInputSymbols()
{
   g_Enabled[0]=Symbol1Enabled; g_InputSymbol[0]=Symbol1Name; g_StartLot[0]=Symbol1Lot;
   g_Enabled[1]=Symbol2Enabled; g_InputSymbol[1]=Symbol2Name; g_StartLot[1]=Symbol2Lot;
   g_Enabled[2]=Symbol3Enabled; g_InputSymbol[2]=Symbol3Name; g_StartLot[2]=Symbol3Lot;
   g_Enabled[3]=Symbol4Enabled; g_InputSymbol[3]=Symbol4Name; g_StartLot[3]=Symbol4Lot;
   g_Enabled[4]=Symbol5Enabled; g_InputSymbol[4]=Symbol5Name; g_StartLot[4]=Symbol5Lot;
}

long MagicForType(ENUM_POSITION_TYPE type)
{
   return (type == POSITION_TYPE_BUY) ? MagicNumberLong : MagicNumberShort;
}

//+------------------------------------------------------------------+
//| 認証                                                              |
//+------------------------------------------------------------------+
bool CheckAuthentication()
{
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
   {
      Print("バックテストモード: 認証スキップ");
      return true;
   }
   long account = AccountInfoInteger(ACCOUNT_LOGIN);
   string url = AUTH_URL + "?account=" + IntegerToString(account);
   char data[], result[];
   string resultHeaders;
   ResetLastError();
   int res = WebRequest("GET", url, "", "", 5000, data, 0, result, resultHeaders);
   if(res == -1)
   {
      int err = GetLastError();
      Print("認証通信失敗 エラー: ", err);
      if(err == 4014)
         Print("WebRequest許可URLに https://script.google.com を追加してください");
      return false;
   }
   string response = CharArrayToString(result);
   StringTrimLeft(response);
   StringTrimRight(response);
   if(response == "OK")
   {
      Print("認証成功 - 口座番号: ", account);
      return true;
   }
   Print("認証拒否 - 口座番号: ", account, " 応答:", response);
   return false;
}

//+------------------------------------------------------------------+
//| 時間・曜日                                                        |
//+------------------------------------------------------------------+
bool IsEuropeanSummerTime(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int year=dt.year, month=dt.mon, day=dt.day;
   if(month < 3 || month > 11) return false;
   if(month > 3 && month < 11) return true;

   MqlDateTime first;
   if(month == 3)
   {
      TimeToStruct(StringToTime(IntegerToString(year)+".03.01 00:00"), first);
      int secondSunday = ((7-first.day_of_week)%7+1)+7;
      return (day >= secondSunday);
   }
   TimeToStruct(StringToTime(IntegerToString(year)+".11.01 00:00"), first);
   int firstSunday = (7-first.day_of_week)%7+1;
   return (day < firstSunday);
}

datetime ServerToJST(datetime serverTime)
{
   int serverOffset = IsEuropeanSummerTime(serverTime) ? 3 : 2;
   return serverTime + (9-serverOffset)*3600;
}

bool IsTradeTimeAllowed()
{
   if(!UseTimeFilter) return true;
   MqlDateTime jst;
   TimeToStruct(ServerToJST(TimeCurrent()), jst);
   int currentMinutes=jst.hour*60+jst.min;
   int startMinutes=TradeStartHour*60+TradeStartMin;
   int endMinutes=TradeEndHour*60+TradeEndMin;
   if(endMinutes >= 1440) endMinutes=1440;
   if(startMinutes < endMinutes)
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   if(startMinutes > endMinutes)
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
   return true;
}

bool IsTradeDayAllowed()
{
   MqlDateTime jst;
   TimeToStruct(ServerToJST(TimeCurrent()), jst);
   switch(jst.day_of_week)
   {
      case 0: return 日曜日稼働;
      case 1: return 月曜日稼働;
      case 2: return 火曜日稼働;
      case 3: return 水曜日稼働;
      case 4: return 木曜日稼働;
      case 5: return 金曜日稼働;
      case 6: return 土曜日稼働;
   }
   return false;
}

//+------------------------------------------------------------------+
//| ポジション集計                                                    |
//+------------------------------------------------------------------+
int CountPositions(int index, ENUM_POSITION_TYPE type)
{
   int count=0;
   long magic=MagicForType(type);
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==g_Symbol[index] &&
         posInfo.Magic()==magic && posInfo.PositionType()==type)
         count++;
   return count;
}

double CalcWeightedAverage(int index, ENUM_POSITION_TYPE type)
{
   double value=0, lots=0;
   long magic=MagicForType(type);
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==g_Symbol[index] &&
         posInfo.Magic()==magic && posInfo.PositionType()==type)
      {
         value += posInfo.PriceOpen()*posInfo.Volume();
         lots  += posInfo.Volume();
      }
   return (lots > 0) ? value/lots : 0;
}

double CalcTotalLots(int index, ENUM_POSITION_TYPE type)
{
   double total=0;
   long magic=MagicForType(type);
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==g_Symbol[index] &&
         posInfo.Magic()==magic && posInfo.PositionType()==type)
         total += posInfo.Volume();
   return total;
}

double CalcTotalProfit(int index, ENUM_POSITION_TYPE type)
{
   double total=0;
   long magic=MagicForType(type);
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==g_Symbol[index] &&
         posInfo.Magic()==magic && posInfo.PositionType()==type)
         total += posInfo.Profit()+posInfo.Swap()+posInfo.Commission();
   return total;
}

double GetLastPositionPrice(int index, ENUM_POSITION_TYPE type)
{
   datetime latest=0;
   double price=0;
   long magic=MagicForType(type);
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==g_Symbol[index] &&
         posInfo.Magic()==magic && posInfo.PositionType()==type && posInfo.Time()>=latest)
      {
         latest=posInfo.Time();
         price=posInfo.PriceOpen();
      }
   return price;
}

datetime GetLastPositionTime(int index, ENUM_POSITION_TYPE type)
{
   datetime latest=0;
   long magic=MagicForType(type);
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==g_Symbol[index] &&
         posInfo.Magic()==magic && posInfo.PositionType()==type && posInfo.Time()>latest)
         latest=posInfo.Time();
   return latest;
}

//+------------------------------------------------------------------+
//| ロット                                                            |
//+------------------------------------------------------------------+
double NormalizeLot(int index, double lot)
{
   double minLot=SymbolInfoDouble(g_Symbol[index], SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(g_Symbol[index], SYMBOL_VOLUME_MAX);
   double brokerStep=SymbolInfoDouble(g_Symbol[index], SYMBOL_VOLUME_STEP);
   double step=(LotStep > 0) ? MathMax(LotStep, brokerStep) : brokerStep;
   if(step <= 0) step=0.01;
   lot=MathFloor((lot+1e-10)/step)*step;
   lot=MathMax(lot,minLot);
   lot=MathMin(lot,maxLot);
   int volumeDigits=2;
   if(step>=1.0) volumeDigits=0;
   else if(step>=0.1) volumeDigits=1;
   else if(step>=0.01) volumeDigits=2;
   else volumeDigits=3;
   return NormalizeDouble(lot,volumeDigits);
}

double RecoverBasketStartLot(int index, ENUM_POSITION_TYPE type)
{
   int stages=CountPositions(index,type);
   if(stages<=0) return 0;
   datetime latest=0;
   double latestLot=0;
   string latestComment="";
   long magic=MagicForType(type);
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==g_Symbol[index] &&
         posInfo.Magic()==magic && posInfo.PositionType()==type && posInfo.Time()>=latest)
      {
         latest=posInfo.Time();
         latestLot=posInfo.Volume();
         latestComment=posInfo.Comment();
      }
   if(latestLot<=0) return 0;

   // 見送り加算された最新ポジションなら加算倍率を取り除く。
   int skipPos=StringFind(latestComment,"_skip");
   if(skipPos>=0)
   {
      int skip=(int)StringToInteger(StringSubstr(latestComment,skipPos+5));
      if(skip>0) latestLot/=(1+skip);
   }
   double base=latestLot;
   if(LotMultiplier>0)
      for(int stage=1; stage<stages; stage++) base/=LotMultiplier;
   return NormalizeLot(index,base);
}

double GetLotForStage(int index, ENUM_POSITION_TYPE type, int stage)
{
   if(stage<=0 || g_StartLot[index]<=0) return 0;
   double basketBase=(type==POSITION_TYPE_BUY)
                     ? g_BasketStartLotLong[index]
                     : g_BasketStartLotShort[index];
   double lot=(basketBase>0) ? basketBase : g_StartLot[index];
   for(int i=1; i<stage; i++) lot*=LotMultiplier;
   return NormalizeLot(index,lot);
}

double GetTPForStage(int stage)
{
   return (stage<=2) ? TP_Stage1to2 : TP_Stage3Plus;
}

void GetTrailParams(int stage,double &trigger,double &width,double &minLock)
{
   if(stage<=TrailStage_Boundary1)
   { trigger=Trail_Shallow_Trigger; width=Trail_Shallow_Width; minLock=Trail_Shallow_MinLock; }
   else if(stage<=TrailStage_Boundary2)
   { trigger=Trail_Middle_Trigger; width=Trail_Middle_Width; minLock=Trail_Middle_MinLock; }
   else if(stage<=TrailStage_Boundary3)
   { trigger=Trail_Deep_Trigger; width=Trail_Deep_Width; minLock=Trail_Deep_MinLock; }
   else
   { trigger=Trail_Extreme_Trigger; width=Trail_Extreme_Width; minLock=Trail_Extreme_MinLock; }
}

//+------------------------------------------------------------------+
//| RSI・新規エントリー                                               |
//+------------------------------------------------------------------+
double GetRSI(int index)
{
   double rsi[];
   if(g_RSIHandle[index]==INVALID_HANDLE || CopyBuffer(g_RSIHandle[index],0,0,1,rsi)<=0)
      return -1;
   return rsi[0];
}

int GetEntrySignal(int index)
{
   double rsi=GetRSI(index);
   if(rsi<0) return 0;
   if(rsi>=RSI_BuyEntryLower && rsi<=RSI_BuyEntryUpper) return 1;
   if(rsi>=RSI_SellEntryLower && rsi<=RSI_SellEntryUpper) return -1;
   return 0;
}

bool OpenPosition(int index, ENUM_POSITION_TYPE type, int stage, int skipBonus=0)
{
   double lot=GetLotForStage(index,type,stage);
   if(skipBonus>0) lot=NormalizeLot(index,lot*(1+skipBonus));
   if(lot<=0) return false;

   trade.SetExpertMagicNumber(MagicForType(type));
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(g_Symbol[index]);
   string orderComment=EAComment+"_"+IntegerToString(stage);
   if(skipBonus>0) orderComment+="_skip"+IntegerToString(skipBonus);

   bool result=(type==POSITION_TYPE_BUY)
               ? trade.Buy(lot,g_Symbol[index],0,0,0,orderComment)
               : trade.Sell(lot,g_Symbol[index],0,0,0,orderComment);
   if(result)
   {
      datetime now=TimeCurrent();
      if(type==POSITION_TYPE_BUY)
      {
         if(stage==1) g_BasketStartLotLong[index]=g_StartLot[index];
         g_LastLongEntry[index]=now;
         g_TrailActiveLong[index]=false;
         g_TrailHighLong[index]=0;
      }
      else
      {
         if(stage==1) g_BasketStartLotShort[index]=g_StartLot[index];
         g_LastShortEntry[index]=now;
         g_TrailActiveShort[index]=false;
         g_TrailLowShort[index]=0;
      }
      Print(g_Symbol[index]," ",(type==POSITION_TYPE_BUY?"BUY ":"SELL "),stage,
            "段目 約定 Lot:",lot,(skipBonus>0?" 見送り加算あり":""));
   }
   else
      Print(g_Symbol[index]," 約定失敗: ",trade.ResultRetcodeDescription()," RetCode:",trade.ResultRetcode());
   return result;
}

void ProcessNewEntry(int index)
{
   int signal=GetEntrySignal(index);
   if(signal==1 && CountPositions(index,POSITION_TYPE_BUY)==0 &&
      (TradeDirection==DIR_BOTH || TradeDirection==DIR_ONLY_LONG))
      OpenPosition(index,POSITION_TYPE_BUY,1);
   else if(signal==-1 && CountPositions(index,POSITION_TYPE_SELL)==0 &&
           (TradeDirection==DIR_BOTH || TradeDirection==DIR_ONLY_SHORT))
      OpenPosition(index,POSITION_TYPE_SELL,1);
}

// 直前の実約定価格から、実際の新規約定側価格で固定8pipsを判定する。
void ProcessNanpin(int index, ENUM_POSITION_TYPE type, const MqlTick &tick)
{
   int stages=CountPositions(index,type);
   if(stages==0 || (MaxStages>0 && stages>=MaxStages)) return;
   if(type==POSITION_TYPE_BUY && TradeDirection==DIR_ONLY_SHORT) return;
   if(type==POSITION_TYPE_SELL && TradeDirection==DIR_ONLY_LONG) return;

   datetime lastEntry=(type==POSITION_TYPE_BUY)?g_LastLongEntry[index]:g_LastShortEntry[index];
   if(TimeCurrent()-lastEntry<EntryWaitMinutes*60) return;
   double lastPrice=GetLastPositionPrice(index,type);
   if(lastPrice<=0) return;

   // BUYはAskで買い、SELLはBidで売るため、同じ側の価格で間隔を測る。
   double entrySidePrice=(type==POSITION_TYPE_BUY)?tick.ask:tick.bid;
   double interval=FIXED_NANPIN_PIPS*g_PipsToPrice[index];
   bool trigger=(type==POSITION_TYPE_BUY)
                ? (entrySidePrice<=lastPrice-interval)
                : (entrySidePrice>=lastPrice+interval);
   if(!trigger) return;

   int skipBonus=0;
   if(UseSkipBonus && MaxSkipBonus>0)
   {
      double divergence=MathAbs(entrySidePrice-lastPrice)/g_PipsToPrice[index];
      int skipped=(int)MathFloor(divergence/FIXED_NANPIN_PIPS)-1;
      skipBonus=(int)MathMin(MathMax(skipped,0),MaxSkipBonus);
   }
   OpenPosition(index,type,stages+1,skipBonus);
}

//+------------------------------------------------------------------+
//| 決済管理                                                          |
//+------------------------------------------------------------------+
void CloseAllPositions(int index, ENUM_POSITION_TYPE type)
{
   long magic=MagicForType(type);
   trade.SetExpertMagicNumber(magic);
   trade.SetTypeFillingBySymbol(g_Symbol[index]);
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==g_Symbol[index] &&
         posInfo.Magic()==magic && posInfo.PositionType()==type)
      {
         ulong ticket=posInfo.Ticket();
         if(!trade.PositionClose(ticket))
            Print(g_Symbol[index]," 決済失敗 ticket:",ticket," ",trade.ResultRetcodeDescription());
      }

   if(type==POSITION_TYPE_BUY)
   {
      g_BasketStartLotLong[index]=0;
      g_TrailActiveLong[index]=false;
      g_TrailHighLong[index]=0;
      g_LastLongEntry[index]=0;
   }
   else
   {
      g_BasketStartLotShort[index]=0;
      g_TrailActiveShort[index]=false;
      g_TrailLowShort[index]=0;
      g_LastShortEntry[index]=0;
   }
}

void CheckTakeProfit(int index, ENUM_POSITION_TYPE type, const MqlTick &tick)
{
   int stages=CountPositions(index,type);
   if(stages==0) return;
   double avg=CalcWeightedAverage(index,type);
   double tpPips=GetTPForStage(stages);
   double price=(type==POSITION_TYPE_BUY)?tick.bid:tick.ask;
   double target=(type==POSITION_TYPE_BUY)
                 ? avg+tpPips*g_PipsToPrice[index]
                 : avg-tpPips*g_PipsToPrice[index];
   bool reached=(type==POSITION_TYPE_BUY)?price>=target:price<=target;
   if(!reached) return;
   double profit=CalcTotalProfit(index,type);
   if(UseProfitCheck && profit<MinTotalProfitJPY) return;
   Print(g_Symbol[index]," TP決済 ",(type==POSITION_TYPE_BUY?"BUY":"SELL"),
         " 段数:",stages," 加重平均:",avg," 利益:",profit);
   CloseAllPositions(index,type);
}

void ProcessTrailing(int index, ENUM_POSITION_TYPE type, const MqlTick &tick)
{
   int stages=CountPositions(index,type);
   if(stages==0) return;
   double avg=CalcWeightedAverage(index,type);
   double trigger,width,minLock;
   GetTrailParams(stages,trigger,width,minLock);
   double spread=(tick.ask-tick.bid)/g_PipsToPrice[index];
   minLock=MathMax(minLock,spread+0.5);
   double price=(type==POSITION_TYPE_BUY)?tick.bid:tick.ask;

   if(type==POSITION_TYPE_BUY)
   {
      double triggerPrice=avg+trigger*g_PipsToPrice[index];
      double minLockPrice=avg+minLock*g_PipsToPrice[index];
      if(!g_TrailActiveLong[index] && price>=triggerPrice)
      {
         g_TrailActiveLong[index]=true;
         g_TrailHighLong[index]=price;
      }
      if(g_TrailActiveLong[index])
      {
         if(price>g_TrailHighLong[index]) g_TrailHighLong[index]=price;
         double stop=MathMax(g_TrailHighLong[index]-width*g_PipsToPrice[index],minLockPrice);
         if(price<=stop && (!UseProfitCheck || CalcTotalProfit(index,type)>=MinTotalProfitJPY))
            CloseAllPositions(index,type);
      }
   }
   else
   {
      double triggerPrice=avg-trigger*g_PipsToPrice[index];
      double minLockPrice=avg-minLock*g_PipsToPrice[index];
      if(!g_TrailActiveShort[index] && price<=triggerPrice)
      {
         g_TrailActiveShort[index]=true;
         g_TrailLowShort[index]=price;
      }
      if(g_TrailActiveShort[index])
      {
         if(price<g_TrailLowShort[index]) g_TrailLowShort[index]=price;
         double stop=MathMin(g_TrailLowShort[index]+width*g_PipsToPrice[index],minLockPrice);
         if(price>=stop && (!UseProfitCheck || CalcTotalProfit(index,type)>=MinTotalProfitJPY))
            CloseAllPositions(index,type);
      }
   }
}

void CheckMaxLoss(int index)
{
   double profit=CalcTotalProfit(index,POSITION_TYPE_BUY)+CalcTotalProfit(index,POSITION_TYPE_SELL);
   if(profit<=-MaxLoss_JPY)
   {
      Print(g_Symbol[index]," 含み損損切り発動 合計損益:",profit);
      CloseAllPositions(index,POSITION_TYPE_BUY);
      CloseAllPositions(index,POSITION_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| 全銘柄処理                                                        |
//+------------------------------------------------------------------+
void ProcessAllSymbols()
{
   if(!g_AuthOK || g_Processing) return;
   uint nowMs=GetTickCount();
   if(nowMs-g_LastProcessMs<200) return;
   g_LastProcessMs=nowMs;
   g_Processing=true;

   bool entryTime=IsTradeTimeAllowed() && IsTradeDayAllowed();
   for(int i=0; i<MAX_SYMBOLS; i++)
   {
      if(!g_Enabled[i] || g_Symbol[i]=="") continue;
      MqlTick tick;
      if(!SymbolInfoTick(g_Symbol[i],tick) || tick.bid<=0 || tick.ask<=0) continue;

      if(UseMaxLoss) CheckMaxLoss(i);
      if(UseTrailingStop)
      {
         ProcessTrailing(i,POSITION_TYPE_BUY,tick);
         ProcessTrailing(i,POSITION_TYPE_SELL,tick);
      }
      CheckTakeProfit(i,POSITION_TYPE_BUY,tick);
      CheckTakeProfit(i,POSITION_TYPE_SELL,tick);

      if(NanpinOutsideHours || entryTime)
      {
         ProcessNanpin(i,POSITION_TYPE_BUY,tick);
         ProcessNanpin(i,POSITION_TYPE_SELL,tick);
      }
      if(entryTime) ProcessNewEntry(i);
   }
   g_Processing=false;
}

void UpdateChartComment()
{
   string text="SOLID-CORE v1.10  [固定ナンピン 8.0 pips / 最大 "+IntegerToString(MaxStages)+"段]\n";
   MqlDateTime jst;
   TimeToStruct(ServerToJST(TimeCurrent()),jst);
   text+="JST "+IntegerToString(jst.hour)+":"+(jst.min<10?"0":"")+IntegerToString(jst.min)+
         "  時間:"+(IsTradeTimeAllowed()?"許可":"停止")+" 曜日:"+(IsTradeDayAllowed()?"許可":"停止")+"\n\n";
   for(int i=0; i<MAX_SYMBOLS; i++)
   {
      if(!g_Enabled[i]) continue;
      if(g_Symbol[i]=="")
      {
         text+="[未検出] "+g_InputSymbol[i]+"\n";
         continue;
      }
      int buys=CountPositions(i,POSITION_TYPE_BUY);
      int sells=CountPositions(i,POSITION_TYPE_SELL);
      text+="["+g_Symbol[i]+"] Lot="+DoubleToString(g_StartLot[i],2)+
            "  BUY "+IntegerToString(buys)+" / SELL "+IntegerToString(sells)+"\n";
      if(buys>0)
      {
         double last=GetLastPositionPrice(i,POSITION_TYPE_BUY);
         text+="  BUY Avg="+DoubleToString(CalcWeightedAverage(i,POSITION_TYPE_BUY),g_Digits[i])+
               " Last="+DoubleToString(last,g_Digits[i])+
               " Next="+DoubleToString(last-FIXED_NANPIN_PIPS*g_PipsToPrice[i],g_Digits[i])+
               " PL="+DoubleToString(CalcTotalProfit(i,POSITION_TYPE_BUY),0)+"\n";
      }
      if(sells>0)
      {
         double last=GetLastPositionPrice(i,POSITION_TYPE_SELL);
         text+="  SELL Avg="+DoubleToString(CalcWeightedAverage(i,POSITION_TYPE_SELL),g_Digits[i])+
               " Last="+DoubleToString(last,g_Digits[i])+
               " Next="+DoubleToString(last+FIXED_NANPIN_PIPS*g_PipsToPrice[i],g_Digits[i])+
               " PL="+DoubleToString(CalcTotalProfit(i,POSITION_TYPE_SELL),0)+"\n";
      }
   }
   Comment(text);
}

//+------------------------------------------------------------------+
//| イベント                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   LoadInputSymbols();
   int active=0;
   for(int i=0; i<MAX_SYMBOLS; i++)
   {
      g_RSIHandle[i]=INVALID_HANDLE;
      if(!g_Enabled[i]) continue;
      g_Symbol[i]=ResolveBrokerSymbol(g_InputSymbol[i]);
      if(g_Symbol[i]=="")
      {
         Print("銘柄",i+1,"を検出できません: ",g_InputSymbol[i]);
         continue;
      }
      bool duplicate=false;
      for(int j=0; j<i; j++)
      {
         if(g_Enabled[j] && g_Symbol[j]!="" && g_Symbol[j]==g_Symbol[i])
         {
            duplicate=true;
            break;
         }
      }
      if(duplicate)
      {
         Print("銘柄",i+1,"は既に登録済みのため無効化: ",g_Symbol[i]);
         g_Enabled[i]=false;
         g_Symbol[i]="";
         continue;
      }
      g_Digits[i]=(int)SymbolInfoInteger(g_Symbol[i],SYMBOL_DIGITS);
      g_PipsToPrice[i]=DetectPipsToPrice(g_Symbol[i]);
      g_RSIHandle[i]=iRSI(g_Symbol[i],RSI_Timeframe,RSI_Period,PRICE_CLOSE);
      if(g_RSIHandle[i]==INVALID_HANDLE)
      {
         Print(g_Symbol[i]," RSIハンドル作成失敗");
         g_Symbol[i]="";
         continue;
      }
      // 現在保有中のポジションから待機時間を復元する。
      g_LastLongEntry[i]=GetLastPositionTime(i,POSITION_TYPE_BUY);
      g_LastShortEntry[i]=GetLastPositionTime(i,POSITION_TYPE_SELL);
      g_BasketStartLotLong[i]=RecoverBasketStartLot(i,POSITION_TYPE_BUY);
      g_BasketStartLotShort[i]=RecoverBasketStartLot(i,POSITION_TYPE_SELL);
      active++;
      Print("銘柄",i+1,": 入力=",g_InputSymbol[i]," / 検出=",g_Symbol[i],
            " / 初期Lot=",g_StartLot[i]," / PipsToPrice=",g_PipsToPrice[i],
            " / 引継BUY=",CountPositions(i,POSITION_TYPE_BUY),
            " (復元開始Lot=",g_BasketStartLotLong[i],")",
            " / 引継SELL=",CountPositions(i,POSITION_TYPE_SELL),
            " (復元開始Lot=",g_BasketStartLotShort[i],")");
   }
   if(active==0)
   {
      Alert("SOLID-CORE: 有効な取引銘柄がありません");
      return INIT_FAILED;
   }

   trade.SetDeviationInPoints(SlippagePoints);
   g_AuthOK=CheckAuthentication();
   if(!g_AuthOK)
   {
      Alert("SOLID-CORE: 認証に失敗しました");
      return INIT_FAILED;
   }
   EventSetTimer(1);
   Print("SOLID-CORE v1.10 起動 / 5銘柄対応 / 固定8pips / 最大",MaxStages,"段");
   UpdateChartComment();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i=0; i<MAX_SYMBOLS; i++)
      if(g_RSIHandle[i]!=INVALID_HANDLE) IndicatorRelease(g_RSIHandle[i]);
   Comment("");
   Print("SOLID-CORE v1.10 停止 (保有ポジションは維持)");
}

void OnTick()
{
   ProcessAllSymbols();
}

void OnTimer()
{
   ProcessAllSymbols();
   UpdateChartComment();
}
