module Web.Handler.GetCategory
  ( run
  , Handle(..)
  ) where

import Control.Exception
import Core.Category
import qualified Core.Interactor.GetCategory as IGetCategory
import Web.Application
import Web.Exception

data Handle =
  Handle
    { hGetCategoryHandle :: IGetCategory.Handle IO
    , hPresenter :: Category -> Response
    }

run :: Handle -> CategoryId -> Application
run Handle {..} catId _ respond = do
  category <-
    maybe (throwIO NotFoundException) pure =<<
    IGetCategory.run hGetCategoryHandle catId
  respond $ hPresenter category
