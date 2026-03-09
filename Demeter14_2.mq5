//Demeter14_1
//アイディア
//・利確時に早くできるように、Ticketをメモリに入れておく
//・損益の値(金額)もメモリにいれておく
//・損益の値をベースに利確する
//・他のEAがエントリーしている場合は、同じ方向にはエントリーしない

//Demeter14_2 2026.03.09
//連想配列から構造体配列にポジション管理を変更

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

//MAGICの配列数を変えた時は、パネルを落としてからコンパイルしないとパネルがフリーズします。
long MAGIC[] = {-1, 0, 10, 20}; //最初は-1とするRescueモード
string prefix[] = {"Rescue", "NonEA", "EA1", "EA2"};
color clr_buy[] = {clrBlue, clrAqua, clrBlueViolet, clrDarkBlue};
color clr_sell[] = {clrRed, clrPink, clrDarkOrange, clrDarkRed};
input bool EA1 = true; //EA1の稼働フラグ
input bool EA2 = true; //EA2の稼働フラグ
bool ForceCloseBuy[MAGIC.Size()];
bool ForceCloseSell[MAGIC.Size()];

//各ポジションの情報の構造体
struct PosCache
{
   ulong ticket;
   int magic_idx;
   ENUM_POSITION_TYPE type;
   double volume;
   double price_open;
   double profit;
};

PosCache g_positions[];
int g_pos_count = 0;

int    BuyCount[MAGIC.Size()];
int    SellCount[MAGIC.Size()];
double BuyLots[MAGIC.Size()];
double SellLots[MAGIC.Size()];
double BuyProfit[MAGIC.Size()];
double SellProfit[MAGIC.Size()];
double BuyPriceVolumeSum[MAGIC.Size()];
double SellPriceVolumeSum[MAGIC.Size()];
double BuyAvgPrice[MAGIC.Size()];
double SellAvgPrice[MAGIC.Size()];
ulong  LowestBuyTicket[MAGIC.Size()];
ulong  HighestSellTicket[MAGIC.Size()];
double LowestBuyPrice[MAGIC.Size()];
double HighestSellPrice[MAGIC.Size()];

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
input double RescueBuyTP = 500; //レスキューモードBuy利確価格(0は利確しない)
input double RescueSellTP = 500; //レスキューモードSell利確価格(0は利確しない)

input double TrailStart = 10.0; //トレール開始値
input double TrailInterval = 4.0; //トレール幅
input double SpreadFilter = 4.0; //スプレッドフィルター
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

double nanpin_haba = 15; //ナンピンの幅(pips)
long nanpin_late_time = 5; //ナンピンの遅延時間（分）

string usdjpy_name = ""; //USDJPYの名前

//EA1用パラメータ RSIとボリバン
CiRSI CiRsiEA1;
CiBands CiBandsEA1;
ENUM_TIMEFRAMES RSITimeFrameEA1 = PERIOD_M1; //Long用のRSIのタイムフレーム
ENUM_TIMEFRAMES BandsTimeFrameEA1 = PERIOD_M1; //Long用のBBのタイムフレーム
int RSIPeriodEA1 = 14; //Long用のRSIのPeriod
int BandsPeriodEA1 = 20; //Long用のBBのPeriod
double BandsSigmaEA1 = 2.0; //Long用のBBのシグマ
CiADX CiADXEA1;
ENUM_TIMEFRAMES ADXTimeFrameEA1 = PERIOD_M1;
int ADXPeriodEA1 = 14;

