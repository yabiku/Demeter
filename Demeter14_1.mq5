//Demeter14_1
//アイディア
//・利確時に早くできるように、Ticketをメモリに入れておく
//・損益の値(金額)もメモリにいれておく
//・損益の値をベースに利確する
//・他のEAがエントリーしている場合は、同じ方向にはエントリーしない

#property strict
#property version   "1.20"

#include <Trade/Trade.mqh>
#include <Indicators/Trend.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Indicators/Oscilators.mqh>

#include <Controls/Dialog.mqh>
#include <Controls/CheckBox.mqh>
#include <Controls/Button.mqh>
#include <Controls/Label.mqh>

#include <Object.mqh>
#include <Generic/HashMap.mqh>

long MAGIC[] = {-1, 0, 10, 20, 30}; //最初は-1とするRescueモード
string prefix[] = {"Rescue", "NonEA", "EA1", "EA2", "EA3"};
color clr_buy[] = {clrBlue, clrAqua, clrBlueViolet, clrDarkBlue, clrBlue};
color clr_sell[] = {clrRed, clrPink, clrDarkOrange, clrDarkRed, clrRed};

//現在のポジション情報を格納
//--- 値（構造体の代わり：CObject継承クラス）
class CPosInfo : public CObject
{
public:
   long     magic;
   ENUM_POSITION_TYPE pos_type;
   double   entry_price;
   double   volume;
   datetime entry_time;
};

//---------------- IMapの実体
CHashMap<ulong, CPosInfo*> posMap;

string EAName = MQLInfoString(MQL_PROGRAM_NAME);
string lblStatus = "status";
string account_company_name = AccountInfoString(ACCOUNT_COMPANY);
double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

enum NanpinType {
   offense = 0, //攻撃型
   balance = 1, //バランス型
   defense = 2, //防御型
   noninterval = 3, //インターバル無し
};

input bool EA_auto_lots = true; //EAエントリーロットの自動計算のON(true)
input double EA_in_start_lots = 0.01; //EA最初のロット数
input bool SendNotificationFlg = false; //MT5含み損通知ON(true)
input bool SendNotificationTPFlg = false; //MT5利確通知ON(true)
input bool RescueSendNotification = false; //レスキューモードの通知ON(true)
input int NanpinMultiNumber = 1; //指定されたナンピン数までノンインターバルにする
input int max_nanpin = 18; //ナンピン数の最大
input NanpinType n_type = defense; //ナンピンタイプ
input bool songiriMode = true; //損切モード（指定された金額で損切）
input double songiri = 30000; //損切金額
input double toRescue = 10000; //レスキュー移行価格（円）
input double RescueBuyTP = 2500; //レスキューモードBuy利確価格(0は利確しない)
input double RescueSellTP = 2500; //レスキューモードSell利確価格(0は利確しない)

input double TrailStart = 10.0; //トレール開始値
input double TrailInterval = 5.0; //トレール幅
input double SpreadFilter = 5.0; //スプレッドフィルター
input double plusTP = 3.0; //プラ転決済
input int plusNanpin = 5; //プラ転決済ポジション
input double nanpin_base_diff = 20; //ナンピン価格幅のベース
input int nanpin_base_time = 5; //ナンピン時間差のベース(分)
input double nanpin_lots_bairitsu = 1.5; //ナンピンロット倍率
input double plusNanpin_lots_bairitsu = 1.2; //プラテン決済時のナンピンロット倍率

enum startEnd {
   s = 0, //する（時間指定）
   end = 1, //しない
   full = 2, //フル稼働
};
input startEnd in_entry = s; //平日稼働時間
input string in_stime = "10:00"; //平日稼働開始
input string in_etime = "14:00"; //平日稼働停止

double nextBuyNanpinPrice[MAGIC.Size()]; //次のナンピン価格(Buy)
datetime nextBuyNanpinTime[MAGIC.Size()]; //次のナンピン時間(Buy)
double nextSellNanpinPrice[MAGIC.Size()]; //次のナンピン価格(Sell)
datetime nextSellNanpinTime[MAGIC.Size()]; //次のナンピン時間(Sell)
ulong LowestPriceTicketNo[MAGIC.Size()]; //最も低いポジションのTicket番号
ulong HighestPriceTicketNo[MAGIC.Size()]; //最も高いポジションのTicket番号
double nanpin_haba = 15; //ナンピンの幅(pips)
long nanpin_late_time = 5; //ナンピンの遅延時間（分）

double weightAverageBuy[MAGIC.Size()]; //MAGIC毎の加重平均価格(Buy))
double weightAverageSell[MAGIC.Size()]; //MAGIC毎の加重平均価格(Sell))

double EABuyProfits[MAGIC.Size()]; //MAGIC毎の損益(Buy)
double EASellProfits[MAGIC.Size()]; //MAGIC毎の損益(Sell)

double trailStart_buy_price[MAGIC.Size()]; //Trailing開始価格(Buy)
double trailStart_sell_price[MAGIC.Size()];////Trailing開始価格(Sell)
double trail_buy_price[MAGIC.Size()]; //Trailing価格(Buy)
double trail_sell_price[MAGIC.Size()];////Trailing価格(Sell)

//EA1用パラメータ RSIとボリバン
CiRSI CiRsiEA1;
CiBands CiBandsEA1;
ENUM_TIMEFRAMES RSITimeFrameEA1 = PERIOD_M1; //Long用のRSIのタイムフレーム
ENUM_TIMEFRAMES BandsTimeFrameEA1 = PERIOD_M1; //Long用のBBのタイムフレーム
int RSIPeriodEA1 = 14; //Long用のRSIのPeriod
int BandsPeriodEA1 = 20; //Long用のBBのPeriod
double BandsSigmaEA1 = 2.0; //Long用のBBのシグマ

//For EA3
CiRSI CiRsiEA3;
input ENUM_TIMEFRAMES RSITimeFrameEA3 = PERIOD_M1; //EA3のRSIタイムフレーム
input int RSIPeriodEA3 = 14; //EA3のRSIのPeriod
input int LookBackEA3 = 200; //EA3の過去バー数の数

