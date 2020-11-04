module Database.Authors where

import Core.Author
import Core.Pagination
import Core.User
import Database.Service.Primitives

selectAuthorsByUserId :: UserId -> Maybe PageSpec -> Transaction [AuthorId]
