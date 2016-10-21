module Views.Preferences exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Json.Decode as JD exposing ((:=))

import Types exposing (Model, CardMode(..), User, Editing(..))
import State exposing (Msg(..), Action(..))


buttonMenuView : String -> String -> String -> Html Msg
buttonMenuView active menu label =
    div [ classList [ (menu, True), ("active", active == menu) ] ]
        [ a [ onClick <| OpenMenu (if menu == active then "" else menu) ] [ text label ]
        ]

channelConfigView : String -> String -> Html Msg
channelConfigView active channelName =
    div [ id "channel", class <| if active == "channel" then "active" else "" ]
        [ node "form" []
            [ text channelName
            ]
        ]

userConfigView : String -> List User -> User -> Html Msg
userConfigView active users user =
    div [ id "user", class <| if active == "user" then "active" else "" ]
        [ div [ id "" ]
            [ img [ src <| "/user/" ++ user.name ++ ".png" ] []
            , text user.name
            , br [] []
            , text "Device: "
            , code [] [ text user.machineId ]
            ]
        , div []
            [ h3 [] [ text "Users on this device" ]
            , ul []
                <| List.map (\u -> li [] [ button [] [ text u.name ] ])
                <| List.filter (\u -> u.machineId == user.machineId) users
            ]
        , h3 [] [ text "Add new user" ]
        , node "form"
            [ id "add-new-user"
            , onWithOptions "submit" (Options True True) <| JD.object2
                SetUser
                (JD.at [ "target", "firstElementChild", "firstElementChild", "value" ] JD.string)
                (JD.at [ "target", "firstElementChild", "nextSibling", "firstElementChild", "value" ] JD.string)
            ]
            [ label []
                [ text "Name: "
                , input [] []
                ]
            , label []
                [ text "Picture URL: "
                , input [] []
                ]
            , button [] [ text "Add" ]
            ]
        ]
