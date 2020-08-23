{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}

module Main
  ( main
  ) where

import qualified Config as Cf
import qualified Config.IO as CIO
import Control.Concurrent.Async
import Control.Exception
import Control.Exception.Sync
import qualified Core.Interactor.CreateUser as ICreateUser
import qualified Core.Interactor.GetNews as IGetNews
import Core.Pagination
import qualified Data.Aeson as A
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as T
import qualified Database
import qualified Database.ConnectionManager as DBConnManager
import Gateway.CurrentTime as GCurrentTime
import qualified Gateway.News as GNews
import qualified Gateway.SecretToken as GSecretToken
import qualified Gateway.Users as GUsers
import qualified Logger
import qualified Logger.Impl
import qualified Network.HTTP.Types as Http
import qualified Network.Wai as Wai
import qualified Network.Wai.Handler.Warp as Warp
import System.Exit
import System.IO hiding (Handle)
import qualified Web.Application
import qualified Web.Handler.GetNews as HGetNews
import qualified Web.Handler.PostCreateUser as HPostCreateUser
import qualified Web.JSONEncoder as JSONEncoder
import qualified Web.RequestBodyLoader as RequestBodyLoader
import qualified Web.Router as R
import qualified Web.Types as Web

-- Some common module dependencies. Its purpose is to be passed to
-- functions **in this module**, keeping extensibility in the number
-- of fields and avoiding to add excess parameters to 100500 function
-- signatures.
data Deps =
  Deps
    { dDatabaseConnectionConfig :: DBConnManager.Config
    , dConfig :: Cf.Config
    , dLoggerHandle :: Logger.Handle IO
    , dMaxPageLimit :: PageLimit
    , dJSONEncode :: forall a. A.ToJSON a =>
                                 a -> BB.Builder
    , dLoadRequestJSONBody :: Wai.Request -> IO LBS.ByteString
    , dSecretTokenIOState :: GSecretToken.IOState
    }

main :: IO ()
main = do
  (loggerWorker, deps@Deps {..}) <- getDeps
  webHandle <- getWebAppHandle deps
  race_ loggerWorker $ do
    Logger.info dLoggerHandle "Starting Warp"
    Warp.runSettings
      (Cf.cfWarpSettings dConfig)
      (Web.Application.application webHandle)

getDeps :: IO (Logger.Impl.Worker, Deps)
getDeps = do
  inConfig <- CIO.getConfig
  dConfig <- either die pure $ Cf.makeConfig inConfig
  (loggerWorker, dLoggerHandle) <- getLoggerHandle dConfig
  dSecretTokenIOState <- GSecretToken.initIOState
  pure
    ( loggerWorker
    , Deps
        { dConfig
        , dLoggerHandle
        , dDatabaseConnectionConfig = Cf.cfDatabaseConfig dConfig
        , dMaxPageLimit = Cf.cfMaxPageLimit dConfig
        , dJSONEncode =
            JSONEncoder.encode
              JSONEncoder.Config {prettyPrint = Cf.cfJSONPrettyPrint dConfig}
        , dLoadRequestJSONBody =
            RequestBodyLoader.getJSONRequestBody
              RequestBodyLoader.Config
                {cfMaxBodySize = Cf.cfMaxRequestJsonBodySize dConfig}
        , dSecretTokenIOState
        })

getWebAppHandle :: Deps -> IO Web.Application.Handle
getWebAppHandle deps@Deps {..} = do
  hState <- Web.Application.makeState
  pure
    Web.Application.Handle
      { hState
      , hLogger = (`sessionLoggerHandle` dLoggerHandle)
      , hRouter = router deps
      , hShowInternalExceptionInfoInResponses =
          Cf.cfShowInternalErrorInfoInResponse dConfig
      }

router :: Deps -> R.Router
router deps =
  R.new $ do
    R.ifPath ["news"] $ do
      R.ifMethod Http.methodGet $ HGetNews.run . newsHandlerHandle deps
    R.ifPath ["create_user"] $ do
      R.ifMethod Http.methodPost $
        HPostCreateUser.run . postCreateUserHandle deps

newsHandlerHandle :: Deps -> Web.Session -> HGetNews.Handle
newsHandlerHandle deps@Deps {..} session =
  HGetNews.Handle {hGetNewsHandle = interactorHandle, hJSONEncode = dJSONEncode}
  where
    interactorHandle =
      IGetNews.Handle
        { hGetNews = GNews.getNews $ sessionDatabaseHandle session deps
        , hMaxPageLimit = dMaxPageLimit
        }

postCreateUserHandle :: Deps -> Web.Session -> HPostCreateUser.Handle
postCreateUserHandle deps@Deps {..} session =
  HPostCreateUser.Handle
    { hCreateUserHandle = interactorHandle
    , hJSONEncode = dJSONEncode
    , hGetRequestBody = dLoadRequestJSONBody
    }
  where
    interactorHandle =
      ICreateUser.Handle
        { hCreateUser = GUsers.createUser $ sessionDatabaseHandle session deps
        , hGenerateToken =
            GSecretToken.generateIO secretTokenConfig dSecretTokenIOState
        , hGetCurrentTime = GCurrentTime.getIntegralSecondsTime
        , hAllowedImageContentTypes = Cf.cfAllowedImageMimeTypes dConfig
        }
    secretTokenConfig =
      GSecretToken.Config {cfTokenLength = Cf.cfSecretTokenLength dConfig}

-- | Creates an IO action and a logger handle. The IO action must be
-- forked in order for logging to work.
getLoggerHandle :: Cf.Config -> IO (Logger.Impl.Worker, Logger.Handle IO)
getLoggerHandle Cf.Config {..} = do
  hFileHandle <- getFileHandle cfLogFile
  Logger.Impl.new
    Logger.Impl.Handle {hFileHandle, hMinLevel = cfLoggerVerbosity}
  where
    getFileHandle (Cf.LogFilePath path) =
      openFile path AppendMode `catchS` \e ->
        die $ "While opening log file: " ++ displayException (e :: IOException)
    getFileHandle Cf.LogFileStdErr = pure stderr

sessionLoggerHandle :: Web.Session -> Logger.Handle IO -> Logger.Handle IO
sessionLoggerHandle Web.Session {..} =
  Logger.mapMessage $ \text -> "SID-" <> T.pack (show sessionId) <> " " <> text

sessionDatabaseHandle :: Web.Session -> Deps -> Database.Handle
sessionDatabaseHandle session Deps {..} =
  Database.Handle
    { hConnectionConfig = dDatabaseConnectionConfig
    , hLoggerHandle = sessionLoggerHandle session dLoggerHandle
    }
