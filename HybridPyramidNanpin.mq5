//+------------------------------------------------------------------+
//|                                      HybridPyramidNanpin.mq5     |
//|  RSI順張り + 減少ロット・ピラミッディング + 1.3倍ナンピン      |
//|  SolidCoreの見送り加算思想・ロット正規化を継承した独立EA        |
//+------------------------------------------------------------------+
#property copyright "FRONTIER LAB"
#property version   "1.01"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade trade;
CPositionInfo posInfo;

enum ENUM_売買方向 { 両方向=0, ロングのみ=1, ショートのみ=2 };
enum ENUM_MODE { MODE_FLAT=0, MODE_INITIAL=1, MODE_PYRAMID=2, MODE_NANPIN=3 };

input group "===== 01. ロット設定 ====="
input double 初期ロット=0.10;
input double 最大合計ロット=0.0;
input double ロット刻み=0.01;

input group "===== 02. 基本設定 ====="
input bool 新規エントリー許可=true;
input ENUM_売買方向 売買方向=両方向;
input long マジック番号=2026081401;
input string EAコメント="HYBRID-PN";
input int 許容スリッページ_ポイント=30;
input int 決済後再エントリー待機_分=5;
input double pip価格換算=0.0;
input double 新規最大スプレッド_pips=0.0;

input group "===== 03. RSIエントリー設定 ====="
input ENUM_TIMEFRAMES RSI時間足=PERIOD_M5;
input int RSI期間=14;
input double 買いエントリーRSI=55.0;
input double 売りエントリーRSI=45.0;
input double 買いRSI上限=70.0;
input double 売りRSI下限=30.0;

input group "===== 04. ピラミッディング設定 ====="
input bool ピラミッディング機能=true;
input double ピラミッディング間隔_pips=10.0;
input double ピラミッディングロット倍率=0.70;
input int 最大ピラミッディング回数=4;
input int ピラミッディング最短追加間隔_秒=30;
input bool 時間外ピラミッディング許可=true;
input bool トレール機能=true;
input double トレール幅_pips=15.0;
input double 初回ピラミッド損切り余裕_pips=2.0;
input int 建値保護開始ポジション数=3;
input double 建値保護利益_pips=1.0;
input bool サーバーSL併用=true;

input group "===== 05. ナンピン設定 ====="
input bool ナンピン機能=true;
input double ナンピン間隔_pips=40.0;
input double ナンピンロット倍率=1.30;
input int 最大ナンピン回数=5;
input int ナンピン最短追加間隔_秒=60;
input bool 時間外ナンピン許可=true;
input bool 見送り加算機能=true;
input int 最大見送り加算段数=3;
input double ナンピン決済幅_pips=10.0;
input double 最低合計利益_円=0.0;

input group "===== 06. 時間設定（日本時間） ====="
input bool 時間設定機能=true;
input int 取引開始時刻_時=9;
input int 取引開始時刻_分=0;
input int 取引終了時刻_時=16;
input int 取引終了時刻_分=0;
input int テスターサーバーUTC差=2;

input group "===== 07. 曜日設定 ====="
input bool 曜日設定機能=true;
input bool 月曜日稼働=true;
input bool 火曜日稼働=true;
input bool 水曜日稼働=true;
input bool 木曜日稼働=true;
input bool 金曜日稼働=true;
input bool 土曜日稼働=false;
input bool 日曜日稼働=false;

input group "===== 08. 含み損・リスク管理 ====="
input bool 含み損損切り機能=false;
input double 最大含み損_円=100000.0;
input double 円換算レート固定=0.0;
input double 口座通貨補正倍率=1.0;

string g_symbol="";
double g_pip=0.0;
int g_digits=0;
int g_rsiHandle=INVALID_HANDLE;
ENUM_MODE g_mode=MODE_FLAT;
ENUM_POSITION_TYPE g_direction=POSITION_TYPE_BUY;
double g_initialPrice=0.0;
double g_lastAddPrice=0.0;
int g_pyramidCount=0;
int g_nanpinLogicalCount=0;
double g_extremePrice=0.0;
double g_basketStop=0.0;
datetime g_lastActionTime=0;
datetime g_lastExitTime=0;
datetime g_lastSignalBar=0;
bool g_processing=false;