class CMyPanel : public CAppDialog
{
private:
   CLabel   lblJPNTime;
   CPanel   EAPanel[MAGIC.Size()];
   CLabel   lblEAName[MAGIC.Size()];
   CLabel   lblBuyProfits[MAGIC.Size()];
   CLabel   lblSellProfits[MAGIC.Size()];
   CCheckBox chkBuyRescue;
   CCheckBox chkSellRescue;
   CLabel   lblBuyNanpin[MAGIC.Size()];
   CLabel   lblSellNanpin[MAGIC.Size()];
   CButton   btnBuy[MAGIC.Size()];
   CButton   btnSell[MAGIC.Size()];

public:
   bool CreatePanel(const long chart_id)
   {      
      int dy = 60;

      // ダイアログ作成（背景の枠）
      if(!CAppDialog::Create(chart_id, EAName, 0, 20, 20, 255, 135+dy*(MAGIC.Size()-1)))
         return false;

      // 表示
      this.Show();
      
      // ---- ラベル日本時間 ----
      if(!lblJPNTime.Create(chart_id, "lblJPN", 0, 2, 2, 100, 25))
         return false;
      lblJPNTime.FontSize(8);
      lblJPNTime.Text("");
      if(!this.Add(lblJPNTime))
         return false;
      lblJPNTime.Show();
      

      for(int i=0; i<(int)MAGIC.Size(); i++) {
         // ----- 枠 -------      
         if(!EAPanel[i].Create(chart_id, prefix[i]+"Panel", 0, 2, 25+dy*i, 225, 80+dy*i))
            return false;
         EAPanel[i].ColorBorder(clrBlack);
         if(!this.Add(EAPanel[i]))
            return false;
         EAPanel[i].Show();
         
         //--- EAの名前 -----
         if(!lblEAName[i].Create(chart_id, prefix[i]+"Name", 0, 5, 22+dy*i, 100, 28+dy*i))
            return false;
         lblEAName[i].FontSize(8);
         lblEAName[i].Text(prefix[i]);
         if(!this.Add(lblEAName[i]))
            return false;
         lblEAName[i].Show();
   
         //--- 損益 -----
         if(!lblBuyProfits[i].Create(chart_id, prefix[i]+"BuyProfits", 0, 5, 37+dy*i, 100, 45+dy*i))
            return false;
         lblBuyProfits[i].FontSize(8);
         lblBuyProfits[i].Text("0");
         if(!this.Add(lblBuyProfits[i]))
            return false;
         lblBuyProfits[i].Show();
   
         if(!lblSellProfits[i].Create(chart_id, prefix[i]+"SellProfits", 0, 5, 55+dy*i, 100, 63+dy*i))
            return false;
         lblSellProfits[i].FontSize(8);
         lblSellProfits[i].Text("0");
         if(!this.Add(lblSellProfits[i]))
            return false;
         lblSellProfits[i].Show();
   
         if(MAGIC[i] == -1) {
            // ---- Rescueチェックボックス ----
            if(!chkBuyRescue.Create(chart_id, prefix[i]+"BuyChk", 0, 85, 39+dy*i, 150, 60+dy*i))
               return false;
            chkBuyRescue.Text("OFF");
            chkBuyRescue.Checked(false);
            if(!this.Add(chkBuyRescue))
               return false;
            chkBuyRescue.Show();
      
            if(!chkSellRescue.Create(chart_id, prefix[i]+"SellChk", 0, 85, 57+dy*i, 150, 78+dy*i))
               return false;
            chkSellRescue.Text("OFF");
            chkSellRescue.Checked(false);
            if(!this.Add(chkSellRescue))
               return false;
            chkSellRescue.Show();
         } else {
            if(!lblBuyNanpin[i].Create(chart_id, prefix[i]+"BuyNanpin", 0, 85, 37+dy*i, 150, 45+dy*i))
               return false;
            lblBuyNanpin[i].FontSize(8);
            lblBuyNanpin[i].Text("0.0");
            if(!this.Add(lblBuyNanpin[i]))
               return false;
            lblBuyNanpin[i].Show();
      
            if(!lblSellNanpin[i].Create(chart_id, prefix[i]+"SellNanpin", 0, 85, 55+dy*i, 150, 63+dy*i))
               return false;
            lblSellNanpin[i].FontSize(8);
            lblSellNanpin[i].Text("0.0");
            if(!this.Add(lblSellNanpin[i]))
               return false;
            lblSellNanpin[i].Show();
         }
   
         // ---- 決済ボタン ----
         if(!btnBuy[i].Create(chart_id, prefix[i]+"btnBuy", 0, 150, 39+dy*i, 220, 55+dy*i))
            return false;
         btnBuy[i].FontSize(8);
         btnBuy[i].Text("BuyClose");
         if(!this.Add(btnBuy[i]))
            return false;
         btnBuy[i].Show();
   
         if(!btnSell[i].Create(chart_id, prefix[i]+"btnSell", 0, 150, 58+dy*i, 220, 74+dy*i))
            return false;
         btnSell[i].FontSize(8);
         btnSell[i].Text("SellClose");
         if(!this.Add(btnSell[i]))
            return false;
         btnSell[i].Show();
      }
      
      ChartRedraw(chart_id);
      return true;
   }

   virtual bool ChartEvent(const int id,
                        const long &lparam,
                        const double &dparam,
                        const string &sparam)
   {
      // クリックイベントのみ処理（誤反応防止）
      if(id == CHARTEVENT_OBJECT_CLICK)
      {
         // チェックボックス
         if(StringFind(sparam,"RescueBuyChk")>=0)
         {
            if(chkBuyRescue.Checked())
            {
               chkBuyRescue.Text("ON");
               Print("チェックボックス：ONになりました");
            }
            else
            {
               chkBuyRescue.Text("OFF");
               Print("チェックボックス：OFFになりました");
            }
         }
         
         if(StringFind(sparam, "RescueSellChk")>=0) {
            if(chkSellRescue.Checked())
            {
               chkSellRescue.Text("ON");
               Print("チェックボックス：ONになりました");
            }
            else
            {
               chkSellRescue.Text("OFF");
               Print("チェックボックス：OFFになりました");
            }
         }

         for(int i=0; i<(int)MAGIC.Size(); i++) {
            // ボタン
            if(sparam == prefix[i]+"btnBuy")
            {
               Print("ボタン："+prefix[i]+"btnBuyが押されました");
               CloseAllPositions(POSITION_TYPE_BUY, MAGIC[i]);
               btnBuy[i].Pressed(false);
            }
            if(sparam == prefix[i]+"btnSell")
            {
               Print("ボタン："+prefix[i]+"btnSellが押されました");
               CloseAllPositions(POSITION_TYPE_SELL, MAGIC[i]);
               btnSell[i].Pressed(false);
            }
         }
         ChartRedraw(m_chart_id);
      }

      return CAppDialog::OnEvent(id, lparam, dparam, sparam);
   }
   
   virtual bool getBuyCheckBox() {
      return chkBuyRescue.Checked();
   }

   virtual bool getSellCheckBox() {
      return chkSellRescue.Checked();
   }
   
   virtual void setBuyCheckBox(bool chk) {
      chkBuyRescue.Checked(chk);
   }

   virtual void setSellCheckBox(bool chk) {
      chkSellRescue.Checked(chk);
   }
   
   virtual string getBuyCheckBoxText() {
      return chkBuyRescue.Text();
   }

