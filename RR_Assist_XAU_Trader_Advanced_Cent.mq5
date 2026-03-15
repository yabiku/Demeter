//+------------------------------------------------------------------+
//|                       RR_Assist_XAU_Trader_Advanced_Cent.mq5     |
//|  XAUUSD Risk Reward Assist + Market/Pending/Close EA for MT5     |
//|  Cent account friendly version                                   |
//+------------------------------------------------------------------+
#property strict
#property version "2.10"

#include <Trade/Trade.mqh>

input long   InpMagicNumber            = 20260315;
input bool   InpStartBuyMode           = true;
input bool   InpStartSyncMode          = false;
input bool   InpUseMidPrice            = true;
input int    InpBoxBarsWidth           = 28;

input double InpDefaultRiskPoints      = 300;
input double InpDefaultRewardPoints    = 600;
input double InpDefaultLot             = 0.10;

input bool   InpKeepTPLSDistance       = true;
input bool   InpShowCurrentPrice       = true;
input bool   InpShowPriceTags          = true;
input bool   InpShowPointAndPrice      = true;

input bool   InpUseOrderSendDelayGuard = true;
input int    InpClickGuardMs           = 800;
input bool   InpAllowMultiplePositions = true;
input int    InpDeviationPoints        = 30;

input bool   InpAutoDetectCentAccount  = true;   // 追加
input double InpCentDivisorOverride    = 100.0;  // 追加: 通常は100
input bool   InpShowMajorCurrencyEquiv = true;   // 追加

input int    InpPanelX                 = 20;
input int    InpPanelY                 = 20;

input color  InpBuyColor               = clrLimeGreen;
input color  InpSellColor              = clrTomato;
input color  InpEntryColor             = clrGold;
input color  InpTPColor                = clrDeepSkyBlue;
input color  InpSLColor                = clrTomato;
input color  InpRewardFillColor        = clrPaleTurquoise;
input color  InpRiskFillColor          = clrMistyRose;
input color  InpPanelBgColor           = C'35,38,44';
input color  InpPanelTextColor         = clrWhite;
input color  InpPanelAccentColor       = C'70,130,180';
input color  InpEditBgColor            = clrWhite;
input color  InpEditTextColor          = clrBlack;
input color  InpBorderColor            = C'90,90,90';

CTrade trade;

string PREFIX;

string OBJ_PANEL_BG, OBJ_PANEL_HEADER, OBJ_TITLE, OBJ_MODE, OBJ_INFO, OBJ_STATUS;
string OBJ_BTN_BUYMODE, OBJ_BTN_SELLMODE, OBJ_BTN_SYNC, OBJ_BTN_RESET;

string OBJ_BTN_BUYNOW, OBJ_BTN_SELLNOW;
string OBJ_BTN_BUYLIMIT, OBJ_BTN_SELLLIMIT, OBJ_BTN_BUYSTOP, OBJ_BTN_SELLSTOP;

string OBJ_BTN_CLOSEBUY, OBJ_BTN_CLOSESELL, OBJ_BTN_CLOSEALL;
string OBJ_BTN_DELPEND, OBJ_BTN_DELALL;

string OBJ_CAP_ENTRY, OBJ_CAP_TP, OBJ_CAP_SL, OBJ_CAP_LOT;
string OBJ_EDT_ENTRY, OBJ_EDT_TP, OBJ_EDT_SL, OBJ_EDT_LOT;

string OBJ_CAP_RISK, OBJ_CAP_REWARD, OBJ_CAP_RR, OBJ_CAP_RISK_MONEY, OBJ_CAP_REWARD_MONEY, OBJ_CAP_BALANCE_RISK;
string OBJ_VAL_RISK, OBJ_VAL_REWARD, OBJ_VAL_RR, OBJ_VAL_RISK_MONEY, OBJ_VAL_REWARD_MONEY, OBJ_VAL_BALANCE_RISK;

string OBJ_ENTRY_LINE, OBJ_TP_LINE, OBJ_SL_LINE, OBJ_REWARD_RECT, OBJ_RISK_RECT;
string OBJ_TAG_ENTRY, OBJ_TAG_TP, OBJ_TAG_SL, OBJ_TAG_CURR;

bool   g_is_buy      = true;
bool   g_sync        = false;
double g_entry       = 0.0;
double g_tp          = 0.0;
double g_sl          = 0.0;
double g_prev_entry  = 0.0;
double g_lot         = 0.10;
ulong  g_last_click_ms = 0;

int PANEL_W = 500;
int PANEL_H = 470;

//----------------------------------------------------
// Utility
//----------------------------------------------------
int DigitsX() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS); }

double PointX()
{
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0.0) pt = 0.00001;
   return pt;
}

double NormalizePrice(double price) { return NormalizeDouble(price, DigitsX()); }

double VolumeMinX()
{
   double v = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   return (v > 0.0 ? v : 0.01);
}
double VolumeMaxX()
{
   double v = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return (v > 0.0 ? v : 100.0);
}
double VolumeStepX()
{
   double v = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return (v > 0.0 ? v : 0.01);
}

double NormalizeLot(double lot)
{
   double vmin  = VolumeMinX();
   double vmax  = VolumeMaxX();
   double vstep = VolumeStepX();

   if(lot < vmin) lot = vmin;
   if(lot > vmax) lot = vmax;

   lot = MathFloor((lot / vstep) + 0.5) * vstep;

   int digits = 2;
   if(vstep == 1.0) digits = 0;
   else if(vstep == 0.1) digits = 1;
   else if(vstep == 0.01) digits = 2;
   else if(vstep == 0.001) digits = 3;

   return NormalizeDouble(lot, digits);
}

string FmtPrice(double price) { return DoubleToString(NormalizePrice(price), DigitsX()); }

string FmtLot(double lot)
{
   double step = VolumeStepX();
   int digits = 2;
   if(step == 1.0) digits = 0;
   else if(step == 0.1) digits = 1;
   else if(step == 0.01) digits = 2;
   else if(step == 0.001) digits = 3;
   return DoubleToString(NormalizeLot(lot), digits);
}

double BidX() { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }
double AskX() { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }

double CurrentRefPrice()
{
   double bid = BidX();
   double ask = AskX();

   if(InpUseMidPrice && bid > 0.0 && ask > 0.0)
      return NormalizePrice((bid + ask) / 2.0);

   if(g_is_buy)
      return NormalizePrice(ask > 0.0 ? ask : bid);
   return NormalizePrice(bid > 0.0 ? bid : ask);
}

