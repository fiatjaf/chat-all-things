module Views.Preferences exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)

import Types exposing (Model, CardMode(..), Editing(..))
import State exposing (Msg(..), Action(..))

buttonMenuView : String -> String -> String -> Html Msg
buttonMenuView active menu label =
    div [ classList [ (menu, True), ("active", active == menu) ] ]
        [ a [ onClick <| OpenMenu (if menu == active then "" else menu) ] [ text label ]
        ]

channelConfigView : String -> String -> Html Msg
channelConfigView active channelName =
    node "form" [ id "channel", class <| if active == "channel" then "active" else "" ]
        [ text channelName
        ]

userConfigView : String -> String -> Html Msg
userConfigView active userName =
    node "form" [ id "user", class <| if active == "user" then "active" else "" ]
        [ label []
            [ text "name: "
            , input [ value userName ] []
            ]
        , label []
            [ text "picture URL: "
            , input [] []
            ]
        , button [] [ text "Save" ]
        ]