   virtual string getSellCheckBoxText() {
      return chkSellRescue.Text();
   }

   virtual void setBuyCheckBoxText(string txt) {
      chkBuyRescue.Text(txt);
   }

   virtual void setSellCheckBoxText(string txt) {
      chkSellRescue.Text(txt);
   }
   
   virtual void setLblJPNTime(string jpn_time) {
      lblJPNTime.Text(jpn_time);
   }
   
   void setLblProfits(ENUM_POSITION_TYPE buyorsell, double profits, int magic_idx) {
      if(buyorsell == POSITION_TYPE_BUY) {
         if(profits == 0.0) {
            lblBuyProfits[magic_idx].Color(clrBlack);
         } else if(profits < 0) {
            lblBuyProfits[magic_idx].Color(clrRed);
         } else if(profits > 0) {
            lblBuyProfits[magic_idx].Color(clrBlue);
         }
         lblBuyProfits[magic_idx].Text(addcomma(profits,0));
      } else {
         if(profits == 0.0) {
            lblSellProfits[magic_idx].Color(clrBlack);
         } else if(profits < 0) {
            lblSellProfits[magic_idx].Color(clrRed);
         } else if(profits > 0) {
            lblSellProfits[magic_idx].Color(clrBlue);
         }
         lblSellProfits[magic_idx].Text(addcomma(profits,0));
      }
   }
   
   string getLblProfits(ENUM_POSITION_TYPE buyorsell, int magic_idx) {
      if(buyorsell == POSITION_TYPE_BUY) {
         return lblBuyProfits[magic_idx].Text();
      } else {
         return lblSellProfits[magic_idx].Text();
      }
   }
   
   void setLblNanpin(ENUM_POSITION_TYPE buyorsell, double nanpin_price, int magic_idx) {
      if(buyorsell == POSITION_TYPE_BUY) {
         lblBuyNanpin[magic_idx].Text((string)nanpin_price);
      } else {
         lblSellNanpin[magic_idx].Text((string)nanpin_price);
      }
   }
   
   string getLblNanpin(ENUM_POSITION_TYPE buyorsell, int magic_idx) {
      if(buyorsell == POSITION_TYPE_BUY) {
         return lblBuyNanpin[magic_idx].Text();
      } else {
         return lblSellNanpin[magic_idx].Text();
      }
   }
};

CMyPanel panel;
CTrade trade;
//CPositionInfo Cposition;
CSymbolInfo Csymbol;

int OnInit()
{
   EventSetTimer(1);
   ChartSetInteger(0, CHART_FOREGROUND, false);
   
   getAllPositionInfo();
   getWeightAverage();
               
   if(!panel.CreatePanel(ChartID()))
   {
      Print("パネル作成失敗");
      return INIT_FAILED;
   }

   panel.Run();

   if(!ObjectCreate(0, lblStatus, OBJ_LABEL, 0, 0, 0)) {
      Print("Label Create Error...");
   }
   ObjectSetString(0, lblStatus, OBJPROP_TEXT, "");
   ObjectSetInteger(0, lblStatus, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, lblStatus, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, lblStatus, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, lblStatus, OBJPROP_YDISTANCE, 40);
   ObjectSetInteger(0, lblStatus, OBJPROP_FONTSIZE, 13);

   //パネル表示するやつは、パネルが表示されてから値をいれる
   for(int i=1; i<(int)MAGIC.Size(); i++) {
      nextNanpinPriceTime(POSITION_TYPE_BUY, i);
      nextNanpinPriceTime(POSITION_TYPE_SELL,i);
      trail_buy_price[i] = 0.0;
      trail_sell_price[i] = 0.0;
   }
   
   return INIT_SUCCEEDED;
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   panel.ChartEvent(id, lparam, dparam, sparam);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   panel.Destroy(reason);
   ObjectsDeleteAll(0, lblStatus, -1, OBJ_LABEL);
   
   FreeAll();
}

