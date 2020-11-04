module Web.Handler.DeleteAuthor
  ( run
  , Handle(..)
  ) where

import Core.Author
import qualified Core.Interactor.DeleteAuthor as I
import Web.Application
import Web.Credentials

data Handle =
  Handle
    { hDeleteAuthorHandle :: I.Handle IO
    , hPresenter :: Response
    }

run :: Handle -> AuthorId -> Application
run Handle {..} authorId' request respond = do
  credentials <- getCredentialsFromRequest request
  I.run hDeleteAuthorHandle credentials authorId'
  respond hPresenter
