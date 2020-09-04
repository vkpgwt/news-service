module Web.Handler.GetUsers
  ( run
  , Handle(..)
  ) where

import qualified Core.Interactor.GetUsers as I
import qualified Network.HTTP.Types as Http
import qualified Network.Wai as Wai
import qualified Web.HTTP as Http
import qualified Web.Presenter.User as P
import qualified Web.QueryParameter as QP
import qualified Web.QueryParameter.PageQuery as QP

data Handle =
  Handle
    { hGetUsersHandle :: I.Handle IO
    , hPresenterHandle :: P.Handle
    }

run :: Handle -> Wai.Application
run h request respond = do
  pageQuery <- QP.parseQueryM (Wai.queryString request) QP.parsePageQuery
  users <- I.run (hGetUsersHandle h) pageQuery
  respond $
    Wai.responseBuilder Http.ok200 [Http.hJSONContentType] $
    P.presentUsers (hPresenterHandle h) users