//-----------------------------------------------
// Main                                         +
//-----------------------------------------------
void OnTick() {
  if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return; //取引NGの場合は抜ける

   Csymbol.Name(Symbol());
   Csymbol.RefreshRates();
   double ask = Csymbol.Ask();
   double bid = Csymbol.Bid();
   bool buyChkFlg = false;
   bool sellChkFlg = false;

   int isEntry = IsEntryOK();
   if(isEntry == 0) ObjectSetString(0, lblStatus, OBJPROP_TEXT, "稼働中");
   if(isEntry == 1) ObjectSetString(0, lblStatus, OBJPROP_TEXT, "スプレッド拡大");
   if(isEntry == 2) ObjectSetString(0, lblStatus, OBJPROP_TEXT, "NG時間帯");
   
   //パネルのチェックボックス
   if(panel.getBuyCheckBox()) {
      if(!HavePosition(POSITION_TYPE_BUY)) {
         panel.setBuyCheckBox(false);
      } else {
         buyChkFlg = true;
      }
   }
   if(panel.getSellCheckBox()) {
      if(!HavePosition(POSITION_TYPE_SELL)) {
         panel.setSellCheckBox(false);
      } else {
         sellChkFlg = true;
      }
   }

   for(int i=1; i<(int)MAGIC.Size(); i++) {
      //ナンピン処理
      if(!buyChkFlg && LowestPriceTicketNo[i] > 0 && nextBuyNanpinPrice[i] >= ask && nextBuyNanpinTime[i] <= TimeCurrent()) {
         trade.SetExpertMagicNumber(MAGIC[i]);
         double lots = getLots(LowestPriceTicketNo[i], nanpin_lots_bairitsu);
         if(!trade.Buy(lots)) printTradeError(trade);
      }
      if(!sellChkFlg && HighestPriceTicketNo[i] > 0 && nextSellNanpinPrice[i] <= bid && nextSellNanpinTime[i] <= TimeCurrent()) {
         trade.SetExpertMagicNumber(MAGIC[i]);
         double lots = getLots(HighestPriceTicketNo[i], nanpin_lots_bairitsu);
         if(!trade.Sell(lots)) printTradeError(trade);
      }

      //利確処理
      if(!buyChkFlg) TrailingStop(POSITION_TYPE_BUY, bid, i);      
      if(!sellChkFlg) TrailingStop(POSITION_TYPE_SELL, ask, i);

      //エントリー
      int sig_entry = EntrySignal(MAGIC[i]);
      if(!buyChkFlg && sig_entry>0 && IsNoEntry(POSITION_TYPE_BUY)) {
         trade.SetExpertMagicNumber(MAGIC[i]);
         if(!trade.Buy(NormalizeLot(Symbol(), EA_in_start_lots))) {
            printTradeError(trade);
         }
      }
      if(!sellChkFlg && sig_entry<0 && IsNoEntry(POSITION_TYPE_SELL)) {
         trade.SetExpertMagicNumber(MAGIC[i]);
         if(!trade.Sell(NormalizeLot(Symbol(), EA_in_start_lots))) {
            printTradeError(trade);
         }
      }
      
      //パネル表示
      getEAProfits();
      if(buyChkFlg) {
         if(panel.getLblProfits(POSITION_TYPE_BUY, i) != "") panel.setLblProfits(POSITION_TYPE_BUY, 0, i);
         if(panel.getLblNanpin(POSITION_TYPE_BUY, i) != "") panel.setLblNanpin(POSITION_TYPE_BUY, 0, i);
      } else {
         if(EABuyProfits[i] != 0.0) panel.setLblProfits(POSITION_TYPE_BUY,EABuyProfits[i], i);
         if(nextBuyNanpinPrice[i] != 0.0) panel.setLblNanpin(POSITION_TYPE_BUY, nextBuyNanpinPrice[i], i);
      }
      if(sellChkFlg) {
         if(panel.getLblProfits(POSITION_TYPE_BUY, i) != "") panel.setLblProfits(POSITION_TYPE_SELL, 0, i);
         if(panel.getLblNanpin(POSITION_TYPE_BUY, i) != "") panel.setLblNanpin(POSITION_TYPE_SELL, 0, i);
      } else {
         if(EASellProfits[i] != 0.0) panel.setLblProfits(POSITION_TYPE_SELL,EASellProfits[i], i);
         if(nextSellNanpinPrice[i] != 0.0) panel.setLblNanpin(POSITION_TYPE_SELL, nextSellNanpinPrice[i], i);
      }
   }
   
   if(buyChkFlg) {
      if(panel.getBuyCheckBoxText() == "OFF") panel.setBuyCheckBoxText("ON");
      if(EABuyProfits[0] != 0.0) panel.setLblProfits(POSITION_TYPE_BUY, EABuyProfits[0], 0);
      
      //Rescue modeの利確
      if(EABuyProfits[0] >= RescueBuyTP) CloseAllPositions(POSITION_TYPE_BUY, MAGIC[0]);
      
   } else {
      if(panel.getBuyCheckBoxText() == "ON") panel.setBuyCheckBoxText("OFF");
      if(panel.getLblProfits(POSITION_TYPE_BUY, 0) != "") panel.setLblProfits(POSITION_TYPE_BUY, 0, 0);
   }
   
   if(sellChkFlg) {
      if(panel.getSellCheckBoxText() == "OFF") panel.setSellCheckBoxText("ON");
      if(EASellProfits[0] != 0.0) panel.setLblProfits(POSITION_TYPE_SELL, EASellProfits[0], 0);
      
      //Rescue modeの利確
      if(EASellProfits[0] >= RescueSellTP) CloseAllPositions(POSITION_TYPE_SELL, MAGIC[0]);
      
   } else {
      if(panel.getSellCheckBoxText() == "ON") panel.setSellCheckBoxText("OFF");
      if(panel.getLblProfits(POSITION_TYPE_BUY, 0) != "") panel.setLblProfits(POSITION_TYPE_SELL, 0, 0);      
   }
   
   ChartRedraw(0);
}

//数値にコンマをつける、digは小数点以下の桁数
string addcomma(double inputdata, int dig)
{
  string returnstr = DoubleToString(inputdata,dig);
  int length;
  int noofcomma;
  int firstcomma;
  
  length = StringLen(DoubleToString(MathFloor(inputdata),0));
    
  if (inputdata >= 0) noofcomma = (int)MathFloor((length - 1) / 3); //inputdataが正の場合
  else noofcomma = (int)MathFloor((length - 2) / 3); //inputdataが負(マイナス)の場合
  if (noofcomma == 0) return (returnstr);

  firstcomma = length - noofcomma * 3; //左から数えて最初のコンマの位置
  if (firstcomma == 0) firstcomma = 3; //

  for (int i = 0; i < noofcomma; i++){
    StringConcatenate(returnstr, StringSubstr(returnstr, 0, firstcomma + i * 4),",",StringSubstr(returnstr, firstcomma + i * 4));
  }
  
  return (returnstr);
}


//日本時間に変換
//acnは、account_company_nameの略で、口座会社の名前
//dayを指定するとその時の日本時間
//dayを指定しないと現時間の日本時間を返す
datetime convertToJapanTime(string acn, datetime day = 0) {
/*
夏時間
3月の最終日曜日～10月の最終日曜日まで
例）FX通貨ペアの取引時間
日本時間 6:05～翌 5:50
*/
    if(StringFind(acn, "Phillip") >=0) return TimeCurrent();
    MqlDateTime cjtm; // 時間構造体
    day = day == 0 ? TimeCurrent() : day; // 対象サーバ時間
    datetime time_summer = 21600; // ６時間
    datetime time_winter = 25200; // ７時間
    
    //FXGTの口座なら
    if(StringFind(acn, "GT") >=0) return day+time_summer;
//    if(StringFind(AccountInfoString(ACCOUNT_COMPANY), "Tradexfin") >=0) return day+time_winter;
    
    int target_dow = 0; // 日曜日
    int start_st_n = 2; // 夏時間開始3月第2週
    int end_st_n = 1; // 夏時間終了11月第1週
    TimeToStruct(day, cjtm); // 構造体の変数に変換
    string year = (string)cjtm.year; // 対象年
// 対象年の3月最終日と11月最終日の曜日
    TimeToStruct(StringToTime(year + ".04.01 00:00:00") - 1, cjtm);
    int fdo_mar_day = cjtm.day;
    int fdo_mar = cjtm.day_of_week;
    
    TimeToStruct(StringToTime(year + ".11.01 00:00:00")-1, cjtm);
    int fdo_oct_day = cjtm.day;
    int fdo_oct = cjtm.day_of_week;
    
// 3月最終日曜日
//    int start_st_day = (target_dow < fdo_mar ? target_dow + 7 : target_dow)
//                       - fdo_mar + 7 * start_st_n - 6;
// 3月の最終日曜日
    int start_st_day = fdo_mar_day - fdo_mar;
   
// 10月最終日曜日
//    int end_st_day = (target_dow < fdo_nov ? target_dow + 7 : target_dow)
//                     - fdo_nov + 7 * end_st_n - 6;

    int end_st_day = fdo_oct_day - fdo_oct;
    
// 対象年の夏時間開始日と終了日を確定
    datetime start_st = StringToTime(year + ".03." + (string)start_st_day);
    datetime end_st = StringToTime(year + ".10." + (string)end_st_day);
// 日本時間を返す
    return day += start_st <= day && day <= end_st
                  ? time_summer : time_winter;
}