string StatePrefix()
{
   return "HYBPN_"+IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+g_symbol+"_"+IntegerToString((int)マジック番号)+"_";
}
void SaveState()
{
   string p=StatePrefix();
   GlobalVariableSet(p+"MODE",(double)g_mode); GlobalVariableSet(p+"DIR",(double)g_direction);
   GlobalVariableSet(p+"INIT",g_initialPrice); GlobalVariableSet(p+"LAST",g_lastAddPrice);
   GlobalVariableSet(p+"PYR",(double)g_pyramidCount); GlobalVariableSet(p+"NAN",(double)g_nanpinLogicalCount);
   GlobalVariableSet(p+"EXT",g_extremePrice); GlobalVariableSet(p+"STOP",g_basketStop);
   GlobalVariableSet(p+"ACT",(double)g_lastActionTime); GlobalVariableSet(p+"EXIT",(double)g_lastExitTime);
}
void ClearState()
{
   string p=StatePrefix(); string keys[]={"MODE","DIR","INIT","LAST","PYR","NAN","EXT","STOP","ACT"};
   for(int i=0;i<ArraySize(keys);i++) if(GlobalVariableCheck(p+keys[i])) GlobalVariableDel(p+keys[i]);
}
bool LoadState()
{
   string p=StatePrefix(); if(!GlobalVariableCheck(p+"MODE")) return false;
   g_mode=(ENUM_MODE)(int)GlobalVariableGet(p+"MODE");
   if(GlobalVariableCheck(p+"DIR")) g_direction=(ENUM_POSITION_TYPE)(int)GlobalVariableGet(p+"DIR");
   if(GlobalVariableCheck(p+"INIT")) g_initialPrice=GlobalVariableGet(p+"INIT");
   if(GlobalVariableCheck(p+"LAST")) g_lastAddPrice=GlobalVariableGet(p+"LAST");
   if(GlobalVariableCheck(p+"PYR")) g_pyramidCount=(int)GlobalVariableGet(p+"PYR");
   if(GlobalVariableCheck(p+"NAN")) g_nanpinLogicalCount=(int)GlobalVariableGet(p+"NAN");
   if(GlobalVariableCheck(p+"EXT")) g_extremePrice=GlobalVariableGet(p+"EXT");
   if(GlobalVariableCheck(p+"STOP")) g_basketStop=GlobalVariableGet(p+"STOP");
   if(GlobalVariableCheck(p+"ACT")) g_lastActionTime=(datetime)GlobalVariableGet(p+"ACT");
   if(GlobalVariableCheck(p+"EXIT")) g_lastExitTime=(datetime)GlobalVariableGet(p+"EXIT");
   return true;
}

double DetectPip(string symbol)
{
   if(pip価格換算>0.0) return pip価格換算;
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   return point*((digits==5 || digits==3)?10.0:1.0);
}
double NormalizeLot(double lot)
{
   if(lot<=0) return 0;
   double minLot=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MIN), maxLot=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MAX);
   double brokerStep=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_STEP);
   double step=(ロット刻み>0)?MathMax(ロット刻み,brokerStep):brokerStep; if(step<=0) step=0.01;
   lot=MathFloor((lot+1e-12)/step)*step; if(lot<minLot) return 0; lot=MathMin(lot,maxLot);
   int vd=2; if(step>=1.0) vd=0; else if(step>=0.1) vd=1; else if(step>=0.01) vd=2; else vd=3;
   return NormalizeDouble(lot,vd);
}
datetime JSTNow()
{
   if(MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)) return TimeCurrent()+(9-テスターサーバーUTC差)*3600;
   return TimeGMT()+9*3600;
}
bool IsAllowedDay()
{
   if(!曜日設定機能) return true; MqlDateTime dt; TimeToStruct(JSTNow(),dt);
   switch(dt.day_of_week){case 0:return 日曜日稼働; case 1:return 月曜日稼働; case 2:return 火曜日稼働; case 3:return 水曜日稼働; case 4:return 木曜日稼働; case 5:return 金曜日稼働; case 6:return 土曜日稼働;} return false;
}
bool IsAllowedTime()
{
   if(!時間設定機能) return true; MqlDateTime dt; TimeToStruct(JSTNow(),dt);
   int now=dt.hour*60+dt.min, st=取引開始時刻_時*60+取引開始時刻_分, en=取引終了時刻_時*60+取引終了時刻_分;
   if(st==en) return true; if(st<en) return(now>=st&&now<en); return(now>=st||now<en);
}
bool EntryWindowOpen(){return IsAllowedDay()&&IsAllowedTime();}
bool AdditionalOrderAllowed(bool isPyramid){if(EntryWindowOpen()) return true; return isPyramid?時間外ピラミッディング許可:時間外ナンピン許可;}
double CurrentSpreadPips(const MqlTick &tick){return(g_pip>0)?(tick.ask-tick.bid)/g_pip:0;}
bool SpreadOK(const MqlTick &tick){return 新規最大スプレッド_pips<=0||CurrentSpreadPips(tick)<=新規最大スプレッド_pips;}

