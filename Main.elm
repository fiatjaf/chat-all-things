port module App exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Platform.Cmd as Cmd
import Navigation exposing (Location)
import Debounce
import ElmTextSearch as Search

import State exposing (update, subscriptions,
                       Msg(..), Action(..))
import Types exposing (Card, Message, Content(..),
                       cardDecoder, messageDecoder,
                       encodeCard, encodeMessage,
                       Model, CardMode(..))
import Views.Messages exposing (..)
import Views.Cards exposing (..)
import Views.Preferences exposing (..)


init : { channel : String, me : String } -> Location -> (Model, Cmd Msg)
init flags _ =
    { channel = flags.channel
    , me = flags.me
    , messages = []
    , cards = []
    , menu = ""
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
    , debouncer = Debounce.init
    } ! []


-- VIEW

view : Model -> Html Msg
view model =
    div [ id "container" ]
        [ aside []
            [ lazy3 buttonMenuView model.menu "channel" model.channel
            , lazy3 buttonMenuView model.menu "user" model.me
            ]
        , lazy2 channelConfigView model.menu model.channel
        , lazy2 userConfigView model.menu model.me
        , node "main" []
            [ section [ id "chat" ] [ chatView model ]
            , section [ id "cards" ] [ cardsView model ]
            ]
        ]

main =
    Navigation.programWithFlags
        (Navigation.makeParser (\l -> l))
        { init = init
        , view = view
        , update = update
        , urlUpdate = \msg model -> model ! []
        , subscriptions = subscriptions
        }