int obj_count = 0;
void OnTimer() {
   panel.setLblJPNTime(TimeToString(convertToJapanTime(account_company_name), TIME_DATE| TIME_SECONDS));

   //オープンポジションが無い場合
   if(PositionsTotal() == 0)
      FreeAll();

   //パネルを前面に
   int now = ObjectsTotal(0,0,-1);
   if(now != obj_count)
   {
      obj_count = now;
      BringPanelToFront();
   }
}

void BringPanelToFront()
{
   // 一旦非表示
   panel.Hide();

   // 再表示
   panel.Show();

   // 再描画
   ChartRedraw();
}


//+------------------------------------------------------------------+
//| 新規ポジションをとったらposMapへ追加する                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // 取引履歴（Deal）が追加されたタイミングを拾うのが分かりやすい
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   // Deal ticket
   ulong deal_ticket = (ulong)trans.deal;
   if(deal_ticket == 0)
      return;

   // Deal情報を取得
   if(!HistoryDealSelect(deal_ticket))
      return;

   long   deal_type   = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);     // BUY/SELLなど
   long   entry       = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);    // IN/OUT/INOUT
   long   magic       = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);    // Magic
   ulong  pos_id      = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID); // Position ID
   double volume      = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
   datetime entry_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME); //Entry Time  
   double price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE); //Entry Price 

   // エントリー（新規建て）だけ欲しいなら DEAL_ENTRY_IN を絞る
   if(entry != DEAL_ENTRY_IN)
      return;

   // BUY/SELL以外（手数料、スワップ等）を除外したい
   if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
      return;
      
   CPosInfo *info = new CPosInfo;
   info.pos_type = (ENUM_POSITION_TYPE)deal_type;
   info.entry_price = price;
   info.entry_time = entry_time;
   info.magic = magic;
   info.volume = volume;
   
   posMap.Add(pos_id, info);
   
   nextNanpinPriceTime(info.pos_type, ArrayBsearch(MAGIC, magic));
   getWeightAverage();
   
}

void DumpAll()
{
   ulong   keys[];
   CPosInfo *values[];

   int n = posMap.CopyTo(keys, values, 0);  // 全件コピーして列挙

   for(int i=0; i<n; i++)
   {
      CPosInfo *p = values[i];
      Print("Ticket=",keys[i],
            " Entry=",p.pos_type,
            " Price=",p.entry_price,
            " entry_time=",p.entry_time,
            " magic=",p.magic,
            " volume=",p.volume);
   }
}

void FreeAll()
{
   ulong keys[];
   CPosInfo *values[];

   int n = posMap.CopyTo(keys, values, 0);
   for(int i=0; i<n; i++)
      delete values[i];

   posMap.Clear();
   
   for(int i=0; i<(int)MAGIC.Size(); i++) {
      nextBuyNanpinPrice[i] = 0.0;
      nextSellNanpinPrice[i] = 0.0;
      nextBuyNanpinTime[i] = TimeCurrent();
      nextSellNanpinTime[i] = TimeCurrent();
      LowestPriceTicketNo[i] = 0;
      HighestPriceTicketNo[i] = 0;
      weightAverageBuy[i] = 0.0;
      weightAverageSell[i] = 0.0;
      EABuyProfits[i] = 0.0;
      EASellProfits[i] = 0.0;
      trailStart_buy_price[i] = 0.0;
      trailStart_sell_price[i] = 0.0;
      trail_buy_price[i] = 0.0;
      trail_sell_price[i] = 0.0;
      ObjectsDeleteAll(0, prefix[i], -1, OBJ_HLINE);
   }
}

void getAllPositionInfo() {

   int total = PositionsTotal();

   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;

      // ★最重要：まず選択
      if(!PositionSelectByTicket(ticket))
         continue;
         
      long   type     = PositionGetInteger(POSITION_TYPE);
      double volume   = PositionGetDouble(POSITION_VOLUME);
      double price    = PositionGetDouble(POSITION_PRICE_OPEN);

      // ---- 管理系 ----
      long   magic    = PositionGetInteger(POSITION_MAGIC);
      long   time     = PositionGetInteger(POSITION_TIME);

      CPosInfo *info = new CPosInfo;
      info.pos_type = (ENUM_POSITION_TYPE)type;
      info.entry_price = price;
      info.entry_time = (datetime)time;
      info.magic = magic;
      info.volume = volume;
      
      posMap.Add(ticket, info);
            
   }
}

//ポジション一括クローズ
void CloseAllPositions(ENUM_POSITION_TYPE pos_type, long magic) {

   ulong   keys[];
   CPosInfo *values[];
   int n = posMap.CopyTo(keys, values, 0);  // 全件コピーして列挙
   if(n==0) return;

   double balance1 = AccountInfoDouble(ACCOUNT_BALANCE);
   for(int i=0; i<n; i++)
   {
      CPosInfo *p = values[i];
      if(p.pos_type != pos_type) continue;
      if(p.magic == magic || magic < 0) {
         if(!trade.PositionClose(keys[i])) printTradeError(trade);
         DeleteHashMap(keys[i]);
      }
   }

   int magic_idx = ArrayBsearch(MAGIC, magic);
   if(pos_type == POSITION_TYPE_BUY) {
      LowestPriceTicketNo[magic_idx] = 0;
      nextBuyNanpinPrice[magic_idx] = 0.0;
      nextBuyNanpinTime[magic_idx] = TimeCurrent();
      weightAverageBuy[magic_idx] = 0.0;
      EABuyProfits[magic_idx] = 0.0;
      panel.setLblNanpin(POSITION_TYPE_BUY, 0, magic_idx);
      panel.setLblProfits(POSITION_TYPE_BUY, 0, magic_idx);
      trailStart_buy_price[magic_idx] = 0.0;
      trail_buy_price[magic_idx] = 0.0;
      ObjectsDeleteAll(0, prefix[magic_idx]+"_buy_start", -1, OBJ_HLINE);
      ObjectsDeleteAll(0, prefix[magic_idx]+"_buy_trail", -1, OBJ_HLINE);
   } else {
      HighestPriceTicketNo[magic_idx] = 0;
      nextSellNanpinPrice[magic_idx] = 0.0;
      nextSellNanpinTime[magic_idx] = TimeCurrent();
      weightAverageSell[magic_idx] = 0.0;
      EASellProfits[magic_idx] = 0.0;
      panel.setLblNanpin(POSITION_TYPE_SELL, 0, magic_idx);
      panel.setLblProfits(POSITION_TYPE_SELL, 0, magic_idx);
      trailStart_sell_price[magic_idx] = 0.0;
      trail_sell_price[magic_idx] = 0.0;
      ObjectsDeleteAll(0, prefix[magic_idx]+"_sell_start", -1, OBJ_HLINE);
      ObjectsDeleteAll(0, prefix[magic_idx]+"_sell_trail", -1, OBJ_HLINE);
   }
   
   if(pos_type == POSITION_TYPE_BUY) {
      if(panel.getBuyCheckBox()) {
         panel.setBuyCheckBox(false);
         panel.setBuyCheckBoxText("OFF");
      }
   } else {
      if(panel.getSellCheckBox()) {
         panel.setSellCheckBox(false);
         panel.setSellCheckBoxText("OFF");
      }
   }
      
   double balance2 = AccountInfoDouble(ACCOUNT_BALANCE);
}

