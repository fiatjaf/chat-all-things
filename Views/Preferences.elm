module Views.Preferences exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Dict exposing (Dict)
import Time exposing (..)
import Json.Decode exposing (string, object1, object2, object3, bool, at)

import Types exposing (Model, CardMode(..),
                       User, Channel,
                       PeerStatus(..), Editing(..))
import State exposing (Msg(..), Action(..))


buttonMenuView : String -> String -> List (Html Msg) -> Html Msg
buttonMenuView active menu contents =
    div [ classList [ (menu, True), ("active", active == menu) ] ]
        [ a [ onClick <| OpenMenu (if menu == active then "" else menu) ] contents
        ]

menuView : String -> String -> Html Msg -> Html Msg
menuView active menu = div [ id menu, class <| if menu == active then "active" else "" ] << List.repeat 1

channelConfigView : List String -> Channel -> Dict String PeerStatus -> Html Msg
channelConfigView allChannels channel webrtc =
    div []
        [ div []
            [ a [ class "button", onClick ConnectWebSocket ] [ text "Try to establish connections" ]
            , h3 [] [ text "Open connections" ]
            , lazy openConnectionsView webrtc
            ]
        , div []
            [ h3 [] [ text "Channels on this device" ]
            , ul []
                <| List.map (\c ->
                    li []
                        [ a [ class "button", onClick <| SelectChannel c ] [ text c ]
                        ]
                    )
                <| allChannels
            ]
        , node "form"
            [ class "config-form"
            , onWithOptions "submit" (Options True True) <| object1
                SetChannel
                (at [ "target", "firstElementChild", "firstElementChild", "value" ] string)
            ]
            [ label []
                [ text "Websocket: "
                , input [ value channel.websocket ] []
                ]
            , button [] [ text "Set" ]
            ]
        ] 

openConnectionsView : Dict String PeerStatus -> Html Msg
openConnectionsView webrtc =
    Keyed.ul [ class "open-connections" ]
        <| Dict.toList
        <| Dict.map
            ( \id status ->
                div []
                    [ text <| id ++ ": "
                    , code []
                        [ text <| case status of
                            Connecting -> "CONNECTING"
                            Connected s -> if s.replicating then "REPLICATING" else "CONNECTED"
                            Closed -> "CLOSED"
                            Weird i -> "unknown state " ++ toString i
                        ]
                    , case status of
                        Connected s -> small []
                            [ text <| "data last sent " ++ (inSeconds s.lastSent |> toString) ++ " seconds ago. "
                            , text <| "data last received " ++ (inSeconds s.lastReceived |> toString ) ++ " seconds ago."
                            ]
                        _ -> text ""
                    ]
            )
        <| webrtc

userConfigView : List User -> User -> Html Msg
userConfigView users user =
    div []
        [ div [ class "profile" ]
            [ img [ src user.pictureURL ] []
            , span [] [ text user.name ]
            ]
        , div []
            [ h3 [] [ text "Users on this device" ]
            , ul []
                <| List.map (\u ->
                    li []
                        [ img [ src u.pictureURL ] []
                        , a [ class "button", onClick <| SelectUser u ] [ text u.name ]
                        ]
                    )
                <| List.filter (\u -> u.machineId == user.machineId) users
            ]
        , h3 [] [ text "Add new user" ]
        , node "form"
            [ class "config-form"
            , onWithOptions "submit" (Options True True) <| object2
                SetUser
                (at [ "target", "firstElementChild", "firstElementChild", "value" ] string)
                (at [ "target", "firstElementChild", "nextSibling", "firstElementChild", "value" ] string)
            ]
            [ label []
                [ text "Name: "
                , input [] []
                ]
            , label []
                [ text "Picture URL: "
                , input [] []
                ]
            , button [] [ text "Set" ]
            ]
        ]