//For EA2
CiMA CiMAEA2_200; //SMA200 Close
ENUM_TIMEFRAMES MATimeFrameEA2 = PERIOD_M1;
CiMA CiMAEA2Low_55; //EMA55 Low
CiMA CiMAEA2High_55; //EMA55 High

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
   
   //EAパラメータが変更されてても何もしない。
   if(UninitializeReason() == REASON_PARAMETERS) return(INIT_SUCCEEDED);
   trade.SetDeviationInPoints(50);
   trade.SetAsyncMode(false);
   ChartSetInteger(0, CHART_FOREGROUND, false);

   //USDJPYの名前   
   if(StringFind(account_company_name, "GT") >=0 && contract_size == 1.0) {
      //FXGTなら
      usdjpy_name = "USDJPYm";
   } else if(StringFind(account_company_name, "Tradexfin") >=0 && contract_size == 1.0) {
      //XM Tradingなら
      usdjpy_name = "USDJPYmicro";
   } else if(StringFind(account_company_name, "Phillip") >=0) {
      //Phillip証券なら
      usdjpy_name = "USDJPY.ps01";
   } else if(StringFind(account_company_name, "HF") >=0 && contract_size == 1.0) {
      usdjpy_name = "USDJPYc";
   } else {
      usdjpy_name = "USDJPY";
   }
                     
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
      ResetBuyState(i);
      ResetSellState(i);
   }

   //For EA1
   CiRsiEA1.Create(Symbol(), RSITimeFrameEA1, RSIPeriodEA1, PRICE_CLOSE);
   CiBandsEA1.Create(Symbol(), BandsTimeFrameEA1, BandsPeriodEA1, 0, BandsSigmaEA1, PRICE_CLOSE);
   CiADXEA1.Create(Symbol(), ADXTimeFrameEA1, ADXPeriodEA1);
   
   //For EA2
   CiMAEA2_200.Create(Symbol(), MATimeFrameEA2, 200, 0, MODE_SMA, PRICE_CLOSE);
   CiMAEA2Low_55.Create(Symbol(), MATimeFrameEA2, 55, 0, MODE_EMA, PRICE_LOW);
   CiMAEA2High_55.Create(Symbol(), MATimeFrameEA2, 55, 0, MODE_EMA, PRICE_HIGH);

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
   //チャート変更事に何もしない。
   if(UninitializeReason() == REASON_CHARTCHANGE) return;
   //EAパラメータが変更されてても何もしない。
   if(UninitializeReason() == REASON_PARAMETERS) return;
   
   EventKillTimer();
   panel.Destroy(reason);
   ObjectsDeleteAll(0, lblStatus, -1, OBJ_LABEL);

}

