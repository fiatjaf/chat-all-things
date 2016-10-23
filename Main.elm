port module App exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Dict
import Platform.Cmd as Cmd
import Navigation exposing (Location)
import Debounce
import ElmTextSearch as Search

import State exposing (update, subscriptions,
                       Msg(..), Action(..))
import Types exposing (Card, Message, User, Channel,
                       Content(..), PeerStatus(..),
                       cardDecoder, messageDecoder,
                       encodeCard, encodeMessage,
                       Model, CardMode(..))
import Views.Messages exposing (..)
import Views.Cards exposing (..)
import Views.Preferences exposing (..)


init : { channel : Channel, machineId : String, allChannels : List String }
       -> Location -> (Model, Cmd Msg)
init flags _ =
    { channel = flags.channel
    , me = User flags.machineId flags.machineId ("https://api.adorable.io/avatars/140/" ++ flags.machineId)
    , messages = []
    , cards = []
    , users = []
    , channels = flags.allChannels
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
                ]
            }
    , websocket = False
    , webrtc = Dict.empty
    , debouncer = Debounce.init
    } ! []


-- VIEW

view : Model -> Html Msg
view model =
    let
        npeers = model.webrtc
            |> Dict.size
            |> toString
        nconnected = model.webrtc
            |> Dict.filter
                ( \_ ps -> case ps of
                    Connected _ -> True
                    _ -> False
                )
            |> Dict.size
            |> toString
    in
        div [ id "container" ]
            [ aside []
                [ lazy3 buttonMenuView model.menu "channel"
                    [ span [] [ text model.channel.name ]
                    , small []
                        [ text <| if model.websocket then "looking for new connections" else "not accepting new connections"
                        , if model.websocket then text ""
                          else span [ onClick ConnectWebSocket ] [ text "" ]
                        ]
                    , small [] [ text <| npeers ++ " peers, " ++ nconnected ++ " connected" ]
                    ]
                , lazy3 buttonMenuView model.menu "user"
                    [ img [ src model.me.pictureURL ] [], text model.me.name ]
                ]
            , lazy3 menuView model.menu "channel"
                <| lazy3 channelConfigView model.channels model.channel model.webrtc
            , lazy3 menuView model.menu "user"
                <| lazy2 userConfigView model.users model.me
            , node "main" []
                [ section [ id "chat" ] [ chatView model ]
                , section [ id "cards" ] [ cardsView model ]
                ]
            ]

main =
    Navigation.programWithFlags
        (Navigation.makeParser (\l -> l))
        { init = init
        , view = lazy view
        , update = update
        , urlUpdate = \msg model -> model ! []
        , subscriptions = subscriptions
        }
