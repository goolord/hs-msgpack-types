{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DerivingStrategies #-}

module Data.MessagePack.Types.Object
  ( Object (..)
  ) where

import           Control.Applicative       ((<$>), (<*>))
import           Control.DeepSeq           (NFData (..))
import qualified Data.ByteString           as S
import           Data.Int                  (Int64)
import qualified Data.Text                 as T
import           Data.Typeable             (Typeable)
import           Data.Word                 (Word64, Word8)
import           GHC.Generics              (Generic)
import           Test.QuickCheck.Arbitrary (Arbitrary(..), Arbitrary1(..), shrink1, arbitrary1)
import qualified Test.QuickCheck.Gen       as Gen
import qualified Data.Vector               as V


-- | Object Representation of MessagePack data.
data Object
  = ObjectNil
    -- ^ represents nil
  | ObjectBool                  !Bool
    -- ^ represents true or false
  | ObjectInt    {-# UNPACK #-} !Int64
    -- ^ represents a negative integer
  | ObjectWord   {-# UNPACK #-} !Word64
    -- ^ represents a positive integer
  | ObjectFloat  {-# UNPACK #-} !Float
    -- ^ represents a floating point number
  | ObjectDouble {-# UNPACK #-} !Double
    -- ^ represents a floating point number
  | ObjectStr                   !T.Text
    -- ^ extending Raw type represents a UTF-8 string
  | ObjectBin                   !S.ByteString
    -- ^ extending Raw type represents a byte array
  | ObjectArray                 !(V.Vector Object)
    -- ^ represents a sequence of objects
  | ObjectMap                   !(V.Vector (Object, Object))
    -- ^ represents key-value pairs of objects
  | ObjectExt    {-# UNPACK #-} !Word8 !S.ByteString
    -- ^ represents a tuple of an integer and a byte array where
    -- the integer represents type information and the byte array represents data.
  deriving (Read, Show, Eq, Ord, Typeable, Generic)

instance NFData Object

instance Arbitrary a => Arbitrary (V.Vector a) where
  arbitrary = arbitrary1
  shrink = shrink1

instance Arbitrary1 V.Vector where
    liftArbitrary = fmap V.fromList . liftArbitrary
    liftShrink shr = fmap V.fromList . liftShrink shr . V.toList

instance Arbitrary Object where
  arbitrary = Gen.sized $ \n -> Gen.oneof
    [ return ObjectNil
    , ObjectBool   <$> arbitrary
    , ObjectInt    <$> negatives
    , ObjectWord   <$> arbitrary
    , ObjectFloat  <$> arbitrary
    , ObjectDouble <$> arbitrary
    , ObjectStr    <$> (T.pack <$> arbitrary)
    , ObjectBin    <$> (S.pack <$> arbitrary)
    , ObjectArray  <$> Gen.resize (n `div` 2) arbitrary
    , ObjectMap    <$> Gen.resize (n `div` 4) arbitrary
    , ObjectExt    <$> arbitrary <*> (S.pack <$> arbitrary)
    ]
    where 
    negatives = Gen.choose (minBound, -1)