//-----------------------------------------------
// Main                                         +
//-----------------------------------------------
void OnTick() {

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
      
   //クローズポジションがあればクローズする
   ProcessForceClose();
   
   //パネルのチェックボックス
   if(panel.getBuyCheckBox()) {
/*      if(BuyPositions[0] == 0) {
         panel.setBuyCheckBox(false);
      } else {
         buyChkFlg = true;
      }
*/
   }
   if(panel.getSellCheckBox()) {
/*      if(SellPositions[0] == 0) {
         panel.setSellCheckBox(false);
      } else {
         sellChkFlg = true;
      }
*/
   }

   //水平線処理
   if(buyChkFlg) {
   } else {
      ObjectsDeleteAll(0, prefix[0]+"_buy", -1, OBJ_HLINE);   
   }
   
   if(sellChkFlg) {
   } else {
      ObjectsDeleteAll(0, prefix[0]+"_sell", -1, OBJ_HLINE);
   }

   for(int i=1; i<(int)MAGIC.Size(); i++) {
      //ナンピン処理

      //利確処理

      //エントリー
      int sig_entry = EntrySignal(MAGIC[i]);
/*      if(!buyChkFlg && isEntry == 0 && sig_entry>0 && BuyPositions[0] == 0) {
      }
      if(!sellChkFlg && isEntry == 0 && sig_entry<0 && SellPositions[0] == 0) {
      }
*/      
      //パネル表示
      if(buyChkFlg) {
         if(panel.getLblProfits(POSITION_TYPE_BUY, i) != "") panel.setLblProfits(POSITION_TYPE_BUY, 0, i);
         if(panel.getLblNanpin(POSITION_TYPE_BUY, i) != "") panel.setLblNanpin(POSITION_TYPE_BUY, 0, i);
      } else {
      }
      if(sellChkFlg) {
         if(panel.getLblProfits(POSITION_TYPE_BUY, i) != "") panel.setLblProfits(POSITION_TYPE_SELL, 0, i);
         if(panel.getLblNanpin(POSITION_TYPE_BUY, i) != "") panel.setLblNanpin(POSITION_TYPE_SELL, 0, i);
      } else {
      }
   }
   
   if(buyChkFlg) {
      if(panel.getBuyCheckBoxText() == "OFF") panel.setBuyCheckBoxText("ON");
      
      //Rescue modeの利確
      
   } else {
      if(panel.getBuyCheckBoxText() == "ON") panel.setBuyCheckBoxText("OFF");
      if(panel.getLblProfits(POSITION_TYPE_BUY, 0) != "") panel.setLblProfits(POSITION_TYPE_BUY, 0, 0);
   }
   
   if(sellChkFlg) {
      if(panel.getSellCheckBoxText() == "OFF") panel.setSellCheckBoxText("ON");
      
      //Rescue modeの利確
      
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
   if(PositionsTotal() == 0) return;
   
   //パネルを前面に
   int now = ObjectsTotal(0,0,-1);

   if( now != obj_count)
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
   
}


//ポジション一括クローズ
//マジック毎にクローズフラグをたてる
void CloseAllPositions(ENUM_POSITION_TYPE pos_type, long magic) {

   int magic_idx = ArrayBsearch(MAGIC, magic);
   
   if(magic_idx < 0) return;
   
   if(pos_type == POSITION_TYPE_BUY) {
      if(magic < 0) {
         for(int i=1; i<(int)MAGIC.Size(); i++) {
            ForceCloseBuy[i] = true;
         }
      } else {
         ForceCloseBuy[magic_idx] = true;
      }
   } else {
      if(magic < 0) {
         for(int i=1; i<(int)MAGIC.Size(); i++) {
            ForceCloseSell[i] = true;
         }
      } else {
         ForceCloseSell[magic_idx] = true;
      }
   }
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
   
   if(magic==MAGIC[0] || magic == MAGIC[1])  return(ret);
   if(!CanTradeNow(Symbol())) return(ret);

   Csymbol.Name(Symbol());
   Csymbol.RefreshRates();

   //For EA1
   if(EA1 && magic == MAGIC[2]) {
      CiRsiEA1.Refresh();
      CiBandsEA1.Refresh();
      CiADXEA1.Refresh();
      // RSI < 30 && LowerBands > Bid() ならロング
      if( CiRsiEA1.Main(1) < 30 && iClose(Symbol(), PERIOD_M1, 1) < CiBandsEA1.Lower(1)
         && CiADXEA1.Main(1) < 30
         ) {
         Print("EA1 Buy Signal");
         return(1);
      }
      //  RSI > 70 && UpperBand < Bid() ならショート
      if(CiRsiEA1.Main(1) > 70 && iClose(Symbol(), PERIOD_M1, 1) > CiBandsEA1.Upper(1)
         && CiADXEA1.Main(1) < 30
         ) {
         Print("EA1 Sell Signal");
         return(-1);
      }
   }
   //For EA2
   if(EA2 && magic == MAGIC[3]) {
      CiMAEA2_200.Refresh();
      CiMAEA2Low_55.Refresh();
      CiMAEA2High_55.Refresh();
      
      // Bid(1) > SMA200 && Bid(1)(Low) <= EMA55_LOW(1) && エンガルフ(陽線包み込み)
      if(iClose(Symbol(), PERIOD_M1, 1) > CiMAEA2_200.Main(1) && iLow(Symbol(), PERIOD_M1, 1) <= CiMAEA2Low_55.Main(1)
         && iClose(Symbol(), PERIOD_M1, 2) < iOpen(Symbol(), PERIOD_M1, 2) //2個前が陰線
         && iClose(Symbol(), PERIOD_M1, 1) > iOpen(Symbol(), PERIOD_M1, 1) //1個前が陽線
         && iClose(Symbol(), PERIOD_M1, 1) > iOpen(Symbol(), PERIOD_M1, 2) //包み足
         && iOpen(Symbol(), PERIOD_M1, 1) < iClose(Symbol(), PERIOD_M1, 2)
         && iHigh(Symbol(), PERIOD_M1, 1) > iHigh(Symbol(), PERIOD_M1, 2) //高値更新
         ) {
         return(1);   
      }
      // Bid(1) < SMA200 && Bid(1)(High) >= EMA55_High(1) && エンガルフ(陰線包み込み)
      if(iClose(Symbol(), PERIOD_M1, 1) < CiMAEA2_200.Main(1) && iHigh(Symbol(), PERIOD_M1, 1) >= CiMAEA2High_55.Main(1)
         && iClose(Symbol(), PERIOD_M1, 2) > iOpen(Symbol(), PERIOD_M1, 2) //2個前が陽線
         && iClose(Symbol(), PERIOD_M1, 1) < iOpen(Symbol(), PERIOD_M1, 1) //1個前が陰線
         && iClose(Symbol(), PERIOD_M1, 1) < iOpen(Symbol(), PERIOD_M1, 2) //包み足
         && iOpen(Symbol(), PERIOD_M1, 1) > iClose(Symbol(), PERIOD_M1, 2)
         && iLow(Symbol(), PERIOD_M1, 1) < iLow(Symbol(), PERIOD_M1, 2) //底値更新
         ) {
         return(-1);   
      }

   }

   return(ret);
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

/*
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
*/

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

/*
double getTakeProfitsPrice(ENUM_POSITION_TYPE pos_type) {
   //Rescueモードでの金額指定での利確価格を返す
   double tp_division = 0.0;
   double price = 0.0;
   double plc = 0.0;
   Csymbol.Name(usdjpy_name);
   Csymbol.RefreshRates();
   if(pos_type == POSITION_TYPE_BUY) {
      price = Csymbol.Bid();
      plc = price*lotsBuy[0]*contract_size;
      if(plc != 0) tp_division = RescueBuyTP/plc;
      return (weightAverageBuy[0] + NormalizeDouble(tp_division, Digits()));
   } else {
      price = Csymbol.Ask();
      plc = price*lotsSell[0]*contract_size;
      if(plc != 0) tp_division = RescueSellTP/plc;
      return (weightAverageSell[0] - NormalizeDouble(tp_division, Digits()));
   }
}
*/

bool CanTradeNow(const string symbol)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))          return false;

   long trade_mode = 0;
   if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE, trade_mode)) return false;
   if(trade_mode == SYMBOL_TRADE_MODE_DISABLED) return false;

   // サーバ時刻で判定（テスターでもTimeTradeServer/TimeCurrentは動きます）
   datetime t = TimeTradeServer();
   if(t == 0) t = TimeCurrent();

   MqlDateTime dt; TimeToStruct(t, dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false; // 日・土は基本NG（銘柄により例外あり）

   // セッション判定（取引可能時間帯か）
   datetime from = 0, to=0;
   bool in_session = false;
   for(int i=0; i<10; i++)
   {
      if(!SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, i, from, to))
         break;
      if(from == 0 && to == 0) continue;

      // from/to は「当日0:00からの秒」基準の datetime として返るブローカーが多い
      // TimeCurrentと同じ日に揃えて比較
      datetime day0 = (datetime)(t - (dt.hour*3600 + dt.min*60 + dt.sec));
      datetime s_from = day0 + (from % 86400);
      datetime s_to   = day0 + (to   % 86400);

      if(s_to < s_from) { // 日跨ぎ
         if(t >= s_from || t <= s_to) in_session = true;
      } else {
         if(t >= s_from && t <= s_to) in_session = true;
      }
      if(in_session) break;
   }
   return in_session;
}

void ProcessForceClose()
{
   if(!CanTradeNow(Symbol())) return;

   for(int m=0; m<(int)MAGIC.Size(); m++)
   {
      //クローズすべきMAIGC毎のポジションが無い場合
      if(!ForceCloseBuy[m] && !ForceCloseSell[m])
         continue;

      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket=PositionGetTicket(i);

         if(!PositionSelectByTicket(ticket))
            continue;

         string sym=PositionGetString(POSITION_SYMBOL);
         if(sym!=Symbol())
            continue;

         long magic=PositionGetInteger(POSITION_MAGIC);
         if(magic!=MAGIC[m])
            continue;

         ENUM_POSITION_TYPE type=
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         if(type==POSITION_TYPE_BUY && !ForceCloseBuy[m])
            continue;

         if(type==POSITION_TYPE_SELL && !ForceCloseSell[m])
            continue;

         bool result = trade.PositionClose(ticket);

         if(!result)
         {
            Print("Close retry ticket=",ticket,
                  " ret=",trade.ResultRetcode(),
                  " ",trade.ResultRetcodeDescription());
         }
      }

      // 全部消えたか確認
      bool exists=false;

      for(int i=0;i<PositionsTotal();i++)
      {
         ulong ticket=PositionGetTicket(i);

         if(!PositionSelectByTicket(ticket))
            continue;

         if(PositionGetString(POSITION_SYMBOL)!=Symbol())
            continue;

         if(PositionGetInteger(POSITION_MAGIC)!=MAGIC[m])
            continue;

         ENUM_POSITION_TYPE type=
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         if(type==POSITION_TYPE_BUY && ForceCloseBuy[m])
            exists=true;

         if(type==POSITION_TYPE_SELL && ForceCloseSell[m])
            exists=true;
      }

      if(!exists)
      {
         if(ForceCloseBuy[m])
         {
            ResetBuyState(m);
            ForceCloseBuy[m]=false;
            if(m==0 && panel.getBuyCheckBox()) {
               panel.setBuyCheckBox(false);
               panel.setBuyCheckBoxText("OFF");
            }
         }

         if(ForceCloseSell[m])
         {
            ResetSellState(m);
            ForceCloseSell[m]=false;
            if(m==0 && panel.getSellCheckBox()) {
               panel.setSellCheckBox(false);
               panel.setSellCheckBoxText("OFF");
            }
         }
      }
   }
}