datetime RightTime()
{
   datetime t0 = iTime(_Symbol, _Period, 0);
   int sec = PeriodSeconds(_Period);
   if(sec <= 0) sec = 60;
   return (datetime)(t0 + sec * InpBoxBarsWidth);
}

void SafeDelete(const string name)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
}

bool Exists(const string name) { return (ObjectFind(0, name) >= 0); }
double AbsD(double v) { return (v >= 0.0 ? v : -v); }

void SetStatus(const string msg, color clr=clrWhite)
{
   if(Exists(OBJ_STATUS))
   {
      ObjectSetString(0, OBJ_STATUS, OBJPROP_TEXT, msg);
      ObjectSetInteger(0, OBJ_STATUS, OBJPROP_COLOR, clr);
   }
}

bool ClickGuardPassed()
{
   if(!InpUseOrderSendDelayGuard) return true;

   ulong now = GetTickCount64();
   if(now - g_last_click_ms < (ulong)InpClickGuardMs)
      return false;

   g_last_click_ms = now;
   return true;
}

bool IsTradeAllowedNow()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))          return false;

   long trade_mode = 0;
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE, trade_mode)) return false;
   if(trade_mode == SYMBOL_TRADE_MODE_DISABLED) return false;

   return true;
}

double StopsLevelPrice()
{
   long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (double)stops_level * PointX();
}

//----------------------------------------------------
// Cent account helpers
//----------------------------------------------------
string ToUpperStr(string s)
{
   StringToUpper(s);
   return s;
}

bool ContainsText(const string whole, const string part)
{
   return (StringFind(whole, part) >= 0);
}

string AccountCurrencyX()
{
   return AccountInfoString(ACCOUNT_CURRENCY);
}

bool IsCentAccountCurrency()
{
   if(!InpAutoDetectCentAccount)
      return false;

   string ccy = ToUpperStr(AccountCurrencyX());

   if(ccy == "USC" || ccy == "EUC" || ccy == "CENT")
      return true;

   if(ContainsText(ccy, "CENT"))
      return true;

   if(ContainsText(ccy, "USC"))
      return true;

   return false;
}

double CentDivisor()
{
   return (InpCentDivisorOverride > 0.0 ? InpCentDivisorOverride : 100.0);
}

double ToMajorCurrency(double amount)
{
   if(IsCentAccountCurrency())
      return amount / CentDivisor();
   return amount;
}

string MajorCurrencyCode()
{
   string ccy = ToUpperStr(AccountCurrencyX());

   if(ccy == "USC" || ccy == "USCENT")
      return "USD";
   if(ccy == "EUC" || ccy == "EUCENT")
      return "EUR";
   if(ContainsText(ccy, "CENT"))
   {
      // 汎用 fallback
      return "Major";
   }

   return ccy;
}

string FormatMoneyWithCentInfo(const double amount)
{
   string ccy = AccountCurrencyX();
   string s = DoubleToString(amount, 2) + " " + ccy;

   if(InpShowMajorCurrencyEquiv && IsCentAccountCurrency())
   {
      s += " (≈ " + DoubleToString(ToMajorCurrency(amount), 2) + " " + MajorCurrencyCode() + ")";
   }
   return s;
}

string FormatBalanceWithCentInfo(const double amount)
{
   string ccy = AccountCurrencyX();
   string s = DoubleToString(amount, 2) + " " + ccy;

   if(InpShowMajorCurrencyEquiv && IsCentAccountCurrency())
   {
      s += " / ≈ " + DoubleToString(ToMajorCurrency(amount), 2) + " " + MajorCurrencyCode();
   }
   return s;
}

//----------------------------------------------------
// RR / Money
//----------------------------------------------------
double RiskPrice()   { return AbsD(g_entry - g_sl); }
double RewardPrice() { return AbsD(g_tp - g_entry); }
double RiskPoints()  { return RiskPrice() / PointX(); }
double RewardPoints(){ return RewardPrice() / PointX(); }

double RRValue()
{
   double risk = RiskPrice();
   if(risk <= 0.0) return 0.0;
   return RewardPrice() / risk;
}

string RRString() { return "1 : " + DoubleToString(RRValue(), 2); }

color RRColor()
{
   double rr = RRValue();
   if(rr >= 2.0) return clrLimeGreen;
   if(rr >= 1.5) return clrGold;
   return clrTomato;
}

bool CalcProfitMoney(const ENUM_ORDER_TYPE order_type,
                     const double openPrice,
                     const double closePrice,
                     const double lot,
                     double &money)
{
   money = 0.0;
   if(lot <= 0.0) return false;

   double profit = 0.0;
   if(!OrderCalcProfit(order_type, _Symbol, lot, openPrice, closePrice, profit))
      return false;

   money = profit;
   return true;
}

double RiskMoney()
{
   double m = 0.0;
   ENUM_ORDER_TYPE t = g_is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(CalcProfitMoney(t, g_entry, g_sl, g_lot, m))
      return AbsD(m);
   return 0.0;
}

double RewardMoney()
{
   double m = 0.0;
   ENUM_ORDER_TYPE t = g_is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(CalcProfitMoney(t, g_entry, g_tp, g_lot, m))
      return AbsD(m);
   return 0.0;
}

double AccountBalanceX() { return AccountInfoDouble(ACCOUNT_BALANCE); }

double BalanceRiskPercent()
{
   double bal = AccountBalanceX();
   double riskMoney = RiskMoney();
   if(bal <= 0.0) return 0.0;
   return (riskMoney / bal) * 100.0;
}

//----------------------------------------------------
// Logic
//----------------------------------------------------
void EnsureLogicalOrder()
{
   double risk   = RiskPrice();
   double reward = RewardPrice();

   if(risk <= 0.0)   risk   = InpDefaultRiskPoints * PointX();
   if(reward <= 0.0) reward = InpDefaultRewardPoints * PointX();

   if(g_is_buy)
   {
      if(g_tp <= g_entry) g_tp = NormalizePrice(g_entry + reward);
      if(g_sl >= g_entry) g_sl = NormalizePrice(g_entry - risk);
   }
   else
   {
      if(g_tp >= g_entry) g_tp = NormalizePrice(g_entry - reward);
      if(g_sl <= g_entry) g_sl = NormalizePrice(g_entry + risk);
   }
}

