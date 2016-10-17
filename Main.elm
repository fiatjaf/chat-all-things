port module App exposing (..)

import Platform.Cmd as Cmd
import Dict exposing (Dict)
import Navigation exposing (Location)
import Debounce
import ElmTextSearch as Search
import Debug exposing (log)

import State exposing (update, subscriptions,
                       Model, CardMode(..),
                       Msg(..), Action(..))
import Types exposing (Card, Message, Content(..),
                       cardDecoder, messageDecoder,
                       encodeCard, encodeMessage)
import Views exposing (view)


init : Location -> (Model, Cmd Msg)
init _ =
    { me = "fiatjaf"
    , messages = []
    , cards = []
    , typing = ""
    , prevTyping = ""
    , cardMode = Normal
    , cardSearchIndex =
        Search.new
            { ref = .id
            , fields =
                [ ( .name, 5.0 )
                ]
            , listFields =
                [ ( .comments >> List.map .text, 1.0 )
                , ( .comments >> List.map .author, 0.2 )
                ]
            }
    , userPictures = Dict.fromList
        [ ("fiatjaf", "https://secure.gravatar.com/avatar/b760f503c84d1bf47322f401066c753f.jpg?s=140")
        ]
    , debouncer = Debounce.init
    } ! []

main =
    Navigation.program
        (Navigation.makeParser (\l -> l))
        { init = init
        , view = view
        , update = update
        , urlUpdate = \msg model -> model ! []
        , subscriptions = subscriptions
        }
