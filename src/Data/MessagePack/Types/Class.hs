{-# LANGUAGE DefaultSignatures    #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE IncoherentInstances  #-}
{-# LANGUAGE LambdaCase           #-}
{-# LANGUAGE Trustworthy          #-}
{-# LANGUAGE TypeSynonymInstances #-}

--------------------------------------------------------------------
-- |
-- Module    : Data.MessagePack.Object
-- Copyright : (c) Hideyuki Tanaka, 2009-2015
-- License   : BSD3
--
-- Maintainer:  tanaka.hideyuki@gmail.com
-- Stability :  experimental
-- Portability: portable
--
-- MessagePack object definition
--
--------------------------------------------------------------------

module Data.MessagePack.Types.Class
  ( MessagePack (..)
  , GMessagePack (..)
  ) where

import           Control.Applicative           (Applicative, (<$>), (<*>))
import           Control.Arrow                 ((***))
import qualified Data.ByteString               as S
import qualified Data.ByteString.Lazy          as L
import           Data.Hashable                 (Hashable)
import qualified Data.HashMap.Strict           as HashMap
import           Data.Int                      (Int16, Int32, Int64, Int8)
import qualified Data.IntMap.Strict            as IntMap
import qualified Data.Map                      as Map
import qualified Data.Text                     as T
import qualified Data.Text.Lazy                as LT
import qualified Data.Vector                   as V
import qualified Data.Vector.Storable          as VS
import qualified Data.Vector.Unboxed           as VU
import           Data.Word                     (Word, Word16, Word32, Word64,
                                                Word8)
import           GHC.Generics

import           Data.MessagePack.Types.Assoc
import           Data.MessagePack.Types.Object


-- Generic serialisation.

class GMessagePack f where
  gToObject   :: f a -> Object
  gFromObject :: (Applicative m, Monad m) => Object -> m (f a)


class MessagePack a where
  toObject   :: a -> Object
  fromObject :: (Applicative m, Monad m) => Object -> m a

  default toObject :: (Generic a, GMessagePack (Rep a))
                   => a -> Object
  toObject = genericToObject
  default fromObject :: ( Applicative m, Monad m
                        , Generic a, GMessagePack (Rep a))
                     => Object -> m a
  fromObject = genericFromObject


genericToObject :: (Generic a, GMessagePack (Rep a))
                => a -> Object
genericToObject = gToObject . from

genericFromObject :: ( Applicative m, Monad m
                     , Generic a, GMessagePack (Rep a))
                  => Object -> m a
genericFromObject x = to <$> gFromObject x


-- Instances for integral types (Int etc.).

toInt :: Integral a => a -> Int64
toInt = fromIntegral

fromInt :: Integral a => Int64 -> a
fromInt = fromIntegral

toWord :: Integral a => a -> Word64
toWord = fromIntegral

fromWord :: Integral a => Word64 -> a
fromWord = fromIntegral

instance MessagePack Int64 where
  toObject i
    | i < 0 = ObjectInt i
    | otherwise = ObjectWord $ toWord i
  fromObject = \case
    ObjectInt n  -> return n
    ObjectWord n -> return $ toInt n
    _            -> fail "invalid encoding for integer type"

instance MessagePack Word64 where
  toObject = ObjectWord
  fromObject = \case
    ObjectWord n -> return n
    _            -> fail "invalid encoding for integer type"

instance MessagePack Int    where { toObject = toObject . toInt; fromObject o = fromInt <$> fromObject o }
instance MessagePack Int8   where { toObject = toObject . toInt; fromObject o = fromInt <$> fromObject o }
instance MessagePack Int16  where { toObject = toObject . toInt; fromObject o = fromInt <$> fromObject o }
instance MessagePack Int32  where { toObject = toObject . toInt; fromObject o = fromInt <$> fromObject o }

instance MessagePack Word   where { toObject = toObject . toWord; fromObject o = fromWord <$> fromObject o }
instance MessagePack Word8  where { toObject = toObject . toWord; fromObject o = fromWord <$> fromObject o }
instance MessagePack Word16 where { toObject = toObject . toWord; fromObject o = fromWord <$> fromObject o }
instance MessagePack Word32 where { toObject = toObject . toWord; fromObject o = fromWord <$> fromObject o }


-- Core instances.

instance MessagePack Object where
  toObject = id
  fromObject = return

instance MessagePack () where
  toObject _ = ObjectNil
  fromObject = \case
    ObjectNil      -> return ()
    ObjectArray v  -> if V.null v then return () else fail "invalid encoding for ()"
    _              -> fail "invalid encoding for ()"

instance MessagePack Bool where
  toObject = ObjectBool
  fromObject = \case
    ObjectBool b -> return b
    _            -> fail "invalid encoding for Bool"

instance MessagePack Float where
  toObject = ObjectFloat
  fromObject = \case
    ObjectInt    n -> return $ fromIntegral n
    ObjectWord   n -> return $ fromIntegral n
    ObjectFloat  f -> return f
    ObjectDouble d -> return $ realToFrac d
    _              -> fail "invalid encoding for Float"

instance MessagePack Double where
  toObject = ObjectDouble
  fromObject = \case
    ObjectInt    n -> return $ fromIntegral n
    ObjectWord   n -> return $ fromIntegral n
    ObjectFloat  f -> return $ realToFrac f
    ObjectDouble d -> return d
    _              -> fail "invalid encoding for Double"

-- Because of overlapping instance, this must be above [a].
-- IncoherentInstances and TypeSynonymInstances are required for this to work.
instance MessagePack String where
  toObject = toObject . T.pack
  fromObject obj = T.unpack <$> fromObject obj


-- Instances for binary and UTF-8 encoded string.

instance MessagePack S.ByteString where
  toObject = ObjectBin
  fromObject = \case
    ObjectBin r -> return r
    _           -> fail "invalid encoding for ByteString"

instance MessagePack L.ByteString where
  toObject = ObjectBin . L.toStrict
  fromObject obj = L.fromStrict <$> fromObject obj

instance MessagePack T.Text where
  toObject = ObjectStr
  fromObject = \case
    ObjectStr s -> return s
    _           -> fail "invalid encoding for Text"

instance MessagePack LT.Text where
  toObject = toObject . LT.toStrict
  fromObject obj = LT.fromStrict <$> fromObject obj


-- Instances for array-like data structures.

instance MessagePack a => MessagePack [a] where
  toObject = ObjectArray . fmap toObject . V.fromList
  fromObject = \case
    ObjectArray xs -> V.toList <$> mapM fromObject xs
    _              -> fail "invalid encoding for list"

instance MessagePack a => MessagePack (V.Vector a) where
  toObject = ObjectArray . fmap toObject
  fromObject = \case
    ObjectArray o -> mapM fromObject o
    _             -> fail "invalid encoding for Vector"

instance (MessagePack a, VU.Unbox a) => MessagePack (VU.Vector a) where
  toObject = ObjectArray . fmap toObject . VU.convert
  fromObject = \case
    ObjectArray o -> V.convert <$> mapM fromObject o
    _             -> fail "invalid encoding for Unboxed Vector"

instance (MessagePack a, VS.Storable a) => MessagePack (VS.Vector a) where
  toObject = ObjectArray . fmap toObject . VS.convert
  fromObject = \case
    ObjectArray o -> V.convert <$> mapM fromObject o
    _             -> fail "invalid encoding for Storable Vector"

-- Instances for map-like data structures.

instance (MessagePack a, MessagePack b) => MessagePack (Assoc [(a, b)]) where
  toObject (Assoc xs) = ObjectMap $ V.fromList $ fmap (toObject *** toObject) xs
  fromObject = \case
    ObjectMap xs ->
      Assoc <$> mapM (\(k, v) -> (,) <$> fromObject k <*> fromObject v) (V.toList xs)
    _ ->
      fail "invalid encoding for Assoc"

instance (MessagePack k, MessagePack v, Ord k) => MessagePack (Map.Map k v) where
  toObject = toObject . Assoc . Map.toList
  fromObject obj = Map.fromList . unAssoc <$> fromObject obj

instance MessagePack v => MessagePack (IntMap.IntMap v) where
  toObject = toObject . Assoc . IntMap.toList
  fromObject obj = IntMap.fromList . unAssoc <$> fromObject obj

instance (MessagePack k, MessagePack v, Hashable k, Eq k) => MessagePack (HashMap.HashMap k v) where
  toObject = toObject . Assoc . HashMap.toList
  fromObject obj = HashMap.fromList . unAssoc <$> fromObject obj


-- Instances for various tuple arities.

instance (MessagePack a1, MessagePack a2) => MessagePack (a1, a2) where
  toObject (a1, a2) = ObjectArray $ V.fromList [toObject a1, toObject a2]
  fromObject (ObjectArray as) = match (V.toList as)
    where
    match [a1,a2] = (,) <$> fromObject a1 <*> fromObject a2
    match _ = fail "invalid encoding for tuple"
  fromObject _ = fail "invalid encoding for tuple"

instance (MessagePack a1, MessagePack a2, MessagePack a3) => MessagePack (a1, a2, a3) where
  toObject (a1, a2, a3) = ObjectArray $ V.fromList [toObject a1, toObject a2, toObject a3]
  fromObject (ObjectArray as) = match (V.toList as)
    where
    match [a1, a2, a3] = (,,) <$> fromObject a1 <*> fromObject a2 <*> fromObject a3
    match _ = fail "invalid encoding for tuple"
  fromObject _ = fail "invalid encoding for tuple"

instance (MessagePack a1, MessagePack a2, MessagePack a3, MessagePack a4) => MessagePack (a1, a2, a3, a4) where
  toObject (a1, a2, a3, a4) = ObjectArray $ V.fromList [toObject a1, toObject a2, toObject a3, toObject a4]
  fromObject (ObjectArray as) = match (V.toList as)
    where
    match [a1, a2, a3, a4] = (,,,) <$> fromObject a1 <*> fromObject a2 <*> fromObject a3 <*> fromObject a4
    match _ = fail "invalid encoding for tuple"
  fromObject _ = fail "invalid encoding for tuple"