/** トレード関数がエラーになったときのエラー出力 */
void printTradeError(const CTrade &trade1) {
    uint code = trade1.ResultRetcode();
    string desc = trade1.ResultRetcodeDescription();
    printf("ERROR(%u): %s", code, desc);
}

//+------------------------------------------------------------------+
//| 正規化されたロットを返す                                            |
//+------------------------------------------------------------------+
double NormalizeLot(const string symbol_name, double order_lots) {
   double ln = 0.0;
   double ml=SymbolInfoDouble(symbol_name,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(symbol_name,SYMBOL_VOLUME_MAX);
//   double ln=NormalizeDouble(order_lots,int(ceil(fabs(log(ml)/log(10)))));
   int comma = StringFind((string)SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP),".");
   int end = StringLen((string)SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP));

   if(StringFind(account_company_name, "Phillip") >=0) { //Phillip証券の場合
      ln=NormalizeDouble(order_lots, 0);
   } else {
      ln=NormalizeDouble(order_lots, end-comma-1);
   }
   return(ln<ml ?ml : ln>mx ?mx : ln);
}


ulong getLowestPriceTicket(ENUM_POSITION_TYPE pos_type, long magic) {
   //オープンポジションのpos_typeで指定されたポジションのオープンプライス最安値のticketを返す。
   //ポジションがない場合は-1を返す。
   ulong lowest_ticket = 0;
   double low_price = 10000000000.0; //毎回最安値のオープンプライスをさがしている。

   ulong   keys[];
   CPosInfo *values[];
   int n = posMap.CopyTo(keys, values, 0);  // 全件コピーして列挙

   for(int i=0; i<n; i++)
   {
      CPosInfo *p = values[i];
      if(p.pos_type != pos_type) continue;
      if(p.magic != magic) continue;
      
      if(low_price > p.entry_price) {
         low_price = p.entry_price;
         lowest_ticket = keys[i];
      }      
   }

   return lowest_ticket;
}

ulong getHighestPriceTicket(ENUM_POSITION_TYPE pos_type, long magic) {
   //オープンポジションのtypeで指定されたポジションのオープンプライス最高値のticketを返す。
   //ポジションがない場合は-1を返す。
   ulong highest_ticket = 0;
   double high_price = 0.0; //毎回最高値のオープンプライスをさがしている。

   ulong   keys[];
   CPosInfo *values[];
   int n = posMap.CopyTo(keys, values, 0);  // 全件コピーして列挙

   for(int i=0; i<n; i++)
   {
      CPosInfo *p = values[i];
      if(p.pos_type != pos_type) continue;
      if(p.magic != magic) continue;
      
      if(high_price < p.entry_price) {
         high_price = p.entry_price;
         highest_ticket = keys[i];
      }      
   }   
   return highest_ticket;
}

void nextNanpinPriceTime(ENUM_POSITION_TYPE pos_type, int magic_idx) {
   CPosInfo *p;
   
   getNanpinDiff();
       
   double nanpin_diff = NormalizeDouble(nanpin_haba*10*Point(), Digits());
   long nanpin_time_diff = 60*nanpin_late_time;
   
   if(pos_type == POSITION_TYPE_BUY) {
      nextBuyNanpinPrice[magic_idx] = 0.0;
      LowestPriceTicketNo[magic_idx] = getLowestPriceTicket(POSITION_TYPE_BUY, MAGIC[magic_idx]);
      if(posMap.TryGetValue(LowestPriceTicketNo[magic_idx], p)) {
         nextBuyNanpinPrice[magic_idx] = NormalizeDouble( p.entry_price - nanpin_diff, Digits());
         nextBuyNanpinTime[magic_idx] = p.entry_time + (datetime)nanpin_time_diff;
         panel.setLblNanpin(POSITION_TYPE_BUY, nextBuyNanpinPrice[magic_idx], magic_idx);
      }
   } else {
      nextSellNanpinPrice[magic_idx] = 0.0;
      HighestPriceTicketNo[magic_idx] = getHighestPriceTicket(POSITION_TYPE_SELL, MAGIC[magic_idx]);
      if(posMap.TryGetValue(HighestPriceTicketNo[magic_idx], p)) {
         nextSellNanpinPrice[magic_idx] = NormalizeDouble( p.entry_price + nanpin_diff, Digits());
         nextSellNanpinTime[magic_idx] = p.entry_time + (datetime)nanpin_time_diff;
         panel.setLblNanpin(POSITION_TYPE_SELL, nextSellNanpinPrice[magic_idx], magic_idx);
      }
   }
}

double getLots(ulong ticket, double lots_bairitu) {
   CPosInfo *p;
   if(!posMap.TryGetValue(ticket, p)) return NULL;
   
   return NormalizeLot(Symbol(), p.volume*lots_bairitu);
}

void DeleteHashMap(const ulong key) {
   CPosInfo *info = NULL;
   if(posMap.TryGetValue(key, info)) {
      delete info;
      posMap.Remove(key);
   }
}

void getWeightAverage() {
   ulong   keys[];
   CPosInfo *values[];
   int n = posMap.CopyTo(keys, values, 0);  // 全件コピーして列挙
   double volumesBuy[MAGIC.Size()];
   double volumesSell[MAGIC.Size()];
   double pricexvolumesBuy[MAGIC.Size()];
   double pricexvolumesSell[MAGIC.Size()];
   int magic_idx;
   
   for(int i=0; i<(int)MAGIC.Size(); i++) {
      volumesBuy[i] = 0;
      volumesSell[i] = 0;
      pricexvolumesBuy[i] = 0;
      pricexvolumesSell[i] = 0;
   }

   for(int i=0; i<n; i++)
   {
      CPosInfo *p = values[i];
      magic_idx = ArrayBsearch(MAGIC,p.magic);
      if(p.pos_type == POSITION_TYPE_BUY) {
         volumesBuy[magic_idx] += p.volume;
         pricexvolumesBuy[magic_idx] += p.entry_price * p.volume;
      } else {
         volumesSell[magic_idx] += p.volume;
         pricexvolumesSell[magic_idx] += p.entry_price * p.volume;
      }
   }
   
   double rescueVolumesBuy = 0.0;
   double rescuePriceVolumesBuy = 0.0;
   double rescueVolumesSell = 0.0;
   double rescuePriceVolumesSell = 0.0;
   
   for(int i=1; i<(int)MAGIC.Size(); i++) {
      rescueVolumesBuy += volumesBuy[i];
      rescuePriceVolumesBuy += pricexvolumesBuy[i];

      rescueVolumesSell += volumesSell[i];
      rescuePriceVolumesSell += pricexvolumesSell[i];

      if(volumesBuy[i] != 0.0) {
         weightAverageBuy[i] = NormalizeDouble(pricexvolumesBuy[i]/volumesBuy[i], Digits());
         trailStart_buy_price[i] = weightAverageBuy[i] + TrailStart*10*Point();
      }
      if(volumesSell[i] != 0.0) {
         weightAverageSell[i] = NormalizeDouble(pricexvolumesSell[i]/volumesSell[i], Digits());
         trailStart_sell_price[i] = weightAverageSell[i] - TrailStart*10*Point();
      }
   }
   
   if(rescueVolumesBuy !=  0.0 ) weightAverageBuy[0] = NormalizeDouble(rescuePriceVolumesBuy/rescueVolumesBuy,Digits());
   if(rescuePriceVolumesSell != 0.0 ) weightAverageSell[0] = NormalizeDouble(rescuePriceVolumesSell/rescueVolumesSell, Digits());
   
}

