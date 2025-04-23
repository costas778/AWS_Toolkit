from freqtrade.strategy import IStrategy, IntParameter
import pandas as pd
import talib.abstract as ta
import numpy as np
from pandas import DataFrame
from freqtrade.persistence import Trade
from datetime import datetime, timedelta
from functools import reduce
import talib.abstract as ta

class SimpleStrategy(IStrategy):
    INTERFACE_VERSION = 3
    
    minimal_roi = {
        "0": 0.05
    }
    
    stoploss = -0.10
    timeframe = '5m'
    
    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe['rsi'] = ta.RSI(dataframe, timeperiod=14)
        
        # Bollinger Bands
        bollinger = ta.BBANDS(dataframe, timeperiod=20, nbdevup=2.0, nbdevdn=2.0)
        dataframe['bb_lowerband'] = bollinger['lowerband']
        dataframe['bb_middleband'] = bollinger['middleband']
        dataframe['bb_upperband'] = bollinger['upperband']
        
        return dataframe
    
    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (
                (dataframe['rsi'] < 30) &
                (dataframe['close'] < dataframe['bb_lowerband'])
            ),
            'enter_long'] = 1
        
        return dataframe
    
    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (
                (dataframe['rsi'] > 70) |
                (dataframe['close'] > dataframe['bb_upperband'])
            ),
            'exit_long'] = 1
        
        return dataframe
