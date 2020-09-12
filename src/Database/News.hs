{-# LANGUAGE QuasiQuotes #-}

module Database.News
  ( selectNews
  ) where

import qualified Core.Interactor.GetNews as GetNews
import Core.Pagination
import Data.Profunctor
import Data.Vector (Vector)
import Database
import qualified Hasql.TH as TH

selectNews :: Statement PageSpec (Vector GetNews.News)
selectNews =
  dimap
    (\PageSpec {..} -> (getPageLimit pageLimit, getPageOffset pageOffset))
    (fmap $ \(newsId, newsTitle, newsDate, newsText) -> GetNews.News {..})
    [TH.vectorStatement|
    select news_id :: integer, title :: varchar, date :: date, body :: varchar
    from news
    order by date desc, news_id desc
    limit $1 :: integer offset $2 :: integer
  |]
