{-# LANGUAGE RecordWildCards #-}

-- | The default implementation of the Logger interface.
module Logger.Impl
  ( new
  , Handle(..)
  ) where

import Control.Concurrent.STM.TQueue
import Control.Monad
import Control.Monad.STM
import Data.Maybe
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Data.Time
import qualified Logger
import Prelude hiding (log)
import qualified System.IO

data Handle =
  Handle
    { hFileHandle :: System.IO.Handle
    , hMinLevel :: Logger.Level
    }

-- | Creates an IO action and a logger handle. The IO action must be
-- forked in order for logging to work.
new :: Handle -> IO (IO (), Logger.Handle IO)
new Handle {..} = do
  queue <- newTQueueIO
  pure
    ( loggerWorker hFileHandle queue
    , Logger.Handle {Logger.hLowLevelLog = log hMinLevel queue})

data Message =
  Message
    { messageLevel :: Logger.Level
    , messageCallSite :: Maybe Logger.CallSite
    , messageText :: T.Text
    , messageTime :: UTCTime
    }

log ::
     Logger.Level
  -> TQueue Message
  -> Logger.Level
  -> Maybe Logger.CallSite
  -> T.Text
  -> IO ()
log minLevel queue level callSite text =
  when (minLevel <= level) $ do
    time <- getCurrentTime
    atomically $ writeTQueue queue (Message level callSite text time)

loggerWorker :: System.IO.Handle -> TQueue Message -> IO ()
loggerWorker fileH messageQueue =
  forever $ do
    messages <- atomically $ mfilter (not . null) $ flushTQueue messageQueue
    T.hPutStrLn fileH $ T.intercalate "\n" $ map formatMessage messages
    System.IO.hFlush fileH

formatMessage :: Message -> T.Text
formatMessage Message {..} =
  mconcat [timeString, " | ", levelString, " | ", callSiteString, messageText]
  where
    timeString = T.pack $ formatTime defaultTimeLocale "%F %T.%3q" messageTime
    levelString = T.justifyLeft 7 ' ' $ T.pack (show messageLevel)
    callSiteString = maybe "" formatCallSite messageCallSite
    formatCallSite cs =
      "(at " <>
      Logger.csModule cs <> ":" <> T.pack (show $ Logger.csStartLine cs) <> ") "
