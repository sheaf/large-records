{-# LANGUAGE BangPatterns    #-}
{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE LambdaCase      #-}
{-# LANGUAGE NamedFieldPuns  #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections   #-}

-- | Code generation
module Data.Record.TH.CodeGen (
    largeRecord
  ) where

import Control.Monad (forM)
import Data.List (nub)
import Data.Maybe (catMaybes)
import Data.Proxy
import Data.Vector (Vector)
import GHC.Exts (Any)
import GHC.Records.Compat
import Language.Haskell.TH hiding (TyVarBndr(..), forallC, forallT)
import Language.Haskell.TH.Syntax (NameSpace(..))
import Unsafe.Coerce (unsafeCoerce)

import qualified Data.Generics              as SYB
import qualified Data.Kind                  as Kind
import qualified Data.Vector                as V
import qualified GHC.Generics               as GHC
import qualified Language.Haskell.TH.Syntax as TH

import Data.Record.Generic
import Data.Record.Generic.Eq
import Data.Record.Generic.GHC
import Data.Record.Generic.Show

import Data.Record.Internal.CodeGen
import Data.Record.Internal.Naming
import Data.Record.Internal.Record
import Data.Record.Internal.Record.Parser
import Data.Record.Internal.TH.Compat
import Data.Record.Internal.TH.Util
import Data.Record.Internal.Util
import Data.Record.TH.Config.Options
import Data.Record.TH.Runtime

import qualified Data.Record.Generic.Rep.Internal as Rep
import qualified Data.Record.Internal.TH.Name as N

{-------------------------------------------------------------------------------
  Public API
-------------------------------------------------------------------------------}

-- | Declare a large record
--
-- Example usage:
--
-- > largeRecord defaultPureScript [d|
-- >     data R a = MkR { x :: Int, y :: [a] } deriving (Eq, Show)
-- >     data S a = S   { x :: Int, y :: [a] } deriving (Eq, Show)
-- >   |]
largeRecord :: Options -> Q [Dec] -> Q [Dec]
largeRecord opts decls = do
    rs <- mapM parseRecordDef . dropUniques =<< decls
    concatMapM (genAll opts) (catMaybes rs)

{-------------------------------------------------------------------------------
  Top-level
-------------------------------------------------------------------------------}

-- | Generate all definitions
genAll :: Options -> (Record (), RecordInstances) -> Q [Dec]
genAll opts@Options{..} (r, instances) = concatM $ [
      (:[]) <$> genDatatype opts r instances
    , genVectorConversions opts r
    , genIndexedAccessor   opts r
    , genIndexedOverwrite  opts r
    , when generateHasFieldInstances $ [
          genHasFieldInstances opts r
        ]
    , genGenericInstance opts r instances
    , genGhcGenericsInstances opts r
    ]
  where
    when :: Bool -> [Q [Dec]] -> Q [Dec]
    when False _   = return []
    when True  gen = concatM gen

{-------------------------------------------------------------------------------
  Generation: the type itself

  NOTE: All generation exampleshask assume as example

  > data T a b = MkT {
  >       tWord  :: Word
  >     , tBool  :: Bool
  >     , tChar  :: Char
  >     , tA     :: a
  >     , tListB :: [b]
  >     }
  >   deriving (Eq, Show)
-------------------------------------------------------------------------------}

-- | Generate the datatype that will represent the record
--
-- Currently this generates something like
--
-- > data T a b =
-- >      forall f0 f1 f2 f3 f4. (
-- >        f0 ~ Word
-- >      , f1 ~ Bool
-- >      , f2 ~ Char
-- >      , f3 ~ a
-- >      , f4 ~ [b]
-- >      )
-- >   => MkT {
-- >        tInt   :: f0
-- >      , tBool  :: f1
-- >      , tChar  :: f2
-- >      , tA     :: f3
-- >      , tListB :: f4
-- >      }
-- >   deriving anyclass C -- where applicable
--
-- (possibly with strict fields). This representation accomplishes two things:
--
-- 1. The use of the existentials with type equalities prevents ghc from
--    generating field accessors.
-- 2. It can still be used in the normal way to construct record values and
--    to pattern match on records.
--
-- TODO: From ghc 9.2 and up, we should generate
--
-- > newtype T a b = TFromVector {vectorFromT :: Vector Any}
-- >   deriving anyclass C -- where applicable
--
-- instead, along with a pattern synonym.
genDatatype :: Options -> Record () -> RecordInstances -> Q Dec
genDatatype Options{allFieldsStrict}
            Record{..}
            RecordInstances{recordInstancesAnyclass} = do
    requiresExtensions [ExistentialQuantification]
    vars <- forM recordFields $ \f -> (f, ) <$> N.newName "f"
    N.dataD
      (cxt [])
      (N.unqualified recordType)
      recordTVars
      Nothing
      [ forallC (map (N.plainLocalTV . snd) vars) (cxt $ map (uncurry eqConstraint) vars) $
          N.recC (N.unqualified recordConstr) $
            map (uncurry recordField) vars
      ]
      (map anyclassDerivClause recordInstancesAnyclass)
  where
    eqConstraint :: Field () -> N.Name 'VarName 'N.Unique -> Q Pred
    eqConstraint Field{..} var =
        [t| $(N.varLocalT var) ~ $(return fieldType) |]

    recordField :: Field () -> N.Name 'VarName 'N.Unique -> Q TH.VarBangType
    recordField Field{..} var =
        N.varBangType (N.unqualified fieldName) $
          bangType (return fieldBang) (N.varLocalT var)
      where
        fieldBang :: Bang
        fieldBang = if allFieldsStrict then StrictBang else DefaultBang

    anyclassDerivClause :: Type -> DerivClauseQ
    anyclassDerivClause clss =
        derivClause (Just AnyclassStrategy) [pure clss]

-- | Generate conversion to and from vector
--
-- Generates something like
--
-- > vectorFromT :: T a b -> Vector Any
-- > vectorFromT = \x ->
-- >     case x of
-- >       MkT f0 f1 f2 f3 f4 -> V.fromList [
-- >           unsafeCoerce f0
-- >         , unsafeCoerce f1
-- >         , unsafeCoerce f2
-- >         , unsafeCoerce f3
-- >         , unsafeCoerce f4
-- >         ]
-- >
-- > vectorToT :: Vector Any -> T a b
-- > vectorToT = \x ->
-- >     case V.toList x of
-- >       [f0, f1, f2, f3, f4] ->
-- >         MkT (unsafeCoerce f0)
-- >             (unsafeCoerce f1)
-- >             (unsafeCoerce f2)
-- >             (unsafeCoerce f3)
-- >             (unsafeCoerce f4)
-- >       _ -> error "Pattern match failure in vectorToT: vector with invalid number of elements."
--
-- TODO: From ghc 9.2, these could be identify functions. See 'genDatatype'
-- for details.
genVectorConversions :: Options -> Record () -> Q [Dec]
genVectorConversions _ r@Record{..} = concatM [
      simpleFn
        (N.unqualified (nameRecordVectorFrom recordType))
        [t| $(recordTypeT N.Unqual r) -> Vector Any |]
        bodyToVector
    , simpleFn
        (N.unqualified (nameRecordVectorTo recordType))
        [t| Vector Any -> $(recordTypeT N.Unqual r) |]
        bodyFromVector
    ]
  where
    bodyToVector :: Q Exp
    bodyToVector = do
        x  <- newName "x"
        fs <- forM recordFields $ \_f -> newName "f"

        let pat :: Q Pat
            pat = N.conP (N.unqualified recordConstr) $ map varP fs

            body :: Q Exp
            body = appE (varE 'V.fromList) . listE $
                     map (unsafeCoerceE . varE) fs

        lamE [varP x] $ caseE (varE x) [
            match pat (normalB body) []
          ]

    bodyFromVector :: Q Exp
    bodyFromVector = do
        x  <- newName "x"
        fs <- forM recordFields $ \_f -> newName "f"

        let pat :: Q Pat
            pat = listP $ map varP fs

            bodyErr, bodyOk :: Q Exp
            bodyErr = appE (varE 'error) . litE . stringL $ concat [
                          "Pattern match failure in "
                        , nameRecordVectorTo recordType
                        , ": vector with invalid number of elements."
                        ]
            bodyOk  = appsE $ N.conE (N.unqualified recordConstr)
                            : map (unsafeCoerceE . varE) fs

        lamE [varP x] $ caseE (appE (varE 'V.toList) (varE x)) [
              match pat   (normalB bodyOk)  []
            , match wildP (normalB bodyErr) []
            ]

    unsafeCoerceE :: Q Exp -> Q Exp
    unsafeCoerceE = appE (varE 'unsafeCoerce)

{-------------------------------------------------------------------------------
  Generation: field accessors

  TODO: If we had support within GHC itself for accessing fields in records,
  we might be able to integrate this a lot more closely with normal GHC,
  especially when combined with the @NoFieldSelectors@ extension.

  See <https://gitlab.haskell.org/ghc/ghc/-/issues/17991>
-------------------------------------------------------------------------------}

-- | Generate the indexed field accessor
--
-- Generates something like
--
-- > unsafeGetIndexT :: forall x a b. Int -> T a b -> x
-- > unsafeGetIndexT = \ n t -> noInlineUnsafeCo (V.unsafeIndex (vectorFromT t) n)
genIndexedAccessor :: Options -> Record () -> Q [Dec]
genIndexedAccessor _opts r@Record{..} = do
    x <- newName "x"
    simpleFn
      (N.unqualified (nameRecordIndexedAccessor recordType))
      (forallT
         (PlainTV x : recordTVars)
         (cxt [])
         (arrT [conT ''Int, recordTypeT N.Unqual r] (varT x)))
      [| \n t -> noInlineUnsafeCo $
           V.unsafeIndex ($(recordToVectorE N.Unqual r) t) n
      |]

-- | Generate index field overwrite
--
-- Generates something like
--
-- > unsafeSetIndexT :: forall x a b. Int -> T a b -> x -> T a b
-- > unsafeSetIndexT = \n t val ->
-- >     TFromVector (V.unsafeUpd (vectorFromT t) [(n, noInlineUnsafeCo val)])
--
-- If using 'allFieldsStrict', the function will be strict in @val@.
--
-- TODO: We should support per-field strictness.
genIndexedOverwrite :: Options -> Record () -> Q [Dec]
genIndexedOverwrite Options{allFieldsStrict} r@Record{..} = do
    x <- newName "x"
    simpleFn
      (N.unqualified (nameRecordIndexedOverwrite recordType))
      (forallT
        (PlainTV x : recordTVars)
        (cxt [])
        (arrT
          [conT ''Int, recordTypeT N.Unqual r, varT x]
          (recordTypeT N.Unqual r))
        )
      body
  where
    body :: Q Exp
    body
      | allFieldsStrict =
          [| \n t !val -> $fromVector (
                 V.unsafeUpd ($(recordToVectorE N.Unqual r) t)
                   [(n, noInlineUnsafeCo val)]
               )
           |]
      | otherwise =
          [| \n t val -> $fromVector (
                 V.unsafeUpd ($(recordToVectorE N.Unqual r) t)
                   [(n, noInlineUnsafeCo val)]
               )
           |]

    fromVector :: Q Exp
    fromVector = recordFromVectorDontForceE N.Unqual r

-- | Generate 'HasField' instances for all fields
genHasFieldInstances :: Options -> Record () -> Q [Dec]
genHasFieldInstances opts r@Record{..} =
    mapM (genHasFieldInstance opts r) recordFields

-- | Generate 'HasField' instance for single field
--
-- Generates something like
--
-- > instance x ~ Word => HasField "tInt" (T a b) x where
-- >   hasField = \t -> (unsafeSetIndexT 0 t, unsafeGetIndexT 0 t)
genHasFieldInstance :: Options -> Record () -> Field () -> Q Dec
genHasFieldInstance _opts r f = do
    requiresExtensions [
        DataKinds
      , FlexibleInstances
      , MultiParamTypeClasses
      , TypeFamilies
      , UndecidableInstances
      ]
    x <- newName "x"
    instanceD
      (cxt [equalityT `appT` varT x `appT` fieldTypeT f])
      (appsT (conT ''HasField) [
          fieldNameT f
        , recordTypeT N.Unqual r
        , varT x
        ])
      [valD (varP 'hasField) (normalB [|
          \t -> ( $(fieldUntypedOverwriteE N.Unqual r f) t
                , $(fieldUntypedAccessorE  N.Unqual r f) t
                )
        |]) []]

{-------------------------------------------------------------------------------
  Generation: type-level metadata
-------------------------------------------------------------------------------}

-- | Generate type-level metadata
--
-- Generates something like
--
-- > type MetadataOf (T a b) = '[
-- >     '("tInt", Word),
-- >   , '("tBool", Bool),
-- >   , '("tChar", Char),
-- >   , '("tA", a),
-- >   , '("tListB", [b])
-- >   ]
--
-- NOTE: We do not use type-level lists in most places, since it's difficult
-- to avoid quadratic core code size when working with type-level list. We use
-- this meta-data currently for two purposes only:
--
-- * The 'lr' quasi-quoter uses it as a way to lookup the record definition.
--   See "Data.Record.Internal.RecordInfo.Resolution.GHC".
-- * We use it to put a constraint on 'normalize'; this constraint is carefully
--   defined to avoid quadratic core code size.
--   See "Data.Record.Generic.Transform".
genInstanceMetadataOf :: Options -> Record () -> Q Dec
genInstanceMetadataOf _opts r@Record{..} = tySynInstD $
    tySynEqn
      Nothing
      [t| MetadataOf $(recordTypeT N.Unqual r) |]
      (plistT $ map fieldMetadata recordFields)
  where
    fieldMetadata :: Field () -> Q Type
    fieldMetadata f = ptupleT [fieldNameT f, fieldTypeT f]

{-------------------------------------------------------------------------------
  Generation: Generic instance
-------------------------------------------------------------------------------}

-- | Generate the class we will use to instantiate 'Constraints'
--
-- Generates something like this:
--
-- > class Constraints_T a b (c :: Type -> Constraint) where
-- >   dictConstraints_T :: Proxy c -> Rep (Dict c) (T a b)
--
-- NOTE: It is critical that we don't give the class any superclass constraints
-- like
--
-- > class (c Word, c Bool, c Char, c a, c [b])
-- >    => Constraints_T a b (c :: Type -> Constraint)
--
-- because then @ghc@ would use resolve @Constraints_T@ to that tuple instead,
-- and use lots of "tuple constraint extractor" functions, each of which have
-- the same size as the number of constraints (another example of a
-- @case f of { T x1 x2 x3 .. -> xn@ function, but now at the dictionary level).
genConstraintsClass :: Options -> Record () -> Q Dec
genConstraintsClass _opts r@Record{..} = do
    requiresExtensions [KindSignatures, ConstraintKinds]
    c <- newName "c"
    k <- [t| Kind.Type -> Kind.Constraint |]
    N.classD
      (cxt [])
      (N.unqualified (nameRecordConstraintsClass recordType))
      (recordTVars ++ [KindedTV c k])
      []
      [ N.sigD (N.unqualified (nameRecordConstraintsMethod recordType)) [t|
            Proxy $(varT c) -> Rep (Dict $(varT c)) $(recordTypeT N.Unqual r)
          |]
      ]

-- | Superclass constraints required by the constraints class instance
--
-- Generates something like
--
-- > (c Word, c Bool, c Char, c a, c [b])
--
-- However, we filter out constraints that are type variable free, so if we
-- pass, say, @Show@ for @c@, then we generate
--
-- > (Show a, Show [b])
--
-- instead. This avoids @ghc@ complaining about
--
-- > Redundant constraints: (Show Word, Show Bool, Show Char)
genRequiredConstraints :: Options -> Record () -> Q Type -> Q Cxt
genRequiredConstraints _opts Record{..} c = do
    requiresExtensions [FlexibleContexts]
    constraints <- mapM constrainField recordFields
    return $ nub $ filter hasTypeVar constraints
  where
    constrainField :: Field () -> Q Pred
    constrainField f = c `appT` fieldTypeT f

    hasTypeVar :: Pred -> Bool
    hasTypeVar = SYB.everything (||) (SYB.mkQ False isTypeVar)

    isTypeVar :: Type -> Bool
    isTypeVar (VarT _)   = True
    isTypeVar _otherwise = False

-- | Generate the dictionary creation function ('dict')
--
-- Generates something like
--
-- > \p -> Rep (V.fromList [
-- >     noInlineUnsafeCo (dictFor p (Proxy :: Proxy Word))
-- >   , noInlineUnsafeCo (dictFor p (Proxy :: Proxy Bool))
-- >   , noInlineUnsafeCo (dictFor p (Proxy :: Proxy Char))
-- >   , noInlineUnsafeCo (dictFor p (Proxy :: Proxy a))
-- >   , noInlineUnsafeCo (dictFor p (Proxy :: Proxy [b]))
-- >   ])
genDict :: Options -> Record () -> Q Exp
genDict _opts Record{..} = do
    p <- newName "p"
    lamE [varP p] [| Rep $(vectorE (dictForField p) recordFields) |]
  where
    dictForField :: Name -> Field () -> Q Exp
    dictForField p f = [|
          noInlineUnsafeCo (dictFor $(varE p) (Proxy :: Proxy $(fieldTypeT f)))
        |]

-- | Generate (one and only) instance of the constraints class
--
-- Generates something like
--
-- > instance (..) => Constraints_T a b c where
-- >   dictConstraints_T = ..
--
-- where the body of @dictConstraints_T@ is generated by 'genDict'.
genConstraintsClassInstance :: Options -> Record () -> Q Dec
genConstraintsClassInstance opts r@Record{..} = do
    requiresExtensions [ScopedTypeVariables]
    c <- newName "c"
    instanceD
      (genRequiredConstraints opts r (varT c))
      (appsT (N.conT (N.unqualified (nameRecordConstraintsClass recordType))) $
         map tyVarType recordTVars ++ [varT c])
      [ valD (N.varGlobalP (N.unqualified (nameRecordConstraintsMethod recordType)))
             (normalB (genDict opts r))
             []
      ]

-- | Generate the Constraints type family instance
--
-- Generates something like
--
-- > type Constraints (T a b) = Constraints_T a b
genInstanceConstraints :: Options -> Record () -> Q Dec
genInstanceConstraints _opts r@Record{..} = tySynInstD $
    tySynEqn
      Nothing
      [t| Constraints $(recordTypeT N.Unqual r) |]
      (appsT (N.conT (N.unqualified (nameRecordConstraintsClass recordType))) $
         map tyVarType recordTVars)

-- | Generate metadata
--
-- Generates something like
--
-- > \_p  -> Metadata {
-- >     recordName          = "T"
-- >   , recordConstructor   = "MkT"
-- >   , recordSize          = 5
-- >   , recordFieldMetadata = Rep $ V.fromList [
-- >         FieldMetadata (Proxy :: Proxy "tInt"))   FieldLazy
-- >       , FieldMetadata (Proxy :: Proxy "tBool"))  FieldLazy
-- >       , FieldMetadata (Proxy :: Proxy "tChar"))  FieldLazy
-- >       , FieldMetadata (Proxy :: Proxy "tA"))     FieldLazy
-- >       , FieldMetadata (Proxy :: Proxy "tListB")) FieldLazy
-- >       ]
-- >   }
genMetadata :: Options -> Record () -> Q Exp
genMetadata Options{..} r@Record{..} = do
    p <- newName "_p"
    lamE [varP p] $ recConE 'Metadata [
        fieldExp 'recordName          $ recordTypeE r
      , fieldExp 'recordConstructor   $ recordConstrE r
      , fieldExp 'recordSize          $ litE (integerL numFields)
      , fieldExp 'recordFieldMetadata $ [| Rep.Rep $ V.fromList $fieldMetadata |]
      ]
  where
    numFields :: Integer
    numFields = fromIntegral $ length recordFields

    fieldMetadata :: Q Exp
    fieldMetadata = listE $ map mkFieldMetadata recordFields

    mkFieldMetadata :: Field () -> ExpQ
    mkFieldMetadata f = [|
          FieldMetadata
            (Proxy :: Proxy $(fieldNameT f) )
            $(if allFieldsStrict
                then [| FieldStrict |]
                else [| FieldLazy   |])
        |]

