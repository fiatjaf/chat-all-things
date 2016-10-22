module Views.Messages exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Json.Decode as JD exposing ((:=))

import Types exposing (Model, CardMode(..), Editing(..),
                       Message)
import State exposing (Msg(..), Action(..))


chatView : Model -> Html Msg
chatView model =
    div []
        [ lazy messageActionView model
        , Keyed.node "div" [ id "messages" ]
            ( model.messages
                |> List.take 50
                |> List.reverse
                |> List.map (\m -> (m.id, lazy messageView m))
            )
        , node "form" [ id "input", onSubmit PostMessage ]
            [ textarea
                [ onInput TypeMessage
                , on "keydown" 
                    <| JD.object1
                        (\c -> if c == 13 then PostMessage else NoOp "")
                        ("keyCode" := JD.int)
                , value model.typing
                ] []
            , button [] [ text "Send" ]
            ]
        ]

messageActionView : Model -> Html Msg
messageActionView model =
    if List.any .selected model.messages then
        let
            selectedMessages = List.filter .selected model.messages
            action = 
                case model.cardMode of
                    Focused card _ _ ->
                        a [ onClick <| AddToCard card.id selectedMessages ]
                            [ text "add to card" ]
                    _ -> a [ onClick <| AddToNewCard selectedMessages ]
                            [ text "create a card" ]
        in
            div [ id "messages-action" ]
                [ text <| (++)
                    (selectedMessages |> List.length |> toString)
                    " messages."
                , a [ onClick <| UnselectMessages ] [ text "unselect" ]
                , action
                ]
    else
        text ""

messageView : Message -> Html Msg
messageView message =
    div
        [ class <| "message" ++ if message.selected then " selected" else ""
        , id message.id
        , on "click"
            <| JD.object1
                (SelectMessage message.id)
                ("shiftKey" := JD.bool)
        ]
        [ img [ src message.author.pictureURL ] []
        , div []
            [ strong [] [ text message.author.name ]
            , div [ class "text" ] [ text message.text ]
            ]
        ]

