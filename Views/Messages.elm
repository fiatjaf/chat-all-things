module Views.Messages exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Json.Decode as JD exposing ((:=))
import Dict
import Markdown
import Debug exposing (log)

import Types exposing (Model, Torrent, TorrentFile,
                       CardMode(..), Editing(..), Message)
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
            , case message.torrent of
                Just torrent ->
                    torrentView message.id <| log "torrent" torrent
                Nothing ->
                    Markdown.toHtml [ class "text" ] message.text
            ]
        ]

torrentView : String -> Torrent -> Html Msg
torrentView messageId t =
    div [ class "torrent" ]
        [ if t.progress == 1 then
            text <| "uploaded " ++ toString (t.uploaded / 1000) ++ "kb."
          else if t.progress == 0 then
            a [ onClick <| DownloadTorrent messageId t ] [ text "download attachment" ]
          else
            span []
                [ text "downloaded: "
                , b [] [ text <| toString (t.downloaded / 1000) ++ "kb" ]
                , text ". progress: "
                , b [] [ text <| toString (t.progress * 100) ++ "%" ]
                ]
        , ul []
            <| List.map (lazy torrentFileView)
            <| Dict.values t.files
        ]

torrentFileView : TorrentFile -> Html Msg
torrentFileView tfile =
    li []
        [ code [] [ text tfile.name ]
        , text " "
        , code [] [ text <| toString (tfile.length / 1000) ++ "kb" ]
        , text " "
        , if tfile.blobURL == "" then
            text ""
          else
            a [ href tfile.blobURL, downloadAs tfile.name ] [ text "download" ]
        ]
