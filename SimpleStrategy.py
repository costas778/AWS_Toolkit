from freqtrade.strategy import IStrategy, IntParameter
import pandas as pd
import talib.abstract as ta
from pandas import DataFrame
from datetime import datetime
from freqtrade.persistence import Trade
from typing import Dict, List, Optional

class SimpleStrategy(IStrategy):
    INTERFACE_VERSION = 3
    
    # Buy hyperspace params:
    buy_params = {
        "buy_rsi": 30,
    }

    # Sell hyperspace params:
    sell_params = {
        "sell_rsi": 70,
    }

    # ROI table:
    minimal_roi = {
        "0": 0.1,
        "30": 0.05,
        "60": 0.025,
        "120": 0.01
    }

    # Stoploss:
    stoploss = -0.15

    # Trailing stop:
    trailing_stop = False
    trailing_stop_positive = 0.01
    trailing_stop_positive_offset = 0.02
    trailing_only_offset_is_reached = True

    # Timeframe
    timeframe = '5m'

    # Indicators
    buy_rsi = IntParameter(low=10, high=40, default=30, space='buy', optimize=True)
    sell_rsi = IntParameter(low=60, high=90, default=70, space='sell', optimize=True)

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        # RSI
        dataframe['rsi'] = ta.RSI(dataframe, timeperiod=14)
        
        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (
                (dataframe['rsi'] < self.buy_rsi.value) &
                (dataframe['volume'] > 0)
            ),
            'enter_long'] = 1

        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (
                (dataframe['rsi'] > self.sell_rsi.value) &
                (dataframe['volume'] > 0)
            ),
            'exit_long'] = 1

        return dataframe