void InitPrices()
{
   g_is_buy = InpStartBuyMode;
   g_sync   = InpStartSyncMode;
   g_lot    = NormalizeLot(InpDefaultLot);

   g_entry = CurrentRefPrice();
   double risk   = InpDefaultRiskPoints   * PointX();
   double reward = InpDefaultRewardPoints * PointX();

   if(g_is_buy)
   {
      g_tp = NormalizePrice(g_entry + reward);
      g_sl = NormalizePrice(g_entry - risk);
   }
   else
   {
      g_tp = NormalizePrice(g_entry - reward);
      g_sl = NormalizePrice(g_entry + risk);
   }

   EnsureLogicalOrder();
   g_prev_entry = g_entry;
}

void ApplyMode(bool buyMode)
{
   double risk   = RiskPrice();
   double reward = RewardPrice();

   if(risk <= 0.0)   risk   = InpDefaultRiskPoints * PointX();
   if(reward <= 0.0) reward = InpDefaultRewardPoints * PointX();

   g_is_buy = buyMode;

   if(g_is_buy)
   {
      g_tp = NormalizePrice(g_entry + reward);
      g_sl = NormalizePrice(g_entry - risk);
   }
   else
   {
      g_tp = NormalizePrice(g_entry - reward);
      g_sl = NormalizePrice(g_entry + risk);
   }
   EnsureLogicalOrder();
}

void ReadLinePrices()
{
   if(Exists(OBJ_ENTRY_LINE))
      g_entry = NormalizePrice(ObjectGetDouble(0, OBJ_ENTRY_LINE, OBJPROP_PRICE));
   if(Exists(OBJ_TP_LINE))
      g_tp = NormalizePrice(ObjectGetDouble(0, OBJ_TP_LINE, OBJPROP_PRICE));
   if(Exists(OBJ_SL_LINE))
      g_sl = NormalizePrice(ObjectGetDouble(0, OBJ_SL_LINE, OBJPROP_PRICE));
}

void OnEntryDraggedKeepDistance()
{
   if(!InpKeepTPLSDistance) return;

   double delta = g_entry - g_prev_entry;
   g_tp = NormalizePrice(g_tp + delta);
   g_sl = NormalizePrice(g_sl + delta);
}

void SyncEntryToMarket()
{
   double oldEntry = g_entry;
   double newEntry = CurrentRefPrice();

   double tpDist = g_tp - oldEntry;
   double slDist = g_sl - oldEntry;

   g_entry = NormalizePrice(newEntry);
   g_tp    = NormalizePrice(g_entry + tpDist);
   g_sl    = NormalizePrice(g_entry + slDist);

   EnsureLogicalOrder();
   g_prev_entry = g_entry;
}

void ResetToCurrent()
{
   InitPrices();
}

//----------------------------------------------------
// Trade helpers
//----------------------------------------------------
int CountMyPositions(const string symbol, const long magic)
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
         cnt++;
   }
   return cnt;
}

int CountMyOrders(const string symbol, const long magic)
{
   int cnt = 0;
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;

      if(OrderGetString(ORDER_SYMBOL) == symbol &&
         OrderGetInteger(ORDER_MAGIC) == magic)
         cnt++;
   }
   return cnt;
}

bool CanOpenNewPosition()
{
   if(InpAllowMultiplePositions) return true;
   return (CountMyPositions(_Symbol, InpMagicNumber) == 0);
}

bool ValidateSLTPBySide(const bool is_buy, string &reason)
{
   reason = "";

   if(is_buy)
   {
      if(g_sl >= g_entry) { reason = "BUY系ではSLはEntryより下"; return false; }
      if(g_tp <= g_entry) { reason = "BUY系ではTPはEntryより上"; return false; }
   }
   else
   {
      if(g_sl <= g_entry) { reason = "SELL系ではSLはEntryより上"; return false; }
      if(g_tp >= g_entry) { reason = "SELL系ではTPはEntryより下"; return false; }
   }
   return true;
}

bool ValidateCommon(const bool is_buy, string &reason)
{
   reason = "";

   if(!IsTradeAllowedNow())
   {
      reason = "取引不可状態です";
      return false;
   }

   g_lot = NormalizeLot(g_lot);
   if(g_lot <= 0.0)
   {
      reason = "Lot不正";
      return false;
   }

   if(!ValidateSLTPBySide(is_buy, reason))
      return false;

   return true;
}

bool ValidatePendingPrice(const ENUM_ORDER_TYPE type, string &reason)
{
   reason = "";

   double ask = AskX();
   double bid = BidX();
   double stop_gap = StopsLevelPrice();

   switch(type)
   {
      case ORDER_TYPE_BUY_LIMIT:
         if(!(g_entry < ask)) { reason = "Buy Limit は現在Askより下"; return false; }
         if(AbsD(ask - g_entry) < stop_gap) { reason = "Entryが現在価格に近すぎます"; return false; }
         break;

      case ORDER_TYPE_SELL_LIMIT:
         if(!(g_entry > bid)) { reason = "Sell Limit は現在Bidより上"; return false; }
         if(AbsD(g_entry - bid) < stop_gap) { reason = "Entryが現在価格に近すぎます"; return false; }
         break;

      case ORDER_TYPE_BUY_STOP:
         if(!(g_entry > ask)) { reason = "Buy Stop は現在Askより上"; return false; }
         if(AbsD(g_entry - ask) < stop_gap) { reason = "Entryが現在価格に近すぎます"; return false; }
         break;

      case ORDER_TYPE_SELL_STOP:
         if(!(g_entry < bid)) { reason = "Sell Stop は現在Bidより下"; return false; }
         if(AbsD(bid - g_entry) < stop_gap) { reason = "Entryが現在価格に近すぎます"; return false; }
         break;
   }

   return true;
}

