//+------------------------------------------------------------------+
//|                    ADVANCED PRICE ACTION EA                       |
//|          Professional MQL5 Expert Advisor v1.0                    |
//|                                                                   |
//| Strategy: Pure Price Action + Momentum/Order Flow                |
//| Risk Management: Dynamic Position Sizing & Daily Drawdown        |
//| Features: Interactive Dashboard, Multi-Timeframe, All Pairs      |
//+------------------------------------------------------------------+

#property copyright "Ahmed Trader © 2026"
#property link      "https://github.com/MrAhmedTrader"
#property version   "1.0"
#property strict
#property icon      "🤖"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Enumeration for Trade Direction
enum TRADE_DIRECTION {
   DIRECTION_BUY = 1,
   DIRECTION_SELL = -1,
   DIRECTION_NONE = 0
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - User Configuration                           |
//+------------------------------------------------------------------+

input group "=== RISK MANAGEMENT SETTINGS ==="
input double RiskPercentage = 2.0;              // Risk % per Trade (0.5-5%)
input double MaxDailyLossPercent = 5.0;         // Max Daily Loss % to Stop Trading
input double MinAccountBalance = 100;            // Minimum Account Balance for Trading

input group "=== PRICE ACTION SETTINGS ==="
input int ATRPeriod = 14;                       // ATR Period for Volatility (10-20)
input double ATRMultiplier_SL = 1.5;            // ATR Multiplier for Stop Loss (1.0-2.5)
input double ATRMultiplier_TP = 2.5;            // ATR Multiplier for Take Profit (2.0-4.0)
input int MomentumPeriod = 5;                   // Price Momentum Check Period (3-10)
input double MinMomentumThreshold = 0.0005;     // Minimum Momentum Threshold (0.0001-0.001)

input group "=== SPREAD & SLIPPAGE SETTINGS ==="
input double MaxSpreadPips = 5.0;               // Max Allowed Spread in Pips
input double MaxSlippagePips = 3.0;             // Max Allowed Slippage in Pips
input int MaxRetries = 3;                       // Max Order Retries on Failure

input group "=== TRADING SESSION SETTINGS ==="
input bool EnableTimeFilter = false;            // Enable Specific Trading Hours Filter
input int StartHour = 8;                        // Start Trading Hour (UTC)
input int EndHour = 20;                         // End Trading Hour (UTC)
input bool SkipFridayCloseTime = true;          // Skip Trading on Friday Close

input group "=== ADVANCED SETTINGS ==="
input ulong MagicNumber = 20260904;             // Magic Number for Order Identification
input bool EnableSound = false;                 // Enable Sound Alerts
input bool EnableNotifications = false;         // Enable Push Notifications
input bool EnableDashboard = true;              // Enable Interactive Dashboard

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                |
//+------------------------------------------------------------------+

CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

double dLastATR = 0;
double dCurrentSpread = 0;
datetime dtLastBarTime = 0;
datetime dtDailyStartTime = 0;
double dDailyStartBalance = 0;
bool bDailyLimitReached = false;
int iOpenPositions = 0;

// Dashboard Objects
string sDashboardPrefix = "DASH_";
struct DashboardData {
   double dailyProfit;
   double currentBalance;
   int openPositions;
   double currentSpread;
   double riskPercent;
   bool isEAActive;
};

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                           |
//+------------------------------------------------------------------+

int OnInit() {
   // Initialize Trade object with Magic Number
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Set deviation for all orders
   trade.SetDeviationInPoints((int)(MaxSlippagePips * 10));
   
   // Validate Input Parameters
   if(!ValidateInputs()) {
      Print("❌ ERROR: Invalid Input Parameters. EA will not start.");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Initialize Daily Values
   dtDailyStartTime = iTime(Symbol(), PERIOD_D1, 0);
   dDailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   bDailyLimitReached = false;
   
   // Create Dashboard
   if(EnableDashboard) {
      CreateDashboard();
   }
   
   Print("✅ EA Initialized Successfully!");
   Print("   Magic Number: ", MagicNumber);
   Print("   Risk Per Trade: ", RiskPercentage, "%");
   Print("   Max Daily Loss: ", MaxDailyLossPercent, "%");
   Print("   Max Spread: ", MaxSpreadPips, " pips");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                         |
//+------------------------------------------------------------------+

void OnDeinit(const int reason) {
   // Delete all dashboard objects
   if(EnableDashboard) {
      DeleteDashboard();
   }
   
   Print("⚠️  EA Stopped. Reason Code: ", reason);
}

//+------------------------------------------------------------------+
//| EXPERT TICK - Main Trading Logic                                |
//+------------------------------------------------------------------+

void OnTick() {
   // Check if new bar formed (to avoid redundant calculations)
   if(!IsNewBar()) {
      return;
   }
   
   // 1. Risk Management Checks
   if(!CheckTradingConditions()) {
      return;
   }
   
   // 2. Calculate Current Market Parameters
   CalculateMarketParameters();
   
   // 3. Update Daily Statistics
   UpdateDailyStatistics();
   
   // 4. Price Action Signal Detection
   TRADE_DIRECTION signal = DetectPriceActionSignal();
   
   // 5. Execute Trade if Signal Found
   if(signal != DIRECTION_NONE) {
      ExecuteTrade(signal);
   }
   
   // 6. Update Dashboard
   if(EnableDashboard) {
      UpdateDashboard();
   }
}

//+------------------------------------------------------------------+
//| NEW BAR DETECTION                                               |
//+------------------------------------------------------------------+

bool IsNewBar() {
   datetime dtCurrentBarTime = iTime(Symbol(), Period(), 0);
   
   if(dtLastBarTime != dtCurrentBarTime) {
      dtLastBarTime = dtCurrentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| VALIDATE INPUT PARAMETERS                                       |
//+------------------------------------------------------------------+

bool ValidateInputs() {
   if(RiskPercentage <= 0 || RiskPercentage > 10) {
      Print("❌ Risk Percentage must be between 0.1% and 10%");
      return false;
   }
   
   if(MaxDailyLossPercent <= 0 || MaxDailyLossPercent > 50) {
      Print("❌ Max Daily Loss must be between 0.1% and 50%");
      return false;
   }
   
   if(ATRPeriod < 5 || ATRPeriod > 50) {
      Print("❌ ATR Period must be between 5 and 50");
      return false;
   }
   
   if(MaxSpreadPips <= 0) {
      Print("❌ Max Spread must be greater than 0");
      return false;
   }
   
   if(MaxSlippagePips < 0) {
      Print("❌ Max Slippage cannot be negative");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| CHECK TRADING CONDITIONS                                        |
//+------------------------------------------------------------------+

bool CheckTradingConditions() {
   // 1. Check if account balance is sufficient
   double dBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(dBalance < MinAccountBalance) {
      Print("⚠️  Account balance below minimum: ", dBalance);
      return false;
   }
   
   // 2. Check daily loss limit
   if(bDailyLimitReached) {
      return false;
   }
   
   // 3. Check spread filter
   dCurrentSpread = (Ask() - Bid()) / Point();
   if(dCurrentSpread > MaxSpreadPips) {
      return false;
   }
   
   // 4. Check time filter
   if(EnableTimeFilter) {
      if(!IsWithinTradingHours()) {
         return false;
      }
   }
   
   // 5. Skip Friday close time
   if(SkipFridayCloseTime) {
      MqlDateTime stTime;
      TimeToStruct(TimeCurrent(), stTime);
      
      if(stTime.day_of_week == 5 && stTime.hour >= 20) { // Friday after 20:00 UTC
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| CHECK IF WITHIN TRADING HOURS                                   |
//+------------------------------------------------------------------+

bool IsWithinTradingHours() {
   MqlDateTime stTime;
   TimeToStruct(TimeCurrent(), stTime);
   
   if(stTime.hour >= StartHour && stTime.hour < EndHour) {
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| CALCULATE MARKET PARAMETERS                                     |
//+------------------------------------------------------------------+

void CalculateMarketParameters() {
   // Calculate ATR for dynamic TP/SL using built-in iATR function
   dLastATR = iATR(Symbol(), Period(), ATRPeriod);
   
   // Get current spread
   dCurrentSpread = (Ask() - Bid()) / Point();
}

//+------------------------------------------------------------------+
//| DETECT PRICE ACTION SIGNAL                                      |
//+------------------------------------------------------------------+

TRADE_DIRECTION DetectPriceActionSignal() {
   // Get required bars
   double dClose0 = Close(0);
   double dClose1 = Close(1);
   double dClose2 = Close(2);
   double dOpen0 = Open(0);
   
   double dHigh0 = High(0);
   double dLow0 = Low(0);
   double dHigh1 = High(1);
   double dLow1 = Low(1);
   
   // Calculate momentum
   double dMomentum = (dClose0 - Close(MomentumPeriod)) / Close(MomentumPeriod);
   
   // BUY SIGNAL: Bullish Price Action
   // - Close above open (bullish candle)
   // - Higher High
   // - Positive momentum
   // - Price closing in upper half of range
   if(dClose0 > dOpen0 &&
      dHigh0 > dHigh1 &&
      dMomentum > MinMomentumThreshold &&
      (dClose0 - dLow0) > (dHigh0 - dClose0)) {
      
      return DIRECTION_BUY;
   }
   
   // SELL SIGNAL: Bearish Price Action
   // - Close below open (bearish candle)
   // - Lower Low
   // - Negative momentum
   // - Price closing in lower half of range
   if(dClose0 < dOpen0 &&
      dLow0 < dLow1 &&
      dMomentum < -MinMomentumThreshold &&
      (dHigh0 - dClose0) > (dClose0 - dLow0)) {
      
      return DIRECTION_SELL;
   }
   
   return DIRECTION_NONE;
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                   |
//+------------------------------------------------------------------+

void ExecuteTrade(TRADE_DIRECTION direction) {
   // Check if we already have an open position
   if(HasOpenPosition()) {
      return;
   }
   
   // Calculate position size based on risk management
   double dLotSize = CalculateLotSize(direction);
   
   if(dLotSize <= 0) {
      Print("⚠️  Invalid lot size calculated: ", dLotSize);
      return;
   }
   
   // Calculate TP and SL levels
   double dStopLoss = 0;
   double dTakeProfit = 0;
   
   if(direction == DIRECTION_BUY) {
      dStopLoss = Bid() - (dLastATR * ATRMultiplier_SL);
      dTakeProfit = Ask() + (dLastATR * ATRMultiplier_TP);
      
      // Attempt to open BUY order
      if(!OpenBuyOrder(dLotSize, dStopLoss, dTakeProfit)) {
         Print("❌ Failed to open BUY order");
      }
   }
   else if(direction == DIRECTION_SELL) {
      dStopLoss = Ask() + (dLastATR * ATRMultiplier_SL);
      dTakeProfit = Bid() - (dLastATR * ATRMultiplier_TP);
      
      // Attempt to open SELL order
      if(!OpenSellOrder(dLotSize, dStopLoss, dTakeProfit)) {
         Print("❌ Failed to open SELL order");
      }
   }
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE BASED ON RISK MANAGEMENT                     |
//+------------------------------------------------------------------+

double CalculateLotSize(TRADE_DIRECTION direction) {
   double dBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dRiskAmount = dBalance * (RiskPercentage / 100.0);
   
   // Get point value and symbol info
   double dPointValue = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double dTickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double dMinLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double dMaxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double dLotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   
   // Calculate stop loss distance in pips
   double dATRInPips = dLastATR / dPointValue;
   double dSLDistance = dATRInPips * ATRMultiplier_SL;
   
   if(dSLDistance <= 0) {
      Print("⚠️  Invalid SL distance");
      return 0;
   }
   
   // Calculate required lot size
   double dLotSize = dRiskAmount / (dSLDistance * dTickValue);
   
   // Normalize lot size to broker's requirements
   dLotSize = NormalizeLotSize(dLotSize, dMinLot, dMaxLot, dLotStep);
   
   return dLotSize;
}

//+------------------------------------------------------------------+
//| NORMALIZE LOT SIZE TO BROKER REQUIREMENTS                        |
//+------------------------------------------------------------------+

double NormalizeLotSize(double dLot, double dMinLot, double dMaxLot, double dLotStep) {
   // Clamp to min and max
   if(dLot < dMinLot) {
      dLot = dMinLot;
   }
   if(dLot > dMaxLot) {
      dLot = dMaxLot;
   }
   
   // Round to lot step
   dLot = MathRound(dLot / dLotStep) * dLotStep;
   
   return dLot;
}

//+------------------------------------------------------------------+
//| OPEN BUY ORDER                                                  |
//+------------------------------------------------------------------+

bool OpenBuyOrder(double dVolume, double dSL, double dTP) {
   for(int i = 0; i < MaxRetries; i++) {
      if(trade.Buy(dVolume, Symbol(), Ask(), dSL, dTP, "PA Buy Signal")) {
         Print("✅ BUY Order Opened: ", trade.ResultOrder(), " Volume: ", dVolume);
         iOpenPositions++;
         
         if(EnableSound) PlaySound("alert.wav");
         if(EnableNotifications) SendNotification("BUY order opened on " + Symbol());
         
         return true;
      }
      else {
         int iError = GetLastError();
         Print("⚠️  Order failed (Attempt ", i+1, "/", MaxRetries, "). Error: ", iError);
         Sleep(100);
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| OPEN SELL ORDER                                                 |
//+------------------------------------------------------------------+

bool OpenSellOrder(double dVolume, double dSL, double dTP) {
   for(int i = 0; i < MaxRetries; i++) {
      if(trade.Sell(dVolume, Symbol(), Bid(), dSL, dTP, "PA Sell Signal")) {
         Print("✅ SELL Order Opened: ", trade.ResultOrder(), " Volume: ", dVolume);
         iOpenPositions++;
         
         if(EnableSound) PlaySound("alert.wav");
         if(EnableNotifications) SendNotification("SELL order opened on " + Symbol());
         
         return true;
      }
      else {
         int iError = GetLastError();
         Print("⚠️  Order failed (Attempt ", i+1, "/", MaxRetries, "). Error: ", iError);
         Sleep(100);
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| CHECK IF POSITION EXISTS                                        |
//+------------------------------------------------------------------+

bool HasOpenPosition() {
   iOpenPositions = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() == Symbol() && 
            positionInfo.Magic() == MagicNumber) {
            iOpenPositions++;
         }
      }
   }
   
   return iOpenPositions > 0;
}

//+------------------------------------------------------------------+
//| UPDATE DAILY STATISTICS                                         |
//+------------------------------------------------------------------+

void UpdateDailyStatistics() {
   // Check if new day started
   datetime dtCurrentDayTime = iTime(Symbol(), PERIOD_D1, 0);
   
   if(dtCurrentDayTime != dtDailyStartTime) {
      dtDailyStartTime = dtCurrentDayTime;
      dDailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      bDailyLimitReached = false;
      Print("📊 New Trading Day Started. Daily P&L Reset.");
   }
   
   // Calculate daily loss
   double dCurrentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dDailyLoss = ((dDailyStartBalance - dCurrentBalance) / dDailyStartBalance) * 100.0;
   
   // Check if daily loss limit exceeded
   if(dDailyLoss >= MaxDailyLossPercent) {
      bDailyLimitReached = true;
      Print("🛑 DAILY LOSS LIMIT REACHED! Daily Loss: ", dDailyLoss, "%");
      Print("   Trading will be paused until new day.");
   }
}

//+------------------------------------------------------------------+
//| GET CLOSE PRICE                                                 |
//+------------------------------------------------------------------+

double Close(int iShift) {
   return iClose(Symbol(), Period(), iShift);
}

//+------------------------------------------------------------------+
//| GET OPEN PRICE                                                  |
//+------------------------------------------------------------------+

double Open(int iShift) {
   return iOpen(Symbol(), Period(), iShift);
}

//+------------------------------------------------------------------+
//| GET HIGH PRICE                                                  |
//+------------------------------------------------------------------+

double High(int iShift) {
   return iHigh(Symbol(), Period(), iShift);
}

//+------------------------------------------------------------------+
//| GET LOW PRICE                                                   |
//+------------------------------------------------------------------+

double Low(int iShift) {
   return iLow(Symbol(), Period(), iShift);
}

//+------------------------------------------------------------------+
//| GET ASK PRICE                                                   |
//+------------------------------------------------------------------+

double Ask() {
   return SymbolInfoDouble(Symbol(), SYMBOL_ASK);
}

//+------------------------------------------------------------------+
//| GET BID PRICE                                                   |
//+------------------------------------------------------------------+

double Bid() {
   return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}

//+------------------------------------------------------------------+
//| CREATE INTERACTIVE DASHBOARD                                    |
//+------------------------------------------------------------------+

void CreateDashboard() {
   // Create main background rectangle
   RectLabelCreate(0, sDashboardPrefix + "BG", 20, 20, 400, 250, clrDarkGray);
   
   // Create title
   TextLabelCreate(0, sDashboardPrefix + "TITLE", 30, 35, "🤖 ADVANCED PRICE ACTION EA", 
                   "Arial Black", 12, clrYellow, ANCHOR_POINT_LEFT_TOP);
   
   // Create status label
   TextLabelCreate(0, sDashboardPrefix + "STATUS", 30, 55, "Status: ACTIVE", 
                   "Arial", 10, clrLime, ANCHOR_POINT_LEFT_TOP);
   
   // Create profit label
   TextLabelCreate(0, sDashboardPrefix + "PROFIT", 30, 75, "Daily P&L: $0.00", 
                   "Arial", 10, clrWhite, ANCHOR_POINT_LEFT_TOP);
   
   // Create positions label
   TextLabelCreate(0, sDashboardPrefix + "POSITIONS", 30, 95, "Open Positions: 0", 
                   "Arial", 10, clrWhite, ANCHOR_POINT_LEFT_TOP);
   
   // Create spread label
   TextLabelCreate(0, sDashboardPrefix + "SPREAD", 30, 115, "Current Spread: 0.0 pips", 
                   "Arial", 10, clrWhite, ANCHOR_POINT_LEFT_TOP);
   
   // Create balance label
   TextLabelCreate(0, sDashboardPrefix + "BALANCE", 30, 135, "Account Balance: $0.00", 
                   "Arial", 10, clrWhite, ANCHOR_POINT_LEFT_TOP);
   
   // Create risk label
   TextLabelCreate(0, sDashboardPrefix + "RISK", 30, 155, "Risk per Trade: 0.00%", 
                   "Arial", 10, clrWhite, ANCHOR_POINT_LEFT_TOP);
   
   // Create ATR label
   TextLabelCreate(0, sDashboardPrefix + "ATR", 30, 175, "Current ATR: 0.0000", 
                   "Arial", 10, clrWhite, ANCHOR_POINT_LEFT_TOP);
   
   // Create time label
   TextLabelCreate(0, sDashboardPrefix + "TIME", 30, 195, "Last Update: 00:00:00", 
                   "Arial", 9, clrSilver, ANCHOR_POINT_LEFT_TOP);
   
   // Create mode label
   TextLabelCreate(0, sDashboardPrefix + "MODE", 30, 215, "Mode: Price Action + Momentum", 
                   "Arial", 9, clrCyan, ANCHOR_POINT_LEFT_TOP);
}

//+------------------------------------------------------------------+
//| UPDATE DASHBOARD                                                |
//+------------------------------------------------------------------+

void UpdateDashboard() {
   double dBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dDailyProfit = dBalance - dDailyStartBalance;
   
   // Update Status
   string sStatus = bDailyLimitReached ? "PAUSED - Daily Limit" : "ACTIVE";
   color cStatus = bDailyLimitReached ? clrRed : clrLime;
   TextLabelModify(0, sDashboardPrefix + "STATUS", "Status: " + sStatus, cStatus);
   
   // Update Daily P&L
   color cProfit = dDailyProfit >= 0 ? clrLime : clrRed;
   TextLabelModify(0, sDashboardPrefix + "PROFIT", 
      "Daily P&L: $" + DoubleToString(dDailyProfit, 2), cProfit);
   
   // Update Open Positions
   TextLabelModify(0, sDashboardPrefix + "POSITIONS", 
      "Open Positions: " + IntegerToString(iOpenPositions), clrWhite);
   
   // Update Spread
   TextLabelModify(0, sDashboardPrefix + "SPREAD", 
      "Current Spread: " + DoubleToString(dCurrentSpread, 1) + " pips", clrWhite);
   
   // Update Balance
   TextLabelModify(0, sDashboardPrefix + "BALANCE", 
      "Account Balance: $" + DoubleToString(dBalance, 2), clrWhite);
   
   // Update Risk
   TextLabelModify(0, sDashboardPrefix + "RISK", 
      "Risk per Trade: " + DoubleToString(RiskPercentage, 2) + "%", clrWhite);
   
   // Update ATR
   TextLabelModify(0, sDashboardPrefix + "ATR", 
      "Current ATR: " + DoubleToString(dLastATR, 4), clrWhite);
   
   // Update Time
   MqlDateTime stTime;
   TimeToStruct(TimeCurrent(), stTime);
   string sTime = StringFormat("%02d:%02d:%02d", stTime.hour, stTime.min, stTime.sec);
   TextLabelModify(0, sDashboardPrefix + "TIME", "Last Update: " + sTime, clrSilver);
}

//+------------------------------------------------------------------+
//| DELETE DASHBOARD                                                |
//+------------------------------------------------------------------+

void DeleteDashboard() {
   ObjectDelete(0, sDashboardPrefix + "BG");
   ObjectDelete(0, sDashboardPrefix + "TITLE");
   ObjectDelete(0, sDashboardPrefix + "STATUS");
   ObjectDelete(0, sDashboardPrefix + "PROFIT");
   ObjectDelete(0, sDashboardPrefix + "POSITIONS");
   ObjectDelete(0, sDashboardPrefix + "SPREAD");
   ObjectDelete(0, sDashboardPrefix + "BALANCE");
   ObjectDelete(0, sDashboardPrefix + "RISK");
   ObjectDelete(0, sDashboardPrefix + "ATR");
   ObjectDelete(0, sDashboardPrefix + "TIME");
   ObjectDelete(0, sDashboardPrefix + "MODE");
}

//+------------------------------------------------------------------+
//| CREATE RECTANGLE LABEL                                          |
//+------------------------------------------------------------------+

void RectLabelCreate(long lChartID, string sName, int iX, int iY, int iWidth, int iHeight,
                     color clrColor) {
   ObjectCreate(lChartID, sName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(lChartID, sName, OBJPROP_XDISTANCE, iX);
   ObjectSetInteger(lChartID, sName, OBJPROP_YDISTANCE, iY);
   ObjectSetInteger(lChartID, sName, OBJPROP_XSIZE, iWidth);
   ObjectSetInteger(lChartID, sName, OBJPROP_YSIZE, iHeight);
   ObjectSetInteger(lChartID, sName, OBJPROP_BGCOLOR, clrColor);
   ObjectSetInteger(lChartID, sName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(lChartID, sName, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(lChartID, sName, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| CREATE TEXT LABEL                                               |
//+------------------------------------------------------------------+

void TextLabelCreate(long lChartID, string sName, int iX, int iY, string sText,
                     string sFont, int iFontSize, color clrColor, 
                     ENUM_ANCHOR_POINT anchor) {
   ObjectCreate(lChartID, sName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(lChartID, sName, OBJPROP_XDISTANCE, iX);
   ObjectSetInteger(lChartID, sName, OBJPROP_YDISTANCE, iY);
   ObjectSetString(lChartID, sName, OBJPROP_TEXT, sText);
   ObjectSetString(lChartID, sName, OBJPROP_FONT, sFont);
   ObjectSetInteger(lChartID, sName, OBJPROP_FONTSIZE, iFontSize);
   ObjectSetInteger(lChartID, sName, OBJPROP_COLOR, clrColor);
   ObjectSetInteger(lChartID, sName, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(lChartID, sName, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| MODIFY TEXT LABEL                                               |
//+------------------------------------------------------------------+

void TextLabelModify(long lChartID, string sName, string sText, color clrColor) {
   ObjectSetString(lChartID, sName, OBJPROP_TEXT, sText);
   ObjectSetInteger(lChartID, sName, OBJPROP_COLOR, clrColor);
}

//+------------------------------------------------------------------+
//| END OF EXPERT ADVISOR                                           |
//+------------------------------------------------------------------+