int IsEntryOK() {
   //戻り値：
   // 0 EntryOK, 0以外はEntryNG
   // 1 スプレッド拡大の為、エントリーNG
   // 2 曜日と時間帯の為、エントリーNG
   int ret = 0;
   
   Csymbol.Name(Symbol());
   Csymbol.RefreshRates();

  //スプレッド拡大   
   if((Csymbol.Ask() - Csymbol.Bid()) >= SpreadFilter*10*Point()) return(1);
   
   //平日時間帯チェック
   datetime time = convertToJapanTime(account_company_name); //日本時刻へ変更
   MqlDateTime mqlDate;
   TimeToStruct(time, mqlDate);
   
   if(in_entry == 0) { //稼働する（時間指定）
      datetime sdatetime = StringToTime((string)mqlDate.year+"." + (string)mqlDate.mon + "." + (string)mqlDate.day + " " + in_stime);
      datetime edatetime = StringToTime((string)mqlDate.year+"." + (string)mqlDate.mon + "." + (string)mqlDate.day + " " + in_etime);

      if(!(time >= sdatetime && time <= edatetime)) return(2);
      
   } else if (in_entry == 1) { //稼働しない
      return(2);
   }// entry == 2は、フル稼働なのでなにもしない
      
   return ret;
}

//エントリーロジック
int EntrySignal(long magic) {
   // 戻値 0 シグナル無し
   // 　　　　1 ロング
   //     -1 ショート
   int ret = 0;
   //MAGIC[0]: Rescue
   //MAGIC[1]: NonEA
   //MAGIC[2]: EA1
   //MAGIC[3]: EA2
   //MAGIC[4]: EA3
   
   if(magic==MAGIC[0] || magic == MAGIC[1])  return(ret);

   Csymbol.Name(Symbol());
   Csymbol.RefreshRates();

   if(magic == MAGIC[2]) {
      CiRsiEA1.Refresh();
      CiBandsEA1.Refresh();
      // RSI < 30 && LowerBands > Bid() ならロング
      if( CiRsiEA1.Main(0) < 30 && CiBandsEA1.Lower(0) > Csymbol.Bid()) {
         Print("EntrySignal=Long");
         return(1);
      }
      //  RSI > 70 && UpperBand < Bid() ならショート
      if(CiRsiEA1.Main(0) > 70 && CiBandsEA1.Upper(0) < Csymbol.Bid()) {
         Print("EntrySignal=Short");
         return(-1);
      }
   }
   
   if(magic == MAGIC[2]) {
   }
   if(magic == MAGIC[3]) {
   }
   
   return(ret);
}

bool IsNoEntry(ENUM_POSITION_TYPE pos_type) {
   //同じ方向にポジションがあればfalse
   //ない場合は、true
   ulong   keys[];
   CPosInfo *values[];

   int n = posMap.CopyTo(keys, values, 0);  // 全件コピーして列挙

   for(int i=0; i<n; i++)
   {
      CPosInfo *p = values[i];
      if(pos_type == p.pos_type) return(false);
   }
   
   return(true);
}

void getEAProfits() {
   ulong   keys[];
   CPosInfo *values[];

   for(int i=0; i<(int)MAGIC.Size(); i++) {
      EABuyProfits[i] = 0.0;
      EASellProfits[i] = 0.0;
   }

   int n = posMap.CopyTo(keys, values, 0);  // 全件コピーして列挙

   for(int i=0; i<n; i++)
   {
      if(!PositionSelectByTicket(keys[i])) return;
      
      CPosInfo *p = values[i];
      if(p.pos_type == POSITION_TYPE_BUY) {
         EABuyProfits[ArrayBsearch(MAGIC, p.magic)] += (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP));
         EABuyProfits[0] += EABuyProfits[ArrayBsearch(MAGIC, p.magic)];
      } else {
         EASellProfits[ArrayBsearch(MAGIC, p.magic)] += (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP));
         EASellProfits[0] +=EASellProfits[ArrayBsearch(MAGIC, p.magic)];
      }
   }
}

void getNanpinDiff() {
   datetime now = convertToJapanTime(account_company_name);
   MqlDateTime mqlNow;
   TimeToStruct(now, mqlNow);
   
   double nanpin_hosei = 1; //価格の補正
   if(StringFind(account_company_name, "OANDA") >=0) nanpin_hosei = 10.0; //OANDA証券の場合
   nanpin_haba =nanpin_base_diff*nanpin_hosei; //価格のナンピン差
   
   nanpin_late_time = nanpin_base_time; //時間のナンピン差
   
   if(mqlNow.hour >= 6 && mqlNow.hour < 16) { //東京時間
      if(n_type == offense) {
         nanpin_haba = (nanpin_base_diff-2)*nanpin_hosei;
         nanpin_late_time = nanpin_base_time;
      } else if(n_type == balance) {
         nanpin_haba = (nanpin_base_diff-2)*nanpin_hosei;
         nanpin_late_time = nanpin_base_time;
      } else if (n_type == defense) {
         nanpin_haba = nanpin_base_diff*nanpin_hosei;
         nanpin_late_time = nanpin_base_time;
      } else if (n_type == noninterval) {
         nanpin_haba = nanpin_base_diff*nanpin_hosei;
         nanpin_late_time = 0;
      }
   } else if(mqlNow.hour >= 16 && mqlNow.hour < 21) { //ロンドン時間
      if(n_type == offense) {
         nanpin_haba = (nanpin_base_diff-2)*nanpin_hosei;
         nanpin_late_time = nanpin_base_time;
      } else if(n_type == balance) {
         nanpin_haba = nanpin_base_diff*nanpin_hosei;
         nanpin_late_time = nanpin_base_time;
      } else if (n_type == defense) {
         nanpin_haba = (nanpin_base_diff+3)*nanpin_hosei;
         nanpin_late_time = nanpin_base_time;
      } else if (n_type == noninterval) {
         nanpin_haba = nanpin_base_diff*nanpin_hosei;
         nanpin_late_time = 0;
      }
   } else { //NY時間
      if(n_type == offense) {
         nanpin_haba = nanpin_base_diff*nanpin_hosei;
         nanpin_late_time = nanpin_base_time+2;
      } else if(n_type == balance) {
         nanpin_haba = (nanpin_base_diff+3)*nanpin_hosei;
         nanpin_late_time = nanpin_base_time+3;
      } else if (n_type == defense) {
         nanpin_haba = (nanpin_base_diff+5)*nanpin_hosei;
         nanpin_late_time = nanpin_base_time+3;
      } else if (n_type == noninterval) {
         nanpin_haba = nanpin_base_diff*nanpin_hosei;
         nanpin_late_time = 0;
      }
   }
}

