{-# LANGUAGE CPP       #-}
{-# LANGUAGE DataKinds #-}

#ifdef USE_GHC_DUMP
{-# OPTIONS_GHC -fplugin GhcDump.Plugin #-}
#endif

-- NOTE: NoFieldSelectors is not useful here: when declaring a record,
-- NoFieldSelectors will /still/ create field selectors, they just won't
-- pollute the namespace (they will be used for HasField instances though).

module Test.Record.Experiments.SimpleRecord.SR030 where

import Test.Record.Size.Infra

data R = MkR {
      -- 1 .. 10
      field1  :: T 1
    , field2  :: T 2
    , field3  :: T 3
    , field4  :: T 4
    , field5  :: T 5
    , field6  :: T 6
    , field7  :: T 7
    , field8  :: T 8
    , field9  :: T 9
    , field10 :: T 10
      -- 11 .. 20
    , field11 :: T 11
    , field12 :: T 12
    , field13 :: T 13
    , field14 :: T 14
    , field15 :: T 15
    , field16 :: T 16
    , field17 :: T 17
    , field18 :: T 18
    , field19 :: T 19
    , field20 :: T 20
      -- 21 .. 30
    , field21 :: T 21
    , field22 :: T 22
    , field23 :: T 23
    , field24 :: T 24
    , field25 :: T 25
    , field26 :: T 26
    , field27 :: T 27
    , field28 :: T 28
    , field29 :: T 29
    , field30 :: T 30
    }