bool PlaceMarketOrder(const bool is_buy)
{
   string reason = "";
   if(!ValidateCommon(is_buy, reason))
   {
      SetStatus("発注不可: " + reason, clrTomato);
      return false;
   }

   if(!CanOpenNewPosition())
   {
      SetStatus("発注不可: 同一マジックの建玉あり", clrTomato);
      return false;
   }

   if(!ClickGuardPassed())
   {
      SetStatus("連打防止中", clrGold);
      return false;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   bool ok = false;
   if(is_buy)
      ok = trade.Buy(g_lot, _Symbol, 0.0, NormalizePrice(g_sl), NormalizePrice(g_tp), "RRTrader_MarketBuy");
   else
      ok = trade.Sell(g_lot, _Symbol, 0.0, NormalizePrice(g_sl), NormalizePrice(g_tp), "RRTrader_MarketSell");

   if(ok)
   {
      SetStatus((is_buy ? "BUY" : "SELL") + " 成行発注成功", clrLimeGreen);
      return true;
   }

   SetStatus("成行失敗: " + trade.ResultRetcodeDescription(), clrTomato);
   return false;
}

bool PlacePendingOrder(const ENUM_ORDER_TYPE order_type)
{
   string reason = "";
   bool is_buy_side = (order_type == ORDER_TYPE_BUY_LIMIT || order_type == ORDER_TYPE_BUY_STOP);

   if(!ValidateCommon(is_buy_side, reason))
   {
      SetStatus("予約不可: " + reason, clrTomato);
      return false;
   }

   if(!ValidatePendingPrice(order_type, reason))
   {
      SetStatus("予約不可: " + reason, clrTomato);
      return false;
   }

   if(!ClickGuardPassed())
   {
      SetStatus("連打防止中", clrGold);
      return false;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   bool ok = false;
   switch(order_type)
   {
      case ORDER_TYPE_BUY_LIMIT:
         ok = trade.BuyLimit(g_lot, NormalizePrice(g_entry), _Symbol, NormalizePrice(g_sl), NormalizePrice(g_tp), ORDER_TIME_GTC, 0, "RRTrader_BuyLimit");
         break;
      case ORDER_TYPE_SELL_LIMIT:
         ok = trade.SellLimit(g_lot, NormalizePrice(g_entry), _Symbol, NormalizePrice(g_sl), NormalizePrice(g_tp), ORDER_TIME_GTC, 0, "RRTrader_SellLimit");
         break;
      case ORDER_TYPE_BUY_STOP:
         ok = trade.BuyStop(g_lot, NormalizePrice(g_entry), _Symbol, NormalizePrice(g_sl), NormalizePrice(g_tp), ORDER_TIME_GTC, 0, "RRTrader_BuyStop");
         break;
      case ORDER_TYPE_SELL_STOP:
         ok = trade.SellStop(g_lot, NormalizePrice(g_entry), _Symbol, NormalizePrice(g_sl), NormalizePrice(g_tp), ORDER_TIME_GTC, 0, "RRTrader_SellStop");
         break;
   }

   if(ok)
   {
      string name = EnumToString(order_type);
      SetStatus("予約注文成功: " + name, clrLimeGreen);
      return true;
   }

   SetStatus("予約失敗: " + trade.ResultRetcodeDescription(), clrTomato);
   return false;
}

int ClosePositionsByType(const ENUM_POSITION_TYPE pos_type)
{
   int success = 0;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pos_type) continue;

      if(trade.PositionClose(ticket))
         success++;
   }
   return success;
}

int CloseAllPositionsByMagic()
{
   int success = 0;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      if(trade.PositionClose(ticket))
         success++;
   }
   return success;
}

int DeletePendingByMagic(const bool only_symbol=true)
{
   int success = 0;
   trade.SetExpertMagicNumber(InpMagicNumber);

   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_LIMIT &&
         type != ORDER_TYPE_SELL_LIMIT &&
         type != ORDER_TYPE_BUY_STOP &&
         type != ORDER_TYPE_SELL_STOP)
         continue;

      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
      if(only_symbol && OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      if(trade.OrderDelete(ticket))
         success++;
   }
   return success;
}

//----------------------------------------------------
// Object creators
//----------------------------------------------------
bool CreateRectLabel(const string name, int x, int y, int w, int h, color bg, color border)
{
   SafeDelete(name);
   if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return false;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   return true;
}

bool CreateLabel(const string name, const string text, int x, int y, int size, color clr, const string font="Arial")
{
   SafeDelete(name);
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return false;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   return true;
}

bool CreateButton(const string name, const string text, int x, int y, int w, int h, color txt, color bg)
{
   SafeDelete(name);
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0)) return false;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txt);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, InpBorderColor);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   return true;
}

bool CreateEdit(const string name, const string text, int x, int y, int w, int h)
{
   SafeDelete(name);
   if(!ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0)) return false;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpEditBgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpEditTextColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, InpBorderColor);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   return true;
}

bool CreateHLine(const string name, double price, color clr, ENUM_LINE_STYLE style, int width)
{
   SafeDelete(name);
   if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price)) return false;

   ObjectSetDouble(0, name, OBJPROP_PRICE, NormalizePrice(price));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   return true;
}

bool CreateZoneRect(const string name, datetime t1, double p1, datetime t2, double p2, color clr)
{
   SafeDelete(name);
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return false;

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   return true;
}

bool CreatePriceTag(const string name, const string text, int x, int y, color bg, color txt)
{
   if(!Exists(name))
   {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return false;
   }

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 125);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 18);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   string txtName = name + "_TXT";
   if(!Exists(txtName))
      ObjectCreate(0, txtName, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, txtName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, txtName, OBJPROP_XDISTANCE, x + 6);
   ObjectSetInteger(0, txtName, OBJPROP_YDISTANCE, y + 1);
   ObjectSetInteger(0, txtName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, txtName, OBJPROP_COLOR, txt);
   ObjectSetString(0, txtName, OBJPROP_TEXT, text);
   ObjectSetString(0, txtName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, txtName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, txtName, OBJPROP_HIDDEN, false);

   return true;
}

//----------------------------------------------------
// UI
//----------------------------------------------------
int PriceToY(double price)
{
   long h = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   double pmax = ChartGetDouble(0, CHART_PRICE_MAX, 0);
   double pmin = ChartGetDouble(0, CHART_PRICE_MIN, 0);

   if(pmax <= pmin) return 0;

   double ratio = (pmax - price) / (pmax - pmin);
   int y = (int)MathRound(ratio * (double)h);

   if(y < 0) y = 0;
   if(y > (int)h - 20) y = (int)h - 20;
   return y;
}

