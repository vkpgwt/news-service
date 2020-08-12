{-# LANGUAGE RecordWildCards #-}

-- | High-level interface to dynamic configuration data (configuration
-- files, command line parameters etc). It should only allow getting
-- and parsing settings to simple data types as they are, neither
-- providing default values nor parsing to library-specific types.
module Config
  ( getConfig
  , Config(..)
  ) where

import Control.Exception.Sync
import Control.Monad.Trans.Class
import Control.Monad.Trans.Reader
import qualified Data.Configurator as C
import qualified Data.Configurator.Types as C
import qualified Data.HashMap.Lazy as LHM
import Data.Ratio
import Data.Word
import System.Environment
import System.Exit
import Text.Printf

-- | Whole configuration data.
data Config =
  Config
    { cfServerPort :: Maybe Int
    , cfServerHostPreference :: Maybe String
    , cfServerName :: Maybe String
    , cfDatabaseName :: String
    , cfDatabaseHost :: Maybe String
    , cfDatabasePort :: Maybe Word16
    , cfDatabaseUser :: Maybe String
    , cfDatabasePassword :: Maybe String
    , cfLoggerVerbosity :: Maybe String
    , cfLogFilePath :: Maybe String
    }
  deriving (Show)

-- | Loads and parses configuration data from all sources
-- (configuration files etc).
getConfig :: IO Config
getConfig = do
  conf <- loadConfigFile
  runReaderT parseConfig conf `catchS` \(C.KeyError key) ->
    die $ printf "Configuration option '%v' is missing" key

parseConfig :: ReaderT C.Config IO Config
parseConfig = do
  cfServerPort <- lookupOpt "server.port"
  cfServerHostPreference <- lookupOpt "server.host"
  cfServerName <- lookupOpt "server.name"
  cfDatabaseName <- require "postgresql.databaseName"
  cfDatabaseHost <- lookupOpt "postgresql.host"
  cfDatabasePort <- fmap getStricterIntegral <$> lookupOpt "postgresql.port"
  cfDatabaseUser <- lookupOpt "postgresql.user"
  cfDatabasePassword <- lookupOpt "postgresql.password"
  cfLoggerVerbosity <- lookupOpt "log.verbosity"
  cfLogFilePath <- lookupOpt "log.path"
  pure Config {..}

loadConfigFile :: IO C.Config
loadConfigFile = do
  paths <- getConfigPaths
  C.load $ map C.Required paths

getConfigPaths :: IO [FilePath]
getConfigPaths = do
  args <- getArgs
  case args of
    ("--config":path:_) -> pure [path]
    _ -> pure []

lookupOpt :: (C.Configured a) => C.Name -> ReaderT C.Config IO (Maybe a)
lookupOpt key = do
  hmap <- lift . C.getMap =<< ask
  case LHM.lookup key hmap of
    Nothing -> pure Nothing
    Just rawValue ->
      case C.convert rawValue of
        Nothing -> lift $ rejectValue rawValue
        Just v -> pure $ Just v
  where
    rejectValue value =
      die $
      printf
        "Configuration option '%v' is assigned an incorrect value: '%v'"
        key
        (show value)

require :: (C.Configured a) => C.Name -> ReaderT C.Config IO a
require key = do
  conf <- ask
  lift $ C.require conf key

-- | An integral type wrapper with a stricter decoding policy. It
-- tries to decode a value without loss of precision. Normally, trying
-- to represent 9999999 as 'Word16' results in something like 16959,
-- which is unsafe when dealing with configuration files.
newtype StricterIntegral a =
  StricterIntegral
    { getStricterIntegral :: a
    }

instance Integral a => C.Configured (StricterIntegral a) where
  convert (C.Number n)
    | denominator n == 1 =
      StricterIntegral <$> fromIntegerReversibly (numerator n)
    | otherwise = Nothing
  convert _ = Nothing

fromIntegerReversibly :: (Integral a) => Integer -> Maybe a
fromIntegerReversibly a =
  let r = fromInteger a
   in if a == toInteger r
        then Just r
        else Nothing