-- | Generate instance for specific class
--
-- Generates one of the following:
--
-- * 'Show':
--
--   > instance (..) => Eq (T a b) where
--   >   (==) = geq
--
-- * 'Eq':
--
--   > instance (..) => Show (T a b) where
--   >   showsPrec = gshowsPrec
--
-- where the @(..)@ constraints are generated by 'genRequiredConstraints'
-- (i.e., a constraint for each field).
--
-- TODO: Think about DeriveFunctor?
genDeriving :: Options -> Record () -> Deriving -> Q Dec
genDeriving opts r = \case
    DeriveEq    -> inst ''Eq   '(==)      'geq
    DeriveOrd   -> inst ''Ord  'compare   'gcompare
    DeriveShow  -> inst ''Show 'showsPrec 'gshowsPrec
  where
    inst :: Name -> Name -> Name -> Q Dec
    inst clss fn gfn =
        instanceD
          (genRequiredConstraints opts r (conT clss))
          [t| $(conT clss) $(recordTypeT N.Unqual r) |]
          [valD (varP fn) (normalB (varE gfn)) []]

-- | Generate definition for `from` in the `Generic` instance
--
-- Generates something like
--
-- > repFromVectorStrict . vectorFromT
genFrom :: Options -> Record () -> Q Exp
genFrom _opts Record{..} = [|
         repFromVector
       . $(N.varE (N.unqualified (nameRecordVectorFrom recordType)))
    |]