int CountPositions()
{
   int n=0; for(int i=PositionsTotal()-1;i>=0;i--) if(posInfo.SelectByIndex(i)&&posInfo.Symbol()==g_symbol&&posInfo.Magic()==マジック番号) n++; return n;
}
int CountPositionsByType(ENUM_POSITION_TYPE type)
{
   int n=0; for(int i=PositionsTotal()-1;i>=0;i--) if(posInfo.SelectByIndex(i)&&posInfo.Symbol()==g_symbol&&posInfo.Magic()==マジック番号&&posInfo.PositionType()==type) n++; return n;
}
double CalcTotalLots()
{
   double v=0; for(int i=PositionsTotal()-1;i>=0;i--) if(posInfo.SelectByIndex(i)&&posInfo.Symbol()==g_symbol&&posInfo.Magic()==マジック番号) v+=posInfo.Volume(); return v;
}
double CalcWeightedAverage()
{
   double sum=0,vol=0; for(int i=PositionsTotal()-1;i>=0;i--) if(posInfo.SelectByIndex(i)&&posInfo.Symbol()==g_symbol&&posInfo.Magic()==マジック番号){sum+=posInfo.PriceOpen()*posInfo.Volume();vol+=posInfo.Volume();} return(vol>0)?sum/vol:0;
}
double CalcAccountProfit()
{
   double p=0; for(int i=PositionsTotal()-1;i>=0;i--) if(posInfo.SelectByIndex(i)&&posInfo.Symbol()==g_symbol&&posInfo.Magic()==マジック番号) p+=posInfo.Profit()+posInfo.Swap(); return p;
}
bool FindJPYRate(double &rate)
{
   if(円換算レート固定>0){rate=円換算レート固定;return true;}
   string cur=AccountInfoString(ACCOUNT_CURRENCY); StringToUpper(cur); if(cur=="JPY"){rate=1.0;return true;}
   string candidates[2]={cur+"JPY","JPY"+cur};
   for(int c=0;c<2;c++){int total=SymbolsTotal(false);for(int i=0;i<total;i++){string s=SymbolName(i,false),up=s;StringToUpper(up);if(StringFind(up,candidates[c])<0)continue;if(!SymbolSelect(s,true))continue;MqlTick t;if(!SymbolInfoTick(s,t)||t.bid<=0||t.ask<=0)continue;rate=(c==0)?t.bid:1.0/t.ask;return rate>0;}}
   return false;
}
bool CalcProfitJPY(double &profitJPY){double rate=0;if(!FindJPYRate(rate))return false;profitJPY=CalcAccountProfit()*rate*口座通貨補正倍率;return true;}
bool CheckMaxTotalLot(double addLot){return 最大合計ロット<=0||CalcTotalLots()+addLot<=最大合計ロット+1e-10;}

