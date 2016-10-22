module Views.Preferences exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Json.Decode exposing (string, object1, object2, object3, bool, at)

import Types exposing (Model, CardMode(..), User, Channel, Editing(..))
import State exposing (Msg(..), Action(..))


buttonMenuView : String -> String -> List (Html Msg) -> Html Msg
buttonMenuView active menu contents =
    div [ classList [ (menu, True), ("active", active == menu) ] ]
        [ a [ onClick <| OpenMenu (if menu == active then "" else menu) ] contents
        ]

channelConfigView : String -> List String -> Channel -> Html Msg
channelConfigView active allChannels channel =
    div [ id "channel", class <| if active == "channel" then "active" else "" ]
        [ div [] [ text channel.name ]
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

userConfigView : String -> List User -> User -> Html Msg
userConfigView active users user =
    div [ id "user", class <| if active == "user" then "active" else "" ]
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
