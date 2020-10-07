module Core.Authentication.Test
  ( itShouldAuthenticateBeforeOperation
  , noCredentials
  , noOpAuthenticationHandle
  ) where

import Control.Exception
import Core.Authentication
import Core.Exception
import Core.User
import Data.IORef
import Test.AsyncExpectation
import Test.Hspec

-- | Tests that the given action succeds only when the authenticated
-- user is an administrator. It passes stub credentials,
-- authentication handle, and the success continuation to the tested
-- action. The success continuation must be invoked from within the
-- action to indicate operation success.
itShouldAuthenticateBeforeOperation ::
     HasCallStack
  => (Maybe Credentials -> AuthenticationHandle IO -> IO () -> IO ())
  -> Spec
itShouldAuthenticateBeforeOperation test = do
  it "should succeed if authenticated successfully" $ do
    shouldInvokeAtLeastOnce "Continuation must be invoked" $ \onSuccess -> do
      let h = noOpAuthenticationHandle
      test noCredentials h onSuccess
  it "should throw BadCredentialsException in case of bad credentials" $ do
    let onSuccess =
          expectationFailure
            "The action to authorize must not invoke the success continuation for incorrect credentials"
        h = AuthenticationHandle $ \_ -> throwIO $ BadCredentialsException ""
    test noCredentials h onSuccess `shouldThrow` isBadCredentialsException
  itShouldPassCredentialsToAuthenticationHandle Nothing test
  itShouldPassCredentialsToAuthenticationHandle (Just someTokenCredentials) test

itShouldPassCredentialsToAuthenticationHandle ::
     HasCallStack
  => Maybe Credentials
  -> (Maybe Credentials -> AuthenticationHandle IO -> IO () -> IO ())
  -> Spec
itShouldPassCredentialsToAuthenticationHandle credentials test =
  it
    ("should pass credentials to the authentication handle: " ++
     show credentials) $ do
    passedCredentials <- newIORef Nothing
    let h =
          AuthenticationHandle $ \creds -> do
            modifyIORef' passedCredentials $
              maybe
                (Just creds)
                (error "Authentication is invoked more than once")
            pure AnonymousUser
    test credentials h (pure ())
    readIORef passedCredentials `shouldReturn` Just credentials

someTokenCredentials :: Credentials
someTokenCredentials =
  TokenCredentials (UserId 85265) (SecretToken "fjeskdfjgoi3h")

noOpAuthenticationHandle :: AuthenticationHandle IO
noOpAuthenticationHandle = AuthenticationHandle $ \_ -> pure AnonymousUser

noCredentials :: Maybe Credentials
noCredentials = Nothing