void BuildPanel()
{
   CreateRectLabel(OBJ_PANEL_BG,     InpPanelX, InpPanelY, PANEL_W, PANEL_H, InpPanelBgColor, InpBorderColor);
   CreateRectLabel(OBJ_PANEL_HEADER, InpPanelX, InpPanelY, PANEL_W, 30, InpPanelAccentColor, InpPanelAccentColor);

   CreateLabel(OBJ_TITLE,  "RR ASSIST XAU TRADER ADV", InpPanelX + 12, InpPanelY + 7, 11, clrWhite, "Arial Bold");
   CreateLabel(OBJ_MODE,   "", InpPanelX + 12, InpPanelY + 36, 10, InpPanelTextColor);
   CreateLabel(OBJ_INFO,   "Market / Limit / Stop / Close", InpPanelX + 12, InpPanelY + 54, 9, clrSilver);
   CreateLabel(OBJ_STATUS, "Ready", InpPanelX + 12, InpPanelY + 72, 9, clrWhite);

   CreateButton(OBJ_BTN_BUYMODE,  "BUY MODE",  InpPanelX + 12,  InpPanelY + 96, 90, 24, clrBlack, clrSilver);
   CreateButton(OBJ_BTN_SELLMODE, "SELL MODE", InpPanelX + 108, InpPanelY + 96, 90, 24, clrBlack, clrSilver);
   CreateButton(OBJ_BTN_SYNC,     "SYNC OFF",  InpPanelX + 204, InpPanelY + 96, 90, 24, clrBlack, clrSilver);
   CreateButton(OBJ_BTN_RESET,    "RESET",     InpPanelX + 300, InpPanelY + 96, 90, 24, clrBlack, clrSilver);

   CreateButton(OBJ_BTN_BUYNOW,    "BUY NOW",    InpPanelX + 12,  InpPanelY + 128, 110, 26, clrBlack, clrLimeGreen);
   CreateButton(OBJ_BTN_SELLNOW,   "SELL NOW",   InpPanelX + 128, InpPanelY + 128, 110, 26, clrWhite, clrTomato);
   CreateButton(OBJ_BTN_BUYLIMIT,  "BUY LIMIT",  InpPanelX + 244, InpPanelY + 128, 110, 26, clrBlack, clrPaleGreen);
   CreateButton(OBJ_BTN_SELLLIMIT, "SELL LIMIT", InpPanelX + 360, InpPanelY + 128, 110, 26, clrWhite, clrLightSalmon);

   CreateButton(OBJ_BTN_BUYSTOP,   "BUY STOP",   InpPanelX + 12,  InpPanelY + 160, 110, 26, clrBlack, clrKhaki);
   CreateButton(OBJ_BTN_SELLSTOP,  "SELL STOP",  InpPanelX + 128, InpPanelY + 160, 110, 26, clrBlack, clrThistle);
   CreateButton(OBJ_BTN_CLOSEBUY,  "CLOSE BUY",  InpPanelX + 244, InpPanelY + 160, 110, 26, clrBlack, clrSilver);
   CreateButton(OBJ_BTN_CLOSESELL, "CLOSE SELL", InpPanelX + 360, InpPanelY + 160, 110, 26, clrBlack, clrSilver);

   CreateButton(OBJ_BTN_CLOSEALL, "CLOSE ALL", InpPanelX + 12,  InpPanelY + 192, 140, 26, clrWhite, clrFireBrick);
   CreateButton(OBJ_BTN_DELPEND,  "DELETE PEND", InpPanelX + 158, InpPanelY + 192, 150, 26, clrBlack, clrGainsboro);
   CreateButton(OBJ_BTN_DELALL,   "DELETE ALL",  InpPanelX + 314, InpPanelY + 192, 156, 26, clrWhite, clrDimGray);

   CreateLabel(OBJ_CAP_ENTRY, "Entry",       InpPanelX + 12, InpPanelY + 232, 9, InpPanelTextColor);
   CreateLabel(OBJ_CAP_TP,    "Take Profit", InpPanelX + 12, InpPanelY + 262, 9, InpPanelTextColor);
   CreateLabel(OBJ_CAP_SL,    "Stop Loss",   InpPanelX + 12, InpPanelY + 292, 9, InpPanelTextColor);
   CreateLabel(OBJ_CAP_LOT,   "Lot",         InpPanelX + 12, InpPanelY + 322, 9, InpPanelTextColor);

   CreateEdit(OBJ_EDT_ENTRY, FmtPrice(g_entry), InpPanelX + 120, InpPanelY + 227, 160, 22);
   CreateEdit(OBJ_EDT_TP,    FmtPrice(g_tp),    InpPanelX + 120, InpPanelY + 257, 160, 22);
   CreateEdit(OBJ_EDT_SL,    FmtPrice(g_sl),    InpPanelX + 120, InpPanelY + 287, 160, 22);
   CreateEdit(OBJ_EDT_LOT,   FmtLot(g_lot),     InpPanelX + 120, InpPanelY + 317, 160, 22);

   CreateLabel(OBJ_CAP_RISK,         "Risk",         InpPanelX + 12, InpPanelY + 360, 9, clrSilver);
   CreateLabel(OBJ_CAP_REWARD,       "Reward",       InpPanelX + 12, InpPanelY + 378, 9, clrSilver);
   CreateLabel(OBJ_CAP_RR,           "R:R",          InpPanelX + 12, InpPanelY + 396, 9, clrSilver);
   CreateLabel(OBJ_CAP_RISK_MONEY,   "Risk Money",   InpPanelX + 12, InpPanelY + 414, 9, clrSilver);
   CreateLabel(OBJ_CAP_REWARD_MONEY, "Reward Money", InpPanelX + 12, InpPanelY + 432, 9, clrSilver);
   CreateLabel(OBJ_CAP_BALANCE_RISK, "Balance %",    InpPanelX + 12, InpPanelY + 450, 9, clrSilver);

   CreateLabel(OBJ_VAL_RISK,         "", InpPanelX + 120, InpPanelY + 360, 9, InpPanelTextColor);
   CreateLabel(OBJ_VAL_REWARD,       "", InpPanelX + 120, InpPanelY + 378, 9, InpPanelTextColor);
   CreateLabel(OBJ_VAL_RR,           "", InpPanelX + 120, InpPanelY + 396, 9, RRColor(), "Arial Bold");
   CreateLabel(OBJ_VAL_RISK_MONEY,   "", InpPanelX + 120, InpPanelY + 414, 9, clrTomato);
   CreateLabel(OBJ_VAL_REWARD_MONEY, "", InpPanelX + 120, InpPanelY + 432, 9, clrLimeGreen);
   CreateLabel(OBJ_VAL_BALANCE_RISK, "", InpPanelX + 120, InpPanelY + 450, 9, clrGold);
}

