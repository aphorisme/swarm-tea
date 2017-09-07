{-# LANGUAGE RecursiveDo #-}
module Swarm.TEA.Network where

import Control.Concurrent.MVar (newMVar, putMVar, tryTakeMVar)
import Control.Exception.Safe  (finally)
import Control.Monad.IO.Class  (liftIO)
import Control.Monad (when)

import qualified Data.ByteString as SB
import Data.Store (Store, encode)
import Data.Maybe (isJust)


import Reactive.Banana
import Reactive.Banana.Frameworks

import Swarm.TEA.Types


-- | Compiles and actuates the TEA network with provided initial state, update function
-- and state file accessor. 
installNetwork :: Store seral
               => (actual, seral)
               -- ^ Initial state.
               -> UpdateFunction actual seral message
               -- ^ Update function, to update the state and fire async actions and reporting.
               -> (seral -> FilePath)
               -- ^ State file accessor, denoting where the serialziable part of the state
               -- should be stored.
               -> IO ()
installNetwork initState uf stateFile = do
  es <- newAddHandler
  nd <- compile (networkDescription es initState uf stateFile)
  actuate nd

-- | Generalized network description mimicing The Elm Architecture. The state consists
-- of two parts, where one part can be serialized. One needs to provide an update function.
networkDescription :: Store seral
                   => EventSource message
                   -- ^ 'EventSource' for the general messages.
                   -> (actual, seral)
                   -- ^ Initial state.
                   -> UpdateFunction actual seral message
                   -- ^ The state update function.
                   -> (seral -> FilePath)
                   -- ^ Path to the file which stores the serialized
                   -- state.
                   -> MomentIO ()
networkDescription es initState update stateFile = mdo
  lock <- liftIO $ newMVar ()
  --------------------------------------
  -- MAIN LOOP - TEA
  --------------------------------------

  -- event by messages
  emsg <- fromAddHandler (addHandler es)


  -- state is accumulated from both: actual and seral changes.
  bState <-
    accumB initState $ unions
           [ (\a s -> (a, snd s)) <$> eActuChange
           , (\a s -> (fst s, a)) <$> eSeralChange
           ]

  -- update function returns four different components:
  let
    eUpdateTuple = (update <$> bState) <@> emsg

    eActuChange  = filterJust ((\(a, _, _, _) -> a) <$> eUpdateTuple)
    eSeralChange = filterJust ((\(_, s, _, _) -> s) <$> eUpdateTuple)
    eReport      = filterJust ((\(_, _, r, _) -> r) <$> eUpdateTuple)
    eAsync       = filterJust ((\(_, _, _, a) -> a) <$> eUpdateTuple)

    -- serialize only, when not serializing at the moment.
    trySerializeState seral = do
      ml <- tryTakeMVar lock
      when (isJust ml)
           (finally (SB.writeFile (stateFile seral) (encode seral)) (putMVar lock ()))
  
  -- actimate async operations:
  reactReporting bState eReport
  reactAsync es eAsync

  -- serialize the serializable part on change:
  reactimate $ trySerializeState <$> eSeralChange

