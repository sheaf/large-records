#if PROFILE_CORESIZE
{-# OPTIONS_GHC -ddump-to-file -ddump-ds-preopt -ddump-ds -ddump-simpl #-}
#endif
#if PROFILE_TIMING
{-# OPTIONS_GHC -ddump-to-file -ddump-timings #-}
#endif

{-# OPTIONS_GHC -fplugin=TypeLet -fplugin=Data.Record.Anonymous.Plugin #-}
{-# OPTIONS_GHC -fplugin-opt=Data.Record.Anonymous.Plugin:typelet #-}

module Experiment.ConstructWithTypelet.Sized.R030 where

import Data.Record.Anonymous.Simple (Record)

import Bench.Types
import Common.RowOfSize.Row030

record :: Record Row
record = ANON {
      -- 00 .. 09
      t00 = MkT 00
    , t01 = MkT 01
    , t02 = MkT 02
    , t03 = MkT 03
    , t04 = MkT 04
    , t05 = MkT 05
    , t06 = MkT 06
    , t07 = MkT 07
    , t08 = MkT 08
    , t09 = MkT 09
      -- 10 .. 19
    , t10 = MkT 10
    , t11 = MkT 11
    , t12 = MkT 12
    , t13 = MkT 13
    , t14 = MkT 14
    , t15 = MkT 15
    , t16 = MkT 16
    , t17 = MkT 17
    , t18 = MkT 18
    , t19 = MkT 19
      -- 20 .. 29
    , t20 = MkT 20
    , t21 = MkT 21
    , t22 = MkT 22
    , t23 = MkT 23
    , t24 = MkT 24
    , t25 = MkT 25
    , t26 = MkT 26
    , t27 = MkT 27
    , t28 = MkT 28
    , t29 = MkT 29
    }