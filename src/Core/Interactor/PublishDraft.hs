module Core.Interactor.PublishDraft
  ( run
  , Handle(..)
  , Failure(..)
  ) where

import Control.Monad.Catch
import Core.Author
import Core.AuthorizationNG
import Core.Deletable
import Core.News
import Data.Time

data Handle m =
  Handle
    { hGetDraftAuthor :: DraftId -> m (Maybe (Deletable AuthorId))
    , hGetCurrentDay :: m Day
    , hMakeDraftIntoNews :: DraftId -> Day -> m News
    }

run ::
     MonadThrow m
  => Handle m
  -> AuthenticatedUser
  -> DraftId
  -> m (Either Failure News)
run Handle {..} authUser vId = do
  hGetDraftAuthor vId >>= \case
    Nothing -> pure $ Left UnknownDraftId
    Just authorId -> do
      authorize "publish a draft" $
        authUser `authUserShouldBeDeletableAuthor` authorId
      day <- hGetCurrentDay
      Right <$> hMakeDraftIntoNews vId day

data Failure =
  UnknownDraftId
  deriving (Eq, Show)
