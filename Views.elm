module Views exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Dict exposing (Dict)
import Array
import String
import Json.Encode as JE
import Json.Decode as JD exposing ((:=))
import Debug exposing (log)

import State exposing (Model, CardMode(..), Editing(..),
                       Msg(..), Action(..))
import Types exposing (Card, Message, Content(..),
                       cardDecoder, messageDecoder,
                       encodeCard, encodeMessage)

-- VIEW

view : Model -> Html Msg
view model =
    node "main" []
        [ section [ id "chat" ] [ chatView model ]
        , section [ id "cards" ] [ cardsView model ]
        ]

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
        [ img [ src <| "user/" ++ message.author ++ ".png" ] []
        , div []
            [ strong [] [ text message.author ]
            , div [ class "text" ] [ text message.text ]
            ]
        ]

cardsView : Model -> Html Msg
cardsView model =
  case model.cardMode of
    Focused card _ editing ->
        div [ id "fullcard" ]
            [ lazy2 fullCardView card editing
            , div [ class "back", onClick <| ClickCard "" ] []
            ]
    SearchResults query ids ->
        div [ id "searching" ] <|
            if List.length ids == 0 then
                [ b [] [ text <| "no cards were found for '" ++ query ++ "'." ]
                , hr [] []
                , Keyed.node "div" [ id "cardlist" ]
                    (model.cards
                        |> List.take 10
                        |> List.map (\c -> (c.id, lazy briefCardView c))
                    )
                ]
            else
                [ b [] [ text <| "search results for '" ++ query ++ "':" ]
                , Keyed.node "div" [ id "cardlist" ]
                    (model.cards
                        |> List.filter (\c -> List.any ((==) c.id) ids)
                        |> List.map (\c -> (c.id, lazy briefCardView c))
                    )
                ]
    _ ->
        Keyed.node "div" [ id "cardlist" ]
            (model.cards
                |> List.take 10
                |> List.map (\c -> (c.id, lazy briefCardView c))
            )

briefCardView : Card -> Html Msg
briefCardView card =
    div [ class "card", id card.id ]
        [ div [ class "name", onClick <| ClickCard card.id ]
            [ b [] [ text card.name ]
            , span [] [ text <| "#" ++ (String.right 5 card.id) ]
            ]
        , div [ class "contents" ]
            <| Array.toList
            <| Array.map (lazy briefCardContentView) card.contents
        ]

briefCardContentView : Content -> Html Msg
briefCardContentView content =
    case content of
        Text val ->
            div [] [ text val ]
        Conversation messages -> div [] [ text <| (List.length messages |> toString) ++ " messages" ]

fullCardView : Card -> Editing -> Html Msg
fullCardView card editing =
    div [ class "card", id card.id ]
        [ div [ class "name" ] <|
            case editing of
                Name ->
                    [ input
                        [ on "blur"
                            <| JD.object1 StopEditing
                                (JD.at [ "target", "value" ] JD.string)
                        , value card.name
                        ] [ text "" ]
                    ]
                _ ->
                    [ b [ onClick <| StartEditing Name ] [ text card.name ]
                    , span [] [ text <| "#" ++ (String.right 5 card.id) ]
                    ]
        , div [ class "contents" ]
            <| Array.toList
            <| Array.indexedMap (cardContentView card) card.contents
        , a
            [ class "add-content ion-more"
            , title "add text to this card"
            , onClick <| UpdateCardContents Add
            ] [ text "" ]
        ]

cardContentView : Card -> Int -> Content -> Html Msg
cardContentView card index content =
    div [ class "content" ]
        [ case content of
            Text val ->
                div
                    [ class "text"
                    , contenteditable True
                    , on "blur"
                        <| JD.object1
                            (\v -> UpdateCardContents <| Edit index <| Text v)
                            (JD.at [ "target", "innerText" ] JD.string)
                    ] [ text val ]
            Conversation messages ->
                div [ class "conversation" ]
                    <| List.map (lazy messageView) messages
        , a
            [ class "delete ion-trash-a"
            , title "delete"
            , onClick <| UpdateCardContents <| Delete index
            ] [ text "" ]
        ]