void UpdatePanel()
{
   string side = g_is_buy ? "BUY MODE" : "SELL MODE";
   string sync = g_sync ? "SYNC ON" : "SYNC OFF";
   string accType = IsCentAccountCurrency() ? "CENT" : "NORMAL";

   ObjectSetString(0, OBJ_MODE, OBJPROP_TEXT,
                   side + " | " + sync + " | " + _Symbol +
                   " | Acc=" + accType +
                   " | Pos=" + IntegerToString(CountMyPositions(_Symbol, InpMagicNumber)) +
                   " | Ord=" + IntegerToString(CountMyOrders(_Symbol, InpMagicNumber)));

   ObjectSetInteger(0, OBJ_BTN_BUYMODE,  OBJPROP_BGCOLOR, g_is_buy ? InpBuyColor : clrSilver);
   ObjectSetInteger(0, OBJ_BTN_SELLMODE, OBJPROP_BGCOLOR, g_is_buy ? clrSilver : InpSellColor);
   ObjectSetString(0, OBJ_BTN_SYNC, OBJPROP_TEXT, g_sync ? "SYNC ON" : "SYNC OFF");
   ObjectSetInteger(0, OBJ_BTN_SYNC, OBJPROP_BGCOLOR, g_sync ? clrKhaki : clrSilver);

   ObjectSetString(0, OBJ_EDT_ENTRY, OBJPROP_TEXT, FmtPrice(g_entry));
   ObjectSetString(0, OBJ_EDT_TP,    OBJPROP_TEXT, FmtPrice(g_tp));
   ObjectSetString(0, OBJ_EDT_SL,    OBJPROP_TEXT, FmtPrice(g_sl));
   ObjectSetString(0, OBJ_EDT_LOT,   OBJPROP_TEXT, FmtLot(g_lot));

   string riskTxt, rewardTxt;
   if(InpShowPointAndPrice)
   {
      riskTxt   = DoubleToString(RiskPoints(), 1)   + " pt (" + DoubleToString(RiskPrice(), DigitsX()) + ")";
      rewardTxt = DoubleToString(RewardPoints(), 1) + " pt (" + DoubleToString(RewardPrice(), DigitsX()) + ")";
   }
   else
   {
      riskTxt   = DoubleToString(RiskPoints(), 1) + " pt";
      rewardTxt = DoubleToString(RewardPoints(), 1) + " pt";
   }

   ObjectSetString(0, OBJ_VAL_RISK,         OBJPROP_TEXT, riskTxt);
   ObjectSetString(0, OBJ_VAL_REWARD,       OBJPROP_TEXT, rewardTxt);
   ObjectSetString(0, OBJ_VAL_RR,           OBJPROP_TEXT, RRString());
   ObjectSetInteger(0, OBJ_VAL_RR,          OBJPROP_COLOR, RRColor());
   ObjectSetString(0, OBJ_VAL_RISK_MONEY,   OBJPROP_TEXT, FormatMoneyWithCentInfo(RiskMoney()));
   ObjectSetString(0, OBJ_VAL_REWARD_MONEY, OBJPROP_TEXT, FormatMoneyWithCentInfo(RewardMoney()));
   ObjectSetString(0, OBJ_VAL_BALANCE_RISK, OBJPROP_TEXT,
                   DoubleToString(BalanceRiskPercent(), 2) + " %"
                   + " | Bal " + FormatBalanceWithCentInfo(AccountBalanceX()));
}

void InitPriceObjects()
{
   CreateHLine(OBJ_ENTRY_LINE, g_entry, InpEntryColor, STYLE_DASH, 2);
   CreateHLine(OBJ_TP_LINE,    g_tp,    InpTPColor,    STYLE_SOLID, 2);
   CreateHLine(OBJ_SL_LINE,    g_sl,    InpSLColor,    STYLE_SOLID, 2);

   datetime t1 = iTime(_Symbol, _Period, 0);
   datetime t2 = RightTime();

   CreateZoneRect(OBJ_REWARD_RECT, t1, g_entry, t2, g_tp, InpRewardFillColor);
   CreateZoneRect(OBJ_RISK_RECT,   t1, g_entry, t2, g_sl, InpRiskFillColor);
}

void UpdatePriceLines()
{
   if(!Exists(OBJ_ENTRY_LINE)) CreateHLine(OBJ_ENTRY_LINE, g_entry, InpEntryColor, STYLE_DASH, 2);
   if(!Exists(OBJ_TP_LINE))    CreateHLine(OBJ_TP_LINE,    g_tp,    InpTPColor,    STYLE_SOLID, 2);
   if(!Exists(OBJ_SL_LINE))    CreateHLine(OBJ_SL_LINE,    g_sl,    InpSLColor,    STYLE_SOLID, 2);

   ObjectSetDouble(0, OBJ_ENTRY_LINE, OBJPROP_PRICE, NormalizePrice(g_entry));
   ObjectSetDouble(0, OBJ_TP_LINE,    OBJPROP_PRICE, NormalizePrice(g_tp));
   ObjectSetDouble(0, OBJ_SL_LINE,    OBJPROP_PRICE, NormalizePrice(g_sl));
}

void UpdateZoneRects()
{
   datetime t1 = iTime(_Symbol, _Period, 0);
   datetime t2 = RightTime();

   if(!Exists(OBJ_REWARD_RECT))
      CreateZoneRect(OBJ_REWARD_RECT, t1, g_entry, t2, g_tp, InpRewardFillColor);
   else
   {
      ObjectMove(0, OBJ_REWARD_RECT, 0, t1, g_entry);
      ObjectMove(0, OBJ_REWARD_RECT, 1, t2, g_tp);
   }

   if(!Exists(OBJ_RISK_RECT))
      CreateZoneRect(OBJ_RISK_RECT, t1, g_entry, t2, g_sl, InpRiskFillColor);
   else
   {
      ObjectMove(0, OBJ_RISK_RECT, 0, t1, g_entry);
      ObjectMove(0, OBJ_RISK_RECT, 1, t2, g_sl);
   }
}