void TrailingStop(ENUM_POSITION_TYPE pos_type, double price, int magic_idx) {
   double trail_interval_diff = TrailInterval*10*Point();

   if(weightAverageBuy[magic_idx] > 0 && pos_type == POSITION_TYPE_BUY) {
      //トレイル開始ライン
      if(ObjectFind(0, prefix[magic_idx]+"_buy_start") < 0) {
         CreateHBLine(prefix[magic_idx]+"_buy_start", trailStart_buy_price[magic_idx], clr_buy[magic_idx], STYLE_DASHDOT);
      } else {
         if(trailStart_buy_price[magic_idx] != ObjectGetDouble(0, prefix[magic_idx]+"_buy_start",OBJPROP_PRICE)) MoveHBLine(prefix[magic_idx]+"_buy_start", trailStart_buy_price[magic_idx]);
      }
      //トレイル開始
      if(trail_buy_price[magic_idx] == 0.0 && price >= trailStart_buy_price[magic_idx]) {
         trail_buy_price[magic_idx] = price - trail_interval_diff;
      }
      if(trail_buy_price[magic_idx] > 0) {
         if(ObjectFind(0, prefix[magic_idx]+"_buy_start") >= 0) ObjectsDeleteAll(0, prefix[magic_idx]+"_buy_start", -1, OBJ_HLINE);
         if(ObjectFind(0, prefix[magic_idx]+"_buy_trail") < 0) {
            CreateHBLine(prefix[magic_idx]+"_buy_trail", trail_buy_price[magic_idx], clr_buy[magic_idx], STYLE_DASHDOTDOT);
         } else {
            MoveHBLine(prefix[magic_idx]+"_buy_trail", trail_buy_price[magic_idx]);
         }
         //利確
         if(price <= trail_buy_price[magic_idx] && EABuyProfits[magic_idx] > 0) {
            CloseAllPositions(POSITION_TYPE_BUY, MAGIC[magic_idx]);
            return;
         }
         //トレイル価格の更新
         if((price - trail_buy_price[magic_idx]) > trail_interval_diff) {
            trail_buy_price[magic_idx] = price - trail_interval_diff;
         }
      }
   }
   if(weightAverageSell[magic_idx] > 0 && pos_type == POSITION_TYPE_SELL) {
      //トレイル開始ライン
      if(ObjectFind(0, prefix[magic_idx]+"_sell_start") < 0) {
         CreateHBLine(prefix[magic_idx]+"_sell_start", trailStart_sell_price[magic_idx], clr_sell[magic_idx], STYLE_DASHDOT);
      } else {
         if(trailStart_sell_price[magic_idx] != ObjectGetDouble(0, prefix[magic_idx]+"_sell_start",OBJPROP_PRICE)) MoveHBLine(prefix[magic_idx]+"_sell_start", trailStart_sell_price[magic_idx]);
      }
      //トレイル開始
      if(trail_sell_price[magic_idx] == 0.0 && price <= trailStart_sell_price[magic_idx]) {
         trail_sell_price[magic_idx] = price + trail_interval_diff;
      }
      if(trail_sell_price[magic_idx] > 0) {
         if(ObjectFind(0, prefix[magic_idx]+"_sell_start") >= 0) ObjectsDeleteAll(0, prefix[magic_idx]+"_sell_start", -1, OBJ_HLINE);
         if(ObjectFind(0, prefix[magic_idx]+"_sell_trail") < 0) {
            CreateHBLine(prefix[magic_idx]+"_sell_trail", trail_sell_price[magic_idx], clr_sell[magic_idx], STYLE_DASHDOTDOT);
         } else {
            MoveHBLine(prefix[magic_idx]+"_sell_trail", trail_sell_price[magic_idx]);
         }
         if(price >= trail_sell_price[magic_idx] && EASellProfits[magic_idx] > 0) {
            CloseAllPositions(POSITION_TYPE_SELL, MAGIC[magic_idx]);
            return;
         }
         //トレイル価格の更新
         if((trail_sell_price[magic_idx] - price) > trail_interval_diff) {
            trail_sell_price[magic_idx] = price + trail_interval_diff;
         }
      }
   }
}

//チャート上に水平線を引く
bool CreateHBLine(string lineName, double price, color clr, ENUM_LINE_STYLE style = STYLE_SOLID) {

   if(!ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, price)) {
      Print(__FUNCTION__,
          ": failed to create a horizontal line! Error code = ",GetLastError());
   } else {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, style);
      return(true);
   }
   return(false);
}

//チャート上の水平線の移動
bool MoveHBLine(string lineName, double price) {
   if(!ObjectMove(0, lineName, 0, 0, price)) {
      Print(__FUNCTION__,
         ": failed to move the horizontal line! Error code = ",GetLastError());
      return(false);
   }
   return(true);
}

bool HavePosition(ENUM_POSITION_TYPE buyorsell) {
   ulong   keys[];
   CPosInfo *values[];
   int n = posMap.CopyTo(keys, values, 0);  // 全件コピーして列挙
   if(n==0) return false;

   for(int i=0; i<n; i++)
   {
      CPosInfo *p = values[i];
      if(p.pos_type == buyorsell) return true;
   }
   
   return false;
}

/*
void CleanPosition() {
   ulong   keys[];
   CPosInfo *values[];
   int n = posMap.CopyTo(keys, values, 0);  // 全件コピーして列挙
   if(n==0) return;

   for(int i=0; i<n; i++)
   {
      CPosInfo *p = values[i];
      if(p.pos_type != pos_type) continue;
      if(p.magic == magic || magic < 0) {
         if(!trade.PositionClose(keys[i])) printTradeError(trade);
         DeleteHashMap(keys[i]);
      }
   }
}
*/