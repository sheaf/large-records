{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Common.RowOfSize.Row050 (Row) where

import Data.Record.Anonymous.Simple (Pair((:=)))

import Bench.Types

type Row = '[
    -- 00 .. 09
    "t00" := T 00
  , "t01" := T 01
  , "t02" := T 02
  , "t03" := T 03
  , "t04" := T 04
  , "t05" := T 05
  , "t06" := T 06
  , "t07" := T 07
  , "t08" := T 08
  , "t09" := T 09
    -- 10 .. 19
  , "t10" := T 10
  , "t11" := T 11
  , "t12" := T 12
  , "t13" := T 13
  , "t14" := T 14
  , "t15" := T 15
  , "t16" := T 16
  , "t17" := T 17
  , "t18" := T 18
  , "t19" := T 19
    -- 20 .. 29
  , "t20" := T 20
  , "t21" := T 21
  , "t22" := T 22
  , "t23" := T 23
  , "t24" := T 24
  , "t25" := T 25
  , "t26" := T 26
  , "t27" := T 27
  , "t28" := T 28
  , "t29" := T 29
    -- 30 .. 39
  , "t30" := T 30
  , "t31" := T 31
  , "t32" := T 32
  , "t33" := T 33
  , "t34" := T 34
  , "t35" := T 35
  , "t36" := T 36
  , "t37" := T 37
  , "t38" := T 38
  , "t39" := T 39
    -- 40 .. 49
  , "t40" := T 40
  , "t41" := T 41
  , "t42" := T 42
  , "t43" := T 43
  , "t44" := T 44
  , "t45" := T 45
  , "t46" := T 46
  , "t47" := T 47
  , "t48" := T 48
  , "t49" := T 49
  ]