void UpdatePriceTags()
{
   if(!InpShowPriceTags)
   {
      SafeDelete(OBJ_TAG_ENTRY); SafeDelete(OBJ_TAG_ENTRY + "_TXT");
      SafeDelete(OBJ_TAG_TP);    SafeDelete(OBJ_TAG_TP + "_TXT");
      SafeDelete(OBJ_TAG_SL);    SafeDelete(OBJ_TAG_SL + "_TXT");
      SafeDelete(OBJ_TAG_CURR);  SafeDelete(OBJ_TAG_CURR + "_TXT");
      return;
   }

   int entryY = PriceToY(g_entry);
   int tpY    = PriceToY(g_tp);
   int slY    = PriceToY(g_sl);

   CreatePriceTag(OBJ_TAG_ENTRY, "ENTRY  " + FmtPrice(g_entry), 10,  entryY, InpEntryColor, clrBlack);
   CreatePriceTag(OBJ_TAG_TP,    "TP     " + FmtPrice(g_tp),    10,  tpY,    InpTPColor,    clrBlack);
   CreatePriceTag(OBJ_TAG_SL,    "SL     " + FmtPrice(g_sl),    10,  slY,    InpSLColor,    clrWhite);

   if(InpShowCurrentPrice)
   {
      double cur = CurrentRefPrice();
      int curY = PriceToY(cur);
      CreatePriceTag(OBJ_TAG_CURR, "NOW    " + FmtPrice(cur), 140, curY, clrGainsboro, clrBlack);
   }
   else
   {
      SafeDelete(OBJ_TAG_CURR);
      SafeDelete(OBJ_TAG_CURR + "_TXT");
   }
}

void ParseEdit(const string objName)
{
   string s = ObjectGetString(0, objName, OBJPROP_TEXT);
   double v = StringToDouble(s);
   if(v <= 0.0) return;

   if(objName == OBJ_EDT_LOT)
   {
      g_lot = NormalizeLot(v);
      return;
   }

   v = NormalizePrice(v);

   if(objName == OBJ_EDT_ENTRY)
   {
      if(InpKeepTPLSDistance)
      {
         double delta = v - g_entry;
         g_entry = v;
         g_tp    = NormalizePrice(g_tp + delta);
         g_sl    = NormalizePrice(g_sl + delta);
      }
      else
      {
         g_entry = v;
      }
   }
   else if(objName == OBJ_EDT_TP)
   {
      g_tp = v;
   }
   else if(objName == OBJ_EDT_SL)
   {
      g_sl = v;
   }

   EnsureLogicalOrder();
   g_prev_entry = g_entry;
}

void RefreshAll()
{
   EnsureLogicalOrder();
   g_lot = NormalizeLot(g_lot);

   UpdatePriceLines();
   UpdateZoneRects();
   UpdatePanel();
   UpdatePriceTags();
   ChartRedraw(0);
}

void DeleteAll()
{
   string names[] =
   {
      OBJ_PANEL_BG, OBJ_PANEL_HEADER, OBJ_TITLE, OBJ_MODE, OBJ_INFO, OBJ_STATUS,
      OBJ_BTN_BUYMODE, OBJ_BTN_SELLMODE, OBJ_BTN_SYNC, OBJ_BTN_RESET,
      OBJ_BTN_BUYNOW, OBJ_BTN_SELLNOW, OBJ_BTN_BUYLIMIT, OBJ_BTN_SELLLIMIT, OBJ_BTN_BUYSTOP, OBJ_BTN_SELLSTOP,
      OBJ_BTN_CLOSEBUY, OBJ_BTN_CLOSESELL, OBJ_BTN_CLOSEALL, OBJ_BTN_DELPEND, OBJ_BTN_DELALL,
      OBJ_CAP_ENTRY, OBJ_CAP_TP, OBJ_CAP_SL, OBJ_CAP_LOT,
      OBJ_EDT_ENTRY, OBJ_EDT_TP, OBJ_EDT_SL, OBJ_EDT_LOT,
      OBJ_CAP_RISK, OBJ_CAP_REWARD, OBJ_CAP_RR, OBJ_CAP_RISK_MONEY, OBJ_CAP_REWARD_MONEY, OBJ_CAP_BALANCE_RISK,
      OBJ_VAL_RISK, OBJ_VAL_REWARD, OBJ_VAL_RR, OBJ_VAL_RISK_MONEY, OBJ_VAL_REWARD_MONEY, OBJ_VAL_BALANCE_RISK,
      OBJ_ENTRY_LINE, OBJ_TP_LINE, OBJ_SL_LINE, OBJ_REWARD_RECT, OBJ_RISK_RECT,
      OBJ_TAG_ENTRY, OBJ_TAG_ENTRY + "_TXT",
      OBJ_TAG_TP,    OBJ_TAG_TP + "_TXT",
      OBJ_TAG_SL,    OBJ_TAG_SL + "_TXT",
      OBJ_TAG_CURR,  OBJ_TAG_CURR + "_TXT"
   };

   for(int i = 0; i < ArraySize(names); i++)
      SafeDelete(names[i]);
}