bool OpenOrder(ENUM_POSITION_TYPE type,double lot,string tag)
{
   lot=NormalizeLot(lot); if(lot<=0||!CheckMaxTotalLot(lot)) return false;
   trade.SetExpertMagicNumber(マジック番号); trade.SetDeviationInPoints(許容スリッページ_ポイント); trade.SetTypeFillingBySymbol(g_symbol);
   string comment=EAコメント+"_"+tag;
   bool ok=(type==POSITION_TYPE_BUY)?trade.Buy(lot,g_symbol,0,0,0,comment):trade.Sell(lot,g_symbol,0,0,0,comment);
   if(!ok) Print("発注失敗 ",tag," ",trade.ResultRetcodeDescription()); return ok;
}
void CloseAll(string reason)
{
   trade.SetExpertMagicNumber(マジック番号); trade.SetTypeFillingBySymbol(g_symbol);
   for(int pass=0;pass<3;pass++){bool any=false;for(int i=PositionsTotal()-1;i>=0;i--){if(posInfo.SelectByIndex(i)&&posInfo.Symbol()==g_symbol&&posInfo.Magic()==マジック番号){any=true;ulong ticket=posInfo.Ticket();if(!trade.PositionClose(ticket))Print("決済失敗 ticket=",ticket," ",trade.ResultRetcodeDescription());}}if(!any||CountPositions()==0)break;}
   if(CountPositions()==0){Print("全決済: ",reason);g_lastExitTime=TimeCurrent();g_mode=MODE_FLAT;g_initialPrice=0;g_lastAddPrice=0;g_pyramidCount=0;g_nanpinLogicalCount=0;g_extremePrice=0;g_basketStop=0;g_lastActionTime=0;ClearState();GlobalVariableSet(StatePrefix()+"EXIT",(double)g_lastExitTime);}
}

int GetRSICrossSignal()
{
   datetime bar=iTime(g_symbol,RSI時間足,0); if(bar<=0||bar==g_lastSignalBar)return 0; g_lastSignalBar=bar;
   double rsi[2]; if(CopyBuffer(g_rsiHandle,0,1,2,rsi)!=2)return 0; double older=rsi[0],latest=rsi[1];
   if(older<買いエントリーRSI&&latest>=買いエントリーRSI&&latest<=買いRSI上限)return 1;
   if(older>売りエントリーRSI&&latest<=売りエントリーRSI&&latest>=売りRSI下限)return -1; return 0;
}
void ProcessInitialEntry(const MqlTick &tick)
{
   if(g_mode!=MODE_FLAT||CountPositions()>0)return; if(!新規エントリー許可||!EntryWindowOpen()||!SpreadOK(tick))return;
   if(g_lastExitTime>0&&TimeCurrent()-g_lastExitTime<決済後再エントリー待機_分*60)return;
   int sig=GetRSICrossSignal(); ENUM_POSITION_TYPE type;
   if(sig==1&&売買方向!=ショートのみ)type=POSITION_TYPE_BUY;else if(sig==-1&&売買方向!=ロングのみ)type=POSITION_TYPE_SELL;else return;
   if(OpenOrder(type,初期ロット,"INIT")){g_mode=MODE_INITIAL;g_direction=type;double fill=trade.ResultPrice();if(fill<=0)fill=(type==POSITION_TYPE_BUY)?tick.ask:tick.bid;g_initialPrice=fill;g_lastAddPrice=fill;g_lastActionTime=TimeCurrent();SaveState();}
}

