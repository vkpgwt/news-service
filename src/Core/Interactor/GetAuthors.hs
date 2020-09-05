module Core.Interactor.GetAuthors
  ( run
  , Handle(..)
  ) where

import Control.Monad.Catch
import Core.Author
import qualified Core.Authorization as A
import Core.Pagination

data Handle m =
  Handle
    { hGetAuthors :: Page -> m [Author]
    , hAuthHandle :: A.Handle m
    , hMaxPageLimit :: PageLimit
    }

run ::
     MonadThrow m => Handle m -> Maybe A.Credentials -> PageQuery -> m [Author]
run h credentials pageQuery = do
  actor <- A.authenticate (hAuthHandle h) credentials
  A.requiresAdminPermission actor "get authors" $ do
    page <- pageFromPageQueryM (hMaxPageLimit h) pageQuery
    hGetAuthors h page