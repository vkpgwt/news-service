module Core.Interactor.DeleteAuthor
  ( run
  , Handle(..)
  ) where

import Control.Monad
import Control.Monad.Catch
import Core.Author
import Core.Authorization
import Core.EntityId
import Core.Exception

data Handle m =
  Handle
    { hDeleteAuthor :: AuthorId -> m Success
    , hAuthenticationHandle :: AuthenticationHandle m
    , hAuthorizationHandle :: AuthorizationHandle
    }

type Success = Bool

run :: MonadThrow m => Handle m -> Maybe Credentials -> AuthorId -> m ()
run Handle {..} credentials authorId' = do
  actor <- authenticate hAuthenticationHandle credentials
  requireAdminPermission hAuthorizationHandle actor "deleting author"
  ok <- hDeleteAuthor authorId'
  unless ok $
    throwM . RequestedEntityNotFoundException $ AuthorEntityId authorId'
