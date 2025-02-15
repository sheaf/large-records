{-# LANGUAGE CPP             #-}
{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ViewPatterns    #-}

#if NOFIELDSELECTORS
{-# LANGUAGE NoFieldSelectors #-}
#endif

#ifdef USE_GHC_DUMP
{-# OPTIONS_GHC -fplugin GhcDump.Plugin #-}
#endif

{-# OPTIONS_GHC -ddump-simpl #-}

module Test.Record.Experiments.PatternSynonym.PS060 where

import Test.Record.Size.Infra

data R

viewR :: R -> (
      (T 00, T 01, T 02, T 03, T 04, T 05, T 06, T 07, T 08, T 09)
    , (T 10, T 11, T 12, T 13, T 14, T 15, T 16, T 17, T 18, T 19)
    , (T 20, T 21, T 22, T 23, T 24, T 25, T 26, T 27, T 28, T 29)
    , (T 30, T 31, T 32, T 33, T 34, T 35, T 36, T 37, T 38, T 39)
    , (T 40, T 41, T 42, T 43, T 44, T 45, T 46, T 47, T 48, T 49)
    , (T 50, T 51, T 52, T 53, T 54, T 55, T 56, T 57, T 58, T 59)
    )
viewR = undefined

pattern MkR ::
     T 00 -> T 01 -> T 02 -> T 03 -> T 04 -> T 05 -> T 06 -> T 07 -> T 08 -> T 09
  -> T 10 -> T 11 -> T 12 -> T 13 -> T 14 -> T 15 -> T 16 -> T 17 -> T 18 -> T 19
  -> T 20 -> T 21 -> T 22 -> T 23 -> T 24 -> T 25 -> T 26 -> T 27 -> T 28 -> T 29
  -> T 30 -> T 31 -> T 32 -> T 33 -> T 34 -> T 35 -> T 36 -> T 37 -> T 38 -> T 39
  -> T 40 -> T 41 -> T 42 -> T 43 -> T 44 -> T 45 -> T 46 -> T 47 -> T 48 -> T 49
  -> T 50 -> T 51 -> T 52 -> T 53 -> T 54 -> T 55 -> T 56 -> T 57 -> T 58 -> T 59
  -> R
pattern MkR {
      x00, x01, x02, x03, x04, x05, x06, x07, x08, x09
    , x10, x11, x12, x13, x14, x15, x16, x17, x18, x19
    , x20, x21, x22, x23, x24, x25, x26, x27, x28, x29
    , x30, x31, x32, x33, x34, x35, x36, x37, x38, x39
    , x40, x41, x42, x43, x44, x45, x46, x47, x48, x49
    , x50, x51, x52, x53, x54, x55, x56, x57, x58, x59
    } <- (viewR -> (
             (x00, x01, x02, x03, x04, x05, x06, x07, x08, x09)
           , (x10, x11, x12, x13, x14, x15, x16, x17, x18, x19)
           , (x20, x21, x22, x23, x24, x25, x26, x27, x28, x29)
           , (x30, x31, x32, x33, x34, x35, x36, x37, x38, x39)
           , (x40, x41, x42, x43, x44, x45, x46, x47, x48, x49)
           , (x50, x51, x52, x53, x54, x55, x56, x57, x58, x59)
           )
         )