-- | Generate definition for `to` in the `Generic` instance
--
-- > (..) . repToVector
--
-- where the @(..)@ is generated by 'recordFromVectorForceStrictFieldsE'
-- (which will any strict fields in the vector).
genTo :: Options -> Record () -> Q Exp
genTo opts r = [|
        $(recordFromVectorForceStrictFieldsE opts r)
      . repToVector
    |]

-- | Generate the definitions required to provide the instance for 'Generic'
--
-- > instance Generic T where
-- >   type Constraints T = Constraints_T
-- >   from       = coerce
-- >   to         = coerce
-- >   dict       = dictConstraints_T
-- >   metadata   = ..
genGenericInstance :: Options -> Record () -> RecordInstances -> Q [Dec]
genGenericInstance opts r@Record{..} RecordInstances{recordInstancesDerived} =
    concatM [
         sequence [
             genConstraintsClass         opts r
           , genConstraintsClassInstance opts r
           , instanceD
               (cxt [])
               [t| Generic $(recordTypeT N.Unqual r) |]
               [ genInstanceConstraints opts r
               , genInstanceMetadataOf  opts r
               , valD (varP 'from)     (normalB $ genFrom opts r)                                                      []
               , valD (varP 'to)       (normalB $ genTo   opts r)                                                      []
               , valD (varP 'dict)     (normalB $ N.varE . N.unqualified . nameRecordConstraintsMethod $ recordType) []
               , valD (varP 'metadata) (normalB $ genMetadata opts r)                                                  []
               ]
           ]
      , mapM (genDeriving opts r) recordInstancesDerived
      ]

{-------------------------------------------------------------------------------
  GHC generics
-------------------------------------------------------------------------------}

-- | Generate GHC generics instance
--
-- Generates something like
--
-- > instance GHC.Generic ExampleRecord where
-- >   type Rep ExampleRecord = ThroughLRGenerics ExampleRecord
-- >
-- >   from = WrapThroughLRGenerics
-- >   to   = unwrapThroughLRGenerics
--
-- See 'ThroughLRGenerics' for documentation.

genGhcGenericsInstances :: Options -> Record () -> Q [Dec]
genGhcGenericsInstances _opts r = sequenceA [
      instanceD
        (cxt [])
        [t| GHC.Generic $(recordTypeT N.Unqual r) |]
        [ tySynInstD $
            tySynEqn
              Nothing
              [t| GHC.Rep $(recordTypeT N.Unqual r) |]
              [t| ThroughLRGenerics $(recordTypeT N.Unqual r) |]
        , valD (varP 'GHC.from) (normalB (conE 'WrapThroughLRGenerics))   []
        , valD (varP 'GHC.to)   (normalB (varE 'unwrapThroughLRGenerics)) []
        ]
    ]

{-------------------------------------------------------------------------------
  Auxiliary
-------------------------------------------------------------------------------}

-- | Construct record from the underlying @Vector Any@, forcing strict fields
--
-- Currently either /all/ fields are strict or /none/, so we either just force
-- all fields, or none of them.
--
-- See also 'recordFromVectorDontForceE'.
recordFromVectorForceStrictFieldsE :: Options -> Record () -> Q Exp
recordFromVectorForceStrictFieldsE Options{allFieldsStrict} r
  | allFieldsStrict = [| \v -> rnfVectorAny v `seq` $fromVector v |]
  | otherwise       =                                fromVector
  where
    fromVector :: Q Exp
    fromVector = recordFromVectorDontForceE N.Unqual r

{-------------------------------------------------------------------------------
  Fix TH naming

  TH distinguishes between global names (names from an explicit package/module),
  dynamically bound names that are resolved and bound after splicing in, and
  unique names, that are meant to be different from all other names.

  Specifically, 'mkName' is intended to create names that are meant to be
  capturable after splicing; 'mkName' generates dynamic names.

  For some strange reason however binder names of declarations in a @[d| ... |]@
  splice are given a unique name rather than a dynamic name. This is
  inconsistent, and complicates the already complicated story for correctly
  dealing with names. We therefore " fix " this here and makes those names
  dynamic.

  Since we are only interested in declaration splices containing /type/
  declarations, nothing else, it suffices to drop the uniques from type
  constructors. Type /variables/ can (and should) remain to have a unique
  flavour, as they are locally bound by the type declarations.
-------------------------------------------------------------------------------}

dropUniques :: [Dec] -> [Dec]
dropUniques = SYB.everywhere (SYB.mkT dropUnique)
  where
    dropUnique :: Type -> Type
    dropUnique (ConT n@(TH.Name occ flavour)) = ConT $
        case flavour of
          TH.NameU _ -> TH.Name occ TH.NameS
          _otherwise -> n
    dropUnique typ = typ
