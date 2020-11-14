module Core.Interactor.GetNews
  ( getNews
  , Handle(..)
  , NewsFilter(..)
  , NewsDateRange(..)
  , emptyNewsFilter
  , GatewayNewsFilter(..)
  , GatewayNewsAuthorFilter(..)
  , GatewayNewsCategoryFilter(..)
  , GatewayNewsAnyTagFilter(..)
  ) where

import Control.Monad.Catch
import Core.Author
import Core.Category
import Core.News
import Core.Pagination
import Core.Tag
import qualified Data.HashSet as Set
import qualified Data.List.NonEmpty as N
import qualified Data.Text as T
import Data.Time

getNews :: MonadThrow m => Handle m -> NewsFilter -> PageSpecQuery -> m [News]
getNews Handle {..} newsFilter pageQuery = do
  pageSpec <- parsePageSpecM hPageSpecParserHandle pageQuery
  hGetNews (gatewayNewsFilterFromNewsFilter newsFilter) pageSpec

data Handle m =
  Handle
    { hGetNews :: GatewayNewsFilter -> PageSpec -> m [News]
    , hPageSpecParserHandle :: PageSpecParserHandle
    }

-- | A specification of a subset of news entries. All fields are
-- considered as filters over specific news parameters. Filters over
-- independent news fields should be combined using logical AND: if a
-- news entry does not conform to any filter field, it should not be
-- issued. Filters over dependent fields (e.g. author id and author
-- name filters) should be combined using logical OR.
--
-- 'Maybe' is used to represent 'no filtering' value as Nothing. We
-- might use the empty list or set for it, but it might be error-prone
-- due to having to detect the special case. Handling an empty list
-- consistently results in no matching items and so it is useless.
data NewsFilter =
  NewsFilter
    { nfDateRanges :: Maybe (N.NonEmpty NewsDateRange)
    , nfAuthorIds :: Maybe (Set.HashSet AuthorId)
    , nfAuthorNameSubstrings :: Maybe (Set.HashSet T.Text)
    , nfCategoryIds :: Maybe (Set.HashSet CategoryId)
    , nfCategoryNameSubstrings :: Maybe (Set.HashSet T.Text)
    , nfTagIdsToMatchAnyTag :: Maybe (Set.HashSet TagId)
    , nfTagNameSubstringsToMatchAnyTag :: Maybe (Set.HashSet T.Text)
    }

emptyNewsFilter :: NewsFilter
emptyNewsFilter =
  NewsFilter
    { nfDateRanges = Nothing
    , nfAuthorIds = Nothing
    , nfAuthorNameSubstrings = Nothing
    , nfCategoryIds = Nothing
    , nfCategoryNameSubstrings = Nothing
    , nfTagIdsToMatchAnyTag = Nothing
    , nfTagNameSubstringsToMatchAnyTag = Nothing
    }

-- | The inclusive range of dates.
data NewsDateRange
  = NewsSinceUntil Day Day
  | NewsSince Day
  | NewsUntil Day
  deriving (Eq, Show)

-- | A news filter to pass to the gateway. All fields are filters
-- which should be combined using logical AND. The type is intended
-- for using in gateways and, therefore, it should not involve obscure
-- processing rules, so OR-combined fields must not present here, they
-- should be placed within other types.
data GatewayNewsFilter =
  GatewayNewsFilter
    { gnfDateRanges :: Maybe (N.NonEmpty NewsDateRange)
    , gnfAuthorFilter :: GatewayNewsAuthorFilter
    , gnfCategoryFilter :: GatewayNewsCategoryFilter
    , gnfAnyTagFilter :: GatewayNewsAnyTagFilter
    }

-- | An author filter. Its fields correspond to filters that should be
-- combined using logical OR.
data GatewayNewsAuthorFilter =
  GatewayNewsAuthorFilter
    { gnfAuthorIds :: Maybe (Set.HashSet AuthorId)
    , gnfAuthorNameSubstrings :: Maybe (Set.HashSet T.Text)
    -- ^ Author name substrings to match with. Each element is a
    -- substring to be searched in the user name of an author of a
    -- news entry. The user name consists of the first name and the
    -- last name, separated with a space.
    }

-- | A category filter. Its fields correspond to filters that should
-- be combined using logical OR.
data GatewayNewsCategoryFilter =
  GatewayNewsCategoryFilter
    { gnfCategoryIds :: Maybe (Set.HashSet CategoryId)
    -- ^ Category identifier to match with. A category matches to an
    -- identifier if its identifier or its ancestor category
    -- identifier matches.
    , gnfCategoryNameSubstrings :: Maybe (Set.HashSet T.Text)
    -- ^ Category name substrings to match with. Each element is a
    -- substring to be searched in the category name or its ancestor
    -- category names.
    }

-- | A tag filter. It selects entries matching at least one tag
-- specified. Its fields correspond to filters that should be combined
-- using logical OR.
data GatewayNewsAnyTagFilter =
  GatewayNewsAnyTagFilter
    { gnfTagIdsToMatchAnyTag :: Maybe (Set.HashSet TagId)
    , gnfTagNameSubstringsToMatchAnyTag :: Maybe (Set.HashSet T.Text)
    -- ^ Tag name substrings to match with. Each element is a
    -- substring to be searched in the tag name.
    }

gatewayNewsFilterFromNewsFilter :: NewsFilter -> GatewayNewsFilter
gatewayNewsFilterFromNewsFilter NewsFilter {..} =
  GatewayNewsFilter
    { gnfDateRanges = nfDateRanges
    , gnfAuthorFilter =
        GatewayNewsAuthorFilter
          { gnfAuthorIds = nfAuthorIds
          , gnfAuthorNameSubstrings = excludeEmptyStrings nfAuthorNameSubstrings
          }
    , gnfCategoryFilter =
        GatewayNewsCategoryFilter
          { gnfCategoryIds = nfCategoryIds
          , gnfCategoryNameSubstrings =
              excludeEmptyStrings nfCategoryNameSubstrings
          }
    , gnfAnyTagFilter =
        GatewayNewsAnyTagFilter
          { gnfTagIdsToMatchAnyTag = nfTagIdsToMatchAnyTag
          , gnfTagNameSubstringsToMatchAnyTag =
              excludeEmptyStrings nfTagNameSubstringsToMatchAnyTag
          }
    }

excludeEmptyStrings :: Maybe (Set.HashSet T.Text) -> Maybe (Set.HashSet T.Text)
excludeEmptyStrings = (normalize . Set.delete "" =<<)
  where
    normalize set
      | Set.null set = Nothing
      | otherwise = Just set