double PyramidLotForAdd(int addNumber){if(addNumber<=0)return 0;return NormalizeLot(初期ロット*MathPow(ピラミッディングロット倍率,addNumber));}
void ProcessPyramid(const MqlTick &tick)
{
   if(!ピラミッディング機能||(g_mode!=MODE_INITIAL&&g_mode!=MODE_PYRAMID)||g_pyramidCount>=最大ピラミッディング回数)return;
   if(!AdditionalOrderAllowed(true)||!SpreadOK(tick)||TimeCurrent()-g_lastActionTime<ピラミッディング最短追加間隔_秒)return;
   double px=(g_direction==POSITION_TYPE_BUY)?tick.ask:tick.bid;
   double trigger=(g_direction==POSITION_TYPE_BUY)?g_lastAddPrice+ピラミッディング間隔_pips*g_pip:g_lastAddPrice-ピラミッディング間隔_pips*g_pip;
   bool hit=(g_direction==POSITION_TYPE_BUY)?px>=trigger:px<=trigger;if(!hit)return;
   int nextAdd=g_pyramidCount+1;double lot=PyramidLotForAdd(nextAdd);if(lot<=0)return;
   if(OpenOrder(g_direction,lot,"PYR"+IntegerToString(nextAdd))){g_mode=MODE_PYRAMID;g_pyramidCount=nextAdd;double fill=trade.ResultPrice();if(fill<=0)fill=px;g_lastAddPrice=fill;g_lastActionTime=TimeCurrent();g_extremePrice=(g_direction==POSITION_TYPE_BUY)?tick.bid:tick.ask;SaveState();}
}
void ApplyServerStop(double stop)
{
   if(!サーバーSL併用||stop<=0)return;int stopsLevel=(int)SymbolInfoInteger(g_symbol,SYMBOL_TRADE_STOPS_LEVEL);double minDist=stopsLevel*SymbolInfoDouble(g_symbol,SYMBOL_POINT);MqlTick tick;if(!SymbolInfoTick(g_symbol,tick))return;
   if(g_direction==POSITION_TYPE_BUY&&tick.bid-stop<minDist)return;if(g_direction==POSITION_TYPE_SELL&&stop-tick.ask<minDist)return;
   for(int i=PositionsTotal()-1;i>=0;i--)if(posInfo.SelectByIndex(i)&&posInfo.Symbol()==g_symbol&&posInfo.Magic()==マジック番号&&posInfo.PositionType()==g_direction){double currentSL=posInfo.StopLoss();bool improve=(g_direction==POSITION_TYPE_BUY)?(currentSL==0||stop>currentSL):(currentSL==0||stop<currentSL);if(improve)trade.PositionModify(posInfo.Ticket(),NormalizeDouble(stop,g_digits),0.0);}
}
void ProcessPyramidTrail(const MqlTick &tick)
{
   if(!トレール機能||g_mode!=MODE_PYRAMID||CountPositions()==0)return;double avg=CalcWeightedAverage();if(avg<=0)return;
   if(g_direction==POSITION_TYPE_BUY){if(g_extremePrice<=0||tick.bid>g_extremePrice)g_extremePrice=tick.bid;double defense=(CountPositions()>=建値保護開始ポジション数)?avg+建値保護利益_pips*g_pip:avg-初回ピラミッド損切り余裕_pips*g_pip;double follow=g_extremePrice-トレール幅_pips*g_pip;double candidate=MathMax(defense,follow);if(g_basketStop<=0||candidate>g_basketStop)g_basketStop=candidate;ApplyServerStop(g_basketStop);SaveState();if(tick.bid<=g_basketStop)CloseAll("ピラミッディングトレール");}
   else{if(g_extremePrice<=0||tick.ask<g_extremePrice)g_extremePrice=tick.ask;double defense=(CountPositions()>=建値保護開始ポジション数)?avg-建値保護利益_pips*g_pip:avg+初回ピラミッド損切り余裕_pips*g_pip;double follow=g_extremePrice+トレール幅_pips*g_pip;double candidate=MathMin(defense,follow);if(g_basketStop<=0||candidate<g_basketStop)g_basketStop=candidate;ApplyServerStop(g_basketStop);SaveState();if(tick.ask>=g_basketStop)CloseAll("ピラミッディングトレール");}
}

double NanpinLotForAdd(int addNumber){if(addNumber<=0)return 0;return NormalizeLot(初期ロット*MathPow(ナンピンロット倍率,addNumber));}
void ProcessNanpin(const MqlTick &tick)
{
   if(!ナンピン機能||(g_mode!=MODE_INITIAL&&g_mode!=MODE_NANPIN)||g_nanpinLogicalCount>=最大ナンピン回数)return;
   if(!AdditionalOrderAllowed(false)||TimeCurrent()-g_lastActionTime<ナンピン最短追加間隔_秒)return;
   double px=(g_direction==POSITION_TYPE_BUY)?tick.ask:tick.bid;double adverse=(g_direction==POSITION_TYPE_BUY)?g_lastAddPrice-px:px-g_lastAddPrice;if(adverse<ナンピン間隔_pips*g_pip)return;
   int steps=(int)MathFloor(adverse/(ナンピン間隔_pips*g_pip));if(steps<1)steps=1;if(!見送り加算機能)steps=1;if(最大見送り加算段数>0)steps=MathMin(steps,最大見送り加算段数);steps=MathMin(steps,最大ナンピン回数-g_nanpinLogicalCount);if(steps<=0)return;
   double totalLot=0;for(int k=1;k<=steps;k++)totalLot+=NanpinLotForAdd(g_nanpinLogicalCount+k);totalLot=NormalizeLot(totalLot);if(totalLot<=0)return;
   int endStage=g_nanpinLogicalCount+steps;string tag=(steps>1)?"NAN_SKIP"+IntegerToString(steps)+"_S"+IntegerToString(endStage):"NAN"+IntegerToString(endStage);
   if(OpenOrder(g_direction,totalLot,tag)){g_mode=MODE_NANPIN;g_nanpinLogicalCount=endStage;double fill=trade.ResultPrice();if(fill<=0)fill=px;g_lastAddPrice=fill;g_lastActionTime=TimeCurrent();SaveState();}
}
void ProcessNanpinExit(const MqlTick &tick)
{
   if(g_mode!=MODE_NANPIN||CountPositions()==0)return;double avg=CalcWeightedAverage();if(avg<=0)return;double px=(g_direction==POSITION_TYPE_BUY)?tick.bid:tick.ask;double target=(g_direction==POSITION_TYPE_BUY)?avg+ナンピン決済幅_pips*g_pip:avg-ナンピン決済幅_pips*g_pip;bool hit=(g_direction==POSITION_TYPE_BUY)?px>=target:px<=target;if(!hit)return;
   if(最低合計利益_円>0){double profitJPY=0;if(!CalcProfitJPY(profitJPY)){Print("円換算レートを取得できないためナンピンTP判定を保留");return;}if(profitJPY<最低合計利益_円)return;}else if(CalcAccountProfit()<0)return;
   CloseAll("ナンピンバスケットTP");
}

