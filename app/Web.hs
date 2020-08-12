{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- | The web application entry point and top-level definitions.
module Web
  ( application
  , Handle(..)
  , State
  , makeState
  ) where

import Control.Exception
import Control.Exception.Sync
import qualified Data.ByteString as SBS
import qualified Data.ByteString.Builder as BB
import Data.IORef
import Data.Int
import Data.List
import qualified Data.Text as T
import Data.Text.Encoding as T
import qualified Logger
import qualified Network.HTTP.Types as Http
import Network.HTTP.Types.Status as Http
import qualified Network.Socket as Socket
import qualified Network.Wai as Wai
import qualified Network.Wai.Handler.Warp as Warp
import Text.Printf
import qualified Web.Router as R

data Handle =
  Handle
    { hLoggerHandle :: Logger.Handle IO
    , hRouter :: R.Router
    , hState :: State
    }

-- | A mutable state of the module. Use 'makeState' to create it and
-- store it into a 'Handle'.
newtype State =
  State
    { stSessionIdRef :: IORef SessionId
    }

newtype SessionId =
  SessionId Int64
  deriving (Eq)

type EApplication = Session -> Wai.Application

type EMiddleware = EApplication -> EApplication

newtype Session =
  Session
    { sessionId :: SessionId
    }

-- | Creates an initial state for the module.
makeState :: IO State
makeState = do
  stSessionIdRef <- newIORef (SessionId 0)
  pure State {..}

application :: Handle -> Wai.Application
application h =
  createSessionMiddleware h .
  logEnterAndExit h . convertExceptionsToStatus500 . logUncaughtExceptions h $
  routerApplication h

createSessionMiddleware :: Handle -> EApplication -> Wai.Application
createSessionMiddleware h eapp request respond = do
  session <- Session <$> generateSessionId h
  eapp session request respond

logEnterAndExit :: Handle -> EMiddleware
logEnterAndExit h eapp session@Session {..} req respond = do
  Logger.info h enterMessage
  (r, status) <- runApplicationAndGetStatus (eapp session) req respond
  Logger.info h (exitMessage status)
  pure r
  where
    enterMessage =
      T.intercalate
        " "
        [ "Request"
        , T.pack (show sessionId)
        , T.pack (formatPeerAddr (Wai.remoteHost req))
        , T.decodeLatin1 (Wai.requestMethod req)
        , T.decodeLatin1 (Wai.rawPathInfo req)
        ]
    exitMessage status =
      T.intercalate
        " "
        [ "Respond"
        , T.pack ("SID=" ++ show sessionId)
        , T.pack (show (Http.statusCode status))
        , T.decodeLatin1 (Http.statusMessage status)
        ]

runApplicationAndGetStatus ::
     Wai.Application
  -> Wai.Request
  -> (Wai.Response -> IO Wai.ResponseReceived)
  -> IO (Wai.ResponseReceived, Http.Status)
runApplicationAndGetStatus app request respond = do
  statusRef <- newIORef (error "The response status must be set here")
  r <-
    app request $ \response -> do
      let (status, _, _) = Wai.responseToStream response
      writeIORef statusRef status
      respond response
  status <- readIORef statusRef
  pure (r, status)

-- Not so fast, though simple.
formatPeerAddr :: Socket.SockAddr -> String
formatPeerAddr (Socket.SockAddrInet _ ip4) =
  intercalate "." $ map show [b1, b2, b3, b4]
  where
    (b1, b2, b3, b4) = Socket.hostAddressToTuple ip4
formatPeerAddr (Socket.SockAddrInet6 _ _ ip6 _) =
  printf "%04X.%04X.%04X.%04X.%04X.%04X.%04X.%04X" b1 b2 b3 b4 b5 b6 b7 b8
  where
    (b1, b2, b3, b4, b5, b6, b7, b8) = Socket.hostAddress6ToTuple ip6
formatPeerAddr (Socket.SockAddrUnix s) = s

generateSessionId :: Handle -> IO SessionId
generateSessionId Handle {..} =
  atomicModifyIORef' (stSessionIdRef hState) $ \(SessionId n) ->
    let new = SessionId (succ n)
     in (new, new)

convertExceptionsToStatus500 :: EMiddleware
convertExceptionsToStatus500 eapp session request respond =
  catchJustS
    testException
    (eapp session request respond)
    (respond . Warp.defaultOnExceptionResponse)
  where
    testException e
      | Just (_ :: SomeAsyncException) <- fromException e = Nothing
      | otherwise = Just e

logUncaughtExceptions :: Handle -> EMiddleware
logUncaughtExceptions h eapp session request respond =
  catchJustS testException (eapp session request respond) logAndRethrow
  where
    testException e
      | Warp.defaultShouldDisplayException e = Just e
      | otherwise = Nothing
    logAndRethrow e = do
      Logger.error h $ T.pack (displayException e)
      throwIO e

routerApplication :: Handle -> EApplication
routerApplication Handle {..} _ request =
  case R.route hRouter request of
    R.HandlerResult handler -> handler request
    R.ResourceNotFoundResult -> ($ stubErrorResponse Http.notFound404 [])
    R.MethodNotSupportedResult knownMethods ->
      ($ stubErrorResponse
           Http.methodNotAllowed405
           [makeAllowHeader knownMethods])
  where
    makeAllowHeader methods = ("Allow", SBS.intercalate ", " methods)

stubErrorResponse :: Http.Status -> [Http.Header] -> Wai.Response
stubErrorResponse status additionalHeaders =
  Wai.responseBuilder
    status
    ((Http.hContentType, "text/html") : additionalHeaders)
    body
  where
    body =
      mconcat
        [ "<!DOCTYPE html><html><body><h1>"
        , BB.stringUtf8 (show (Http.statusCode status))
        , " "
        , BB.byteString (Http.statusMessage status)
        , "</h1></body></html>\n"
        ]

instance Logger.Logger Handle IO where
  lowLevelLog = Logger.hLowLevelLog . hLoggerHandle

instance Show SessionId where
  show (SessionId n) = show n