//----------------------------------------------------
// Events
//----------------------------------------------------
int OnInit()
{
   PREFIX = "RRADV_CENT_" + IntegerToString((int)ChartID()) + "_";

   OBJ_PANEL_BG = PREFIX + "PANEL_BG";
   OBJ_PANEL_HEADER = PREFIX + "PANEL_HEADER";
   OBJ_TITLE = PREFIX + "TITLE";
   OBJ_MODE = PREFIX + "MODE";
   OBJ_INFO = PREFIX + "INFO";
   OBJ_STATUS = PREFIX + "STATUS";

   OBJ_BTN_BUYMODE = PREFIX + "BTN_BUYMODE";
   OBJ_BTN_SELLMODE = PREFIX + "BTN_SELLMODE";
   OBJ_BTN_SYNC = PREFIX + "BTN_SYNC";
   OBJ_BTN_RESET = PREFIX + "BTN_RESET";

   OBJ_BTN_BUYNOW = PREFIX + "BTN_BUYNOW";
   OBJ_BTN_SELLNOW = PREFIX + "BTN_SELLNOW";
   OBJ_BTN_BUYLIMIT = PREFIX + "BTN_BUYLIMIT";
   OBJ_BTN_SELLLIMIT = PREFIX + "BTN_SELLLIMIT";
   OBJ_BTN_BUYSTOP = PREFIX + "BTN_BUYSTOP";
   OBJ_BTN_SELLSTOP = PREFIX + "BTN_SELLSTOP";

   OBJ_BTN_CLOSEBUY = PREFIX + "BTN_CLOSEBUY";
   OBJ_BTN_CLOSESELL = PREFIX + "BTN_CLOSESELL";
   OBJ_BTN_CLOSEALL = PREFIX + "BTN_CLOSEALL";
   OBJ_BTN_DELPEND = PREFIX + "BTN_DELPEND";
   OBJ_BTN_DELALL = PREFIX + "BTN_DELALL";

   OBJ_CAP_ENTRY = PREFIX + "CAP_ENTRY";
   OBJ_CAP_TP = PREFIX + "CAP_TP";
   OBJ_CAP_SL = PREFIX + "CAP_SL";
   OBJ_CAP_LOT = PREFIX + "CAP_LOT";

   OBJ_EDT_ENTRY = PREFIX + "EDT_ENTRY";
   OBJ_EDT_TP = PREFIX + "EDT_TP";
   OBJ_EDT_SL = PREFIX + "EDT_SL";
   OBJ_EDT_LOT = PREFIX + "EDT_LOT";

   OBJ_CAP_RISK = PREFIX + "CAP_RISK";
   OBJ_CAP_REWARD = PREFIX + "CAP_REWARD";
   OBJ_CAP_RR = PREFIX + "CAP_RR";
   OBJ_CAP_RISK_MONEY = PREFIX + "CAP_RISK_MONEY";
   OBJ_CAP_REWARD_MONEY = PREFIX + "CAP_REWARD_MONEY";
   OBJ_CAP_BALANCE_RISK = PREFIX + "CAP_BALANCE_RISK";

   OBJ_VAL_RISK = PREFIX + "VAL_RISK";
   OBJ_VAL_REWARD = PREFIX + "VAL_REWARD";
   OBJ_VAL_RR = PREFIX + "VAL_RR";
   OBJ_VAL_RISK_MONEY = PREFIX + "VAL_RISK_MONEY";
   OBJ_VAL_REWARD_MONEY = PREFIX + "VAL_REWARD_MONEY";
   OBJ_VAL_BALANCE_RISK = PREFIX + "VAL_BALANCE_RISK";

   OBJ_ENTRY_LINE = PREFIX + "ENTRY_LINE";
   OBJ_TP_LINE = PREFIX + "TP_LINE";
   OBJ_SL_LINE = PREFIX + "SL_LINE";
   OBJ_REWARD_RECT = PREFIX + "REWARD_RECT";
   OBJ_RISK_RECT = PREFIX + "RISK_RECT";

   OBJ_TAG_ENTRY = PREFIX + "TAG_ENTRY";
   OBJ_TAG_TP = PREFIX + "TAG_TP";
   OBJ_TAG_SL = PREFIX + "TAG_SL";
   OBJ_TAG_CURR = PREFIX + "TAG_CURR";

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   InitPrices();
   BuildPanel();
   InitPriceObjects();
   RefreshAll();

   if(IsCentAccountCurrency())
      SetStatus("Ready (Cent account detected)", clrLimeGreen);
   else
      SetStatus("Ready", clrWhite);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteAll();
}

void OnTick()
{
   if(g_sync)
      SyncEntryToMarket();

   UpdateZoneRects();
   UpdatePriceTags();
   UpdatePanel();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == OBJ_BTN_BUYMODE)   { ApplyMode(true);  RefreshAll(); return; }
      if(sparam == OBJ_BTN_SELLMODE)  { ApplyMode(false); RefreshAll(); return; }
      if(sparam == OBJ_BTN_SYNC)      { g_sync = !g_sync; if(g_sync) SyncEntryToMarket(); RefreshAll(); return; }
      if(sparam == OBJ_BTN_RESET)     { ResetToCurrent(); RefreshAll(); SetStatus("リセットしました", clrWhite); return; }

      if(sparam == OBJ_BTN_BUYNOW)    { PlaceMarketOrder(true);  RefreshAll(); return; }
      if(sparam == OBJ_BTN_SELLNOW)   { PlaceMarketOrder(false); RefreshAll(); return; }

      if(sparam == OBJ_BTN_BUYLIMIT)  { PlacePendingOrder(ORDER_TYPE_BUY_LIMIT);  RefreshAll(); return; }
      if(sparam == OBJ_BTN_SELLLIMIT) { PlacePendingOrder(ORDER_TYPE_SELL_LIMIT); RefreshAll(); return; }
      if(sparam == OBJ_BTN_BUYSTOP)   { PlacePendingOrder(ORDER_TYPE_BUY_STOP);   RefreshAll(); return; }
      if(sparam == OBJ_BTN_SELLSTOP)  { PlacePendingOrder(ORDER_TYPE_SELL_STOP);  RefreshAll(); return; }

      if(sparam == OBJ_BTN_CLOSEBUY)
      {
         int n = ClosePositionsByType(POSITION_TYPE_BUY);
         SetStatus("BUYクローズ: " + IntegerToString(n) + "件", n > 0 ? clrLimeGreen : clrGold);
         RefreshAll();
         return;
      }
      if(sparam == OBJ_BTN_CLOSESELL)
      {
         int n = ClosePositionsByType(POSITION_TYPE_SELL);
         SetStatus("SELLクローズ: " + IntegerToString(n) + "件", n > 0 ? clrLimeGreen : clrGold);
         RefreshAll();
         return;
      }
      if(sparam == OBJ_BTN_CLOSEALL)
      {
         int n = CloseAllPositionsByMagic();
         SetStatus("全クローズ: " + IntegerToString(n) + "件", n > 0 ? clrLimeGreen : clrGold);
         RefreshAll();
         return;
      }
      if(sparam == OBJ_BTN_DELPEND)
      {
         int n = DeletePendingByMagic(true);
         SetStatus("予約削除: " + IntegerToString(n) + "件", n > 0 ? clrLimeGreen : clrGold);
         RefreshAll();
         return;
      }
      if(sparam == OBJ_BTN_DELALL)
      {
         int n1 = DeletePendingByMagic(true);
         int n2 = CloseAllPositionsByMagic();
         SetStatus("削除/クローズ: order=" + IntegerToString(n1) + " pos=" + IntegerToString(n2), (n1+n2)>0 ? clrLimeGreen : clrGold);
         RefreshAll();
         return;
      }
   }

   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      if(sparam == OBJ_ENTRY_LINE || sparam == OBJ_TP_LINE || sparam == OBJ_SL_LINE)
      {
         double oldEntry = g_entry;
         ReadLinePrices();

         if(sparam == OBJ_ENTRY_LINE)
         {
            g_prev_entry = oldEntry;
            OnEntryDraggedKeepDistance();
         }

         EnsureLogicalOrder();
         g_prev_entry = g_entry;
         RefreshAll();
         return;
      }
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == OBJ_EDT_ENTRY || sparam == OBJ_EDT_TP || sparam == OBJ_EDT_SL || sparam == OBJ_EDT_LOT)
      {
         ParseEdit(sparam);
         RefreshAll();
         return;
      }
   }

   if(id == CHARTEVENT_CHART_CHANGE)
   {
      UpdateZoneRects();
      UpdatePriceTags();
      ChartRedraw(0);
   }
}