bool ProcessMaxLoss()
{
   if(!含み損損切り機能||CountPositions()==0)return false;double jpy=0;if(!CalcProfitJPY(jpy)){Print("円換算レートを取得できないため含み損損切り判定不可");return false;}if(jpy<=-最大含み損_円){CloseAll("最大含み損到達 "+DoubleToString(jpy,0)+"円");return true;}return false;
}

void RecoverFromPositions()
{
   int total=CountPositions();if(total==0){g_mode=MODE_FLAT;string p=StatePrefix();if(GlobalVariableCheck(p+"EXIT"))g_lastExitTime=(datetime)GlobalVariableGet(p+"EXIT");return;}
   ENUM_POSITION_TYPE foundType=POSITION_TYPE_BUY;datetime firstTime=0,lastTime=0;double firstPrice=0,lastPrice=0;int pyr=0,nan=0;bool sawPyr=false,sawNan=false;
   for(int i=PositionsTotal()-1;i>=0;i--)if(posInfo.SelectByIndex(i)&&posInfo.Symbol()==g_symbol&&posInfo.Magic()==マジック番号){foundType=posInfo.PositionType();datetime t=posInfo.Time();if(firstTime==0||t<firstTime){firstTime=t;firstPrice=posInfo.PriceOpen();}if(t>=lastTime){lastTime=t;lastPrice=posInfo.PriceOpen();}string c=posInfo.Comment();if(StringFind(c,"_PYR")>=0){sawPyr=true;pyr++;}if(StringFind(c,"_NAN")>=0){sawNan=true;int skipPos=StringFind(c,"_NAN_SKIP");if(skipPos>=0){int stagePos=StringFind(c,"_S",skipPos+9);if(stagePos>=0)nan=MathMax(nan,(int)StringToInteger(StringSubstr(c,stagePos+2)));}else nan++;}}
   g_direction=foundType;g_initialPrice=firstPrice;g_lastAddPrice=lastPrice;g_lastActionTime=lastTime;if(sawPyr){g_mode=MODE_PYRAMID;g_pyramidCount=pyr;}else if(sawNan){g_mode=MODE_NANPIN;g_nanpinLogicalCount=nan;}else g_mode=MODE_INITIAL;SaveState();
}

bool ValidateAccountMode()
{
   long marginMode=AccountInfoInteger(ACCOUNT_MARGIN_MODE);if(marginMode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING){Alert("HYBRID-PN: ヘッジ口座専用です。ネットティング口座では起動できません。");return false;}return true;
}
bool ValidateInputs()
{
   if(初期ロット<=0||ピラミッディング間隔_pips<=0||ナンピン間隔_pips<=0||トレール幅_pips<=0)return false;if(ピラミッディングロット倍率<=0||ピラミッディングロット倍率>=1.0)return false;if(ナンピンロット倍率<1.0)return false;if(最大ピラミッディング回数<0||最大ナンピン回数<0)return false;return true;
}
void UpdateChartComment()
{
   string mode="FLAT";if(g_mode==MODE_INITIAL)mode="INITIAL";else if(g_mode==MODE_PYRAMID)mode="PYRAMID";else if(g_mode==MODE_NANPIN)mode="NANPIN";string dir=(g_direction==POSITION_TYPE_BUY)?"BUY":"SELL";double jpy=0;bool hasJPY=CalcProfitJPY(jpy);
   string text="HYBRID-PN v1.01\n";text+="Mode: "+mode+"  Dir: "+dir+"  Positions: "+IntegerToString(CountPositions())+"\n";text+="Pip換算: "+DoubleToString(g_pip,g_digits)+"  PYR実価格差: "+DoubleToString(ピラミッディング間隔_pips*g_pip,g_digits)+"  NAN実価格差: "+DoubleToString(ナンピン間隔_pips*g_pip,g_digits)+"\n";text+="PYR回数: "+IntegerToString(g_pyramidCount)+"  NAN論理回数: "+IntegerToString(g_nanpinLogicalCount)+"\n";text+="Avg: "+DoubleToString(CalcWeightedAverage(),g_digits)+"  Stop: "+DoubleToString(g_basketStop,g_digits)+"\n";text+="JST: "+TimeToString(JSTNow(),TIME_DATE|TIME_MINUTES)+"  新規時間: "+(EntryWindowOpen()?"ON":"OFF")+"\n";text+="損益円換算: "+(hasJPY?DoubleToString(jpy,0)+"円":"取得不可");Comment(text);
}

int OnInit()
{
   if(!ValidateInputs()){Alert("HYBRID-PN: 入力パラメーターが不正です");return INIT_PARAMETERS_INCORRECT;}if(!ValidateAccountMode())return INIT_FAILED;
   g_symbol=_Symbol;g_digits=(int)SymbolInfoInteger(g_symbol,SYMBOL_DIGITS);g_pip=DetectPip(g_symbol);if(g_pip<=0)return INIT_FAILED;
   g_rsiHandle=iRSI(g_symbol,RSI時間足,RSI期間,PRICE_CLOSE);if(g_rsiHandle==INVALID_HANDLE){Alert("HYBRID-PN: RSIハンドル作成失敗");return INIT_FAILED;}
   trade.SetExpertMagicNumber(マジック番号);trade.SetDeviationInPoints(許容スリッページ_ポイント);
   if(!LoadState()||CountPositions()==0)RecoverFromPositions();else{int typeCount=CountPositionsByType(g_direction);if(typeCount!=CountPositions()){Alert("HYBRID-PN: 同一マジックでBUY/SELL混在を検出。安全のため起動停止。");return INIT_FAILED;}}
   if(含み損損切り機能||最低合計利益_円>0){double rate=0;if(!FindJPYRate(rate)){Alert("HYBRID-PN: 円換算レートを取得できません。円換算レート固定を設定してください。");return INIT_FAILED;}}
   EventSetTimer(1);Print("HYBRID-PN v1.01 起動 / Symbol=",g_symbol," / pip=",g_pip);return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){SaveState();if(g_rsiHandle!=INVALID_HANDLE)IndicatorRelease(g_rsiHandle);EventKillTimer();Comment("");}
void Process()
{
   if(g_processing)return;g_processing=true;MqlTick tick;if(!SymbolInfoTick(g_symbol,tick)||tick.bid<=0||tick.ask<=0){g_processing=false;return;}
   if(CountPositions()==0&&g_mode!=MODE_FLAT){g_lastExitTime=TimeCurrent();g_mode=MODE_FLAT;g_initialPrice=0;g_lastAddPrice=0;g_pyramidCount=0;g_nanpinLogicalCount=0;g_extremePrice=0;g_basketStop=0;ClearState();GlobalVariableSet(StatePrefix()+"EXIT",(double)g_lastExitTime);}
   if(ProcessMaxLoss()){UpdateChartComment();g_processing=false;return;}
   ProcessPyramidTrail(tick);if(CountPositions()>0)ProcessNanpinExit(tick);
   if(CountPositions()>0){ProcessPyramid(tick);ProcessNanpin(tick);}else ProcessInitialEntry(tick);
   UpdateChartComment();g_processing=false;
}
void OnTick(){Process();}
void OnTimer(){Process();}
//+------------------------------------------------------------------+
