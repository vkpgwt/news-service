{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE RankNTypes #-}

module Web.Handler.CreateAuthor
  ( run
  , Handle(..)
  ) where

import Control.Exception
import qualified Core.Interactor.CreateAuthor as I
import Core.User
import qualified Data.Aeson as A
import qualified Data.Aeson.TH as A
import Data.Int
import Data.List
import Data.Maybe
import qualified Data.Text as T
import qualified Network.HTTP.Types as Http
import qualified Network.Wai as Wai
import Web.Credentials
import Web.Exception
import qualified Web.HTTP as Http
import qualified Web.Presenter.Author as P

data Handle =
  Handle
    { hCreateAuthorHandle :: I.Handle IO
    , hLoadJSONRequestBody :: forall a. A.FromJSON a =>
                                          Wai.Request -> IO a
    , hPresenterHandle :: P.Handle
    }

run :: Handle -> Wai.Application
run Handle {..} request respond = do
  creds <- getCredentialsFromRequest request
  inAuthor <- hLoadJSONRequestBody request
  result <-
    I.run
      hCreateAuthorHandle
      creds
      (UserId $ iaUserId inAuthor)
      (iaDescription inAuthor)
  author <-
    case result of
      Left I.UnknownUserId -> throwIO $ BadRequestException "Unknown UserId"
      Right a -> pure a
  respond $
    Wai.responseBuilder Http.ok200 [Http.hJSONContentType] $
    P.presentAuthor hPresenterHandle author

data InAuthor =
  InAuthor
    { iaUserId :: Int32
    , iaDescription :: T.Text
    }

$(A.deriveFromJSON
    A.defaultOptions
      {A.fieldLabelModifier = A.camelTo2 '_' . fromJust . stripPrefix "ia"}
    ''InAuthor)
