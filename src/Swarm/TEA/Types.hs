module Swarm.TEA.Types
  (
  -- * EventSource
    EventSource
  , fire
  , addHandler
  -- * Async and Reporting Actions
  , Reporting
  , reactReporting
  , AsyncAction
  , reactAsync
  -- * Updating Function
  , UpdateFunction
)
where

import Reactive.Banana
import Reactive.Banana.Frameworks

-- | Type alias for an event source, providing a handler
-- and a action to fire the event.
type EventSource a = (AddHandler a, a -> IO ())

-- | Fires an event from an 'EventSource'.
fire :: EventSource a -> (a -> IO ())
fire = snd

-- | Retrieves the 'AddHandler' from an 'EventSource'.
addHandler :: EventSource a -> AddHandler a
addHandler = fst

-- | Reporting type alias, for the async operation which is meant to
-- report things only, but does not feed back messages.
type Reporting actual seral = (actual, seral) -> IO ()

reactReporting :: Behavior (actual, seral) -> Event (Reporting actual seral) -> MomentIO ()
reactReporting bstate erepo =
  reactimate ((\b r -> r b) <$> bstate <@> erepo)


-- | Asynchronous actions, which may fire a message.
type AsyncAction message = (message -> IO ()) -> IO ()

reactAsync :: (message -> IO ()) -> Event (AsyncAction message) -> MomentIO ()
reactAsync es ev =
  reactimate ((\act -> act es) <$> ev)


-- | Type alias for an update function, used by the network to update the over all state.
type UpdateFunction actual seral message =
  (actual, seral) -> message -> (Maybe actual, Maybe seral, Maybe (Reporting actual seral), Maybe (AsyncAction message))