void ResetBuyState(int magic_idx)
{

   panel.setLblNanpin(POSITION_TYPE_BUY,0,magic_idx);
   panel.setLblProfits(POSITION_TYPE_BUY,0,magic_idx);
   ObjectsDeleteAll(0,prefix[magic_idx]+"_buy_start",-1,OBJ_HLINE);
   ObjectsDeleteAll(0,prefix[magic_idx]+"_buy_trail",-1,OBJ_HLINE);

}

void ResetSellState(int magic_idx)
{

   panel.setLblNanpin(POSITION_TYPE_SELL,0,magic_idx);
   panel.setLblProfits(POSITION_TYPE_SELL,0,magic_idx);
   ObjectsDeleteAll(0,prefix[magic_idx]+"_sell_start",-1,OBJ_HLINE);
   ObjectsDeleteAll(0,prefix[magic_idx]+"_sell_trail",-1,OBJ_HLINE);

}

void ResetPositionSummary() {

   int n= ArraySize(MAGIC);
   
   for(int i=0; i<n; i++) {
      ResetBuyState(i);
      ResetSellState(i);
   }
}


void RefreshPositionsCacheFast()
{
   ResetPositionSummary();

   int total = PositionsTotal();
   ArrayResize(g_positions, total);
   g_pos_count = 0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      int magic_idx = ArrayBsearch(MAGIC, magic);
      if(magic_idx < 0) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double price  = PositionGetDouble(POSITION_PRICE_OPEN);
      double profit = PositionGetDouble(POSITION_PROFIT);

      g_positions[g_pos_count].ticket = ticket;
      g_positions[g_pos_count].magic_idx = magic_idx;
      g_positions[g_pos_count].type = type;
      g_positions[g_pos_count].volume = volume;
      g_positions[g_pos_count].price_open = price;
      g_positions[g_pos_count].profit = profit;
      g_pos_count++;

      if(type == POSITION_TYPE_BUY)
      {
         BuyCount[magic_idx]++;
         BuyLots[magic_idx] += volume;
         BuyProfit[magic_idx] += profit;
         BuyPriceVolumeSum[magic_idx] += price * volume;

         if(LowestBuyTicket[magic_idx] == 0 || price < LowestBuyPrice[magic_idx])
         {
            LowestBuyTicket[magic_idx] = ticket;
            LowestBuyPrice[magic_idx] = price;
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         SellCount[magic_idx]++;
         SellLots[magic_idx] += volume;
         SellProfit[magic_idx] += profit;
         SellPriceVolumeSum[magic_idx] += price * volume;

         if(HighestSellTicket[magic_idx] == 0 || price > HighestSellPrice[magic_idx])
         {
            HighestSellTicket[magic_idx] = ticket;
            HighestSellPrice[magic_idx] = price;
         }
      }
   }

   ArrayResize(g_positions, g_pos_count);

   int n = ArraySize(MAGIC);
   for(int i = 0; i < n; i++)
   {
      if(BuyLots[i] > 0.0)
         BuyAvgPrice[i] = BuyPriceVolumeSum[i] / BuyLots[i];

      if(SellLots[i] > 0.0)
         SellAvgPrice[i] = SellPriceVolumeSum[i] / SellLots[i];
   }
}