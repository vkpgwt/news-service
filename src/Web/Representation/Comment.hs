{-# LANGUAGE TemplateHaskell #-}

module Web.Representation.Comment
  ( CommentRep
  , commentRep
  ) where

import Core.Comment
import Core.News
import qualified Data.Aeson as A
import qualified Data.Aeson.TH as A
import Data.Int
import Data.List
import Data.Maybe
import qualified Data.Text as T
import Data.Time
import Web.Representation.User
import Web.RepresentationBuilder

data CommentRep =
  CommentRep
    { commentCommentId :: Int32
    , commentUser :: Maybe UserRep
    , commentNewsId :: Int32
    , commentText :: T.Text
    , commentCreatedAt :: UTCTime
    }

commentRep :: Comment -> RepBuilder CommentRep
commentRep Comment {..} = do
  userR <- mapM (userRep Nothing) commentAuthor
  pure
    CommentRep
      { commentCommentId = getCommentId commentId
      , commentUser = userR
      , commentNewsId = getNewsId commentNewsId
      , commentText
      , commentCreatedAt
      }

$(A.deriveToJSON
    A.defaultOptions
      { A.fieldLabelModifier = A.camelTo2 '_' . fromJust . stripPrefix "comment"
      , A.omitNothingFields = True
      }
    ''CommentRep)