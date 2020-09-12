module Core.Interactor.GetAuthors
  ( run
  , Handle(..)
  ) where

import Control.Monad.Catch
import Core.Author
import Core.Authorization
import Core.Pagination

data Handle m =
  Handle
    { hGetAuthors :: PageSpec -> m [Author]
    , hAuthHandle :: AuthenticationHandle m
    , hPageSpecParserHandle :: PageSpecParserHandle
    }

run ::
     MonadThrow m
  => Handle m
  -> Maybe Credentials
  -> PageSpecQuery
  -> m [Author]
run h credentials pageQuery = do
  actor <- authenticate (hAuthHandle h) credentials
  requireAdminPermission actor "get authors"
  page <- parsePageSpecM (hPageSpecParserHandle h) pageQuery
  hGetAuthors h page
