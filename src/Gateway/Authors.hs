module Gateway.Authors
  ( createAuthor
  , getAuthors
  ) where

import Core.Author
import qualified Core.Interactor.CreateAuthor as I
import Core.Pagination
import Core.User
import Data.Foldable
import qualified Data.Text as T
import Database as DB
import qualified Database.Authors as DAuthors

createAuthor :: DB.Handle -> UserId -> T.Text -> IO (Either I.Failure Author)
createAuthor h uid description =
  DB.runTransactionRW h $ DAuthors.createAuthor uid description

getAuthors :: DB.Handle -> Page -> IO [Author]
getAuthors h page =
  toList <$> DB.runTransaction h (statement DAuthors.selectAuthors page)
