port module App exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Json.Decode as JD exposing ((:=), decodeValue)
import Json.Encode as JE exposing (Value)
import Platform.Cmd as Cmd
import Array exposing (Array)
import Dict exposing (Dict)
import Navigation exposing (Location)
import String
import Task
import Debug exposing (log)

main =
    Navigation.program
        (Navigation.makeParser (\l -> l))
        { init = init
        , view = view
        , update = update
        , urlUpdate = \msg model -> model ! []
        , subscriptions = subscriptions
        }


-- MODEL

init : Location -> (Model, Cmd Msg)
init _ =
    ( Model
        "fiatjaf"
        [] [] ""
        ( Dict.fromList
            [ ("fiatjaf", "https://secure.gravatar.com/avatar/b760f503c84d1bf47322f401066c753f.jpg?s=140")
            ]
        )
    , Cmd.none
    )

type alias Model =
    { me : String
    , cards : List Card
    , messages : List Message
    , typing : String
    , userPictures : Dict String String
    }

type alias Card =
    { name : String
    , desc : String
    , comments : List Message
    }

type alias Message =
    { author : String
    , text : String
    }


-- UPDATE

type Msg
    = TypeMessage String
    | PostMessage
    | AddMessage Message | AddCard Card
    | NoOp String

port pouchPut : Value -> Cmd msg
port pouchCreate : Value -> Cmd msg

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        TypeMessage v ->
            { model | typing = v } ! []
        PostMessage ->
            let
                text = model.typing |> String.trim
                newmessage = pouchCreate <|
                    JE.object
                        [ ("type", JE.string "message")
                        , ("author", JE.string model.me)
                        , ("text", JE.string text)
                        ]
                newcard =
                    if String.left 5 text == "/card" then
                        pouchCreate <|
                            JE.object
                                [ ("type", JE.string "card")
                                , ("name", JE.string <| String.dropLeft 5 text)
                                , ("desc", JE.string "")
                                ]
                    else Cmd.none
            in
                { model | typing = "" } ! [ newmessage, newcard ]
        AddMessage message ->
            { model | messages = message :: model.messages } ! []
        AddCard card ->
            { model | cards = card :: model.cards } ! []
        NoOp _ -> (model, Cmd.none)


-- SUBSCRIPTIONS

port pouchMessages : (Value -> msg) -> Sub msg
port pouchCards : (Value -> msg) -> Sub msg

subscriptions : Model -> Sub Msg
subscriptions model =
    let
        messageDecoder = JD.object2 Message ("author" := JD.string) ("text" := JD.string)
        cardDecoder = JD.object3 Card ("name" := JD.string) ("desc" := JD.string) (JD.succeed [])
    in
        Sub.batch
            [ pouchMessages
                ( \v ->
                    case decodeValue messageDecoder (log "m" v) of
                        Ok message -> AddMessage message
                        Err err -> NoOp <| log "error decoding Message" err
                )
            , pouchCards
                ( \v ->
                    case decodeValue cardDecoder v of
                        Ok card -> AddCard card
                        Err err -> NoOp <| log "error decoding Card" err
                )
            ]

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
        [ div [ id "messages" ]
            ( model.messages
                |> List.take 50
                |> List.reverse
                |> List.map (lazy2 messageView model.userPictures)
            )
        , node "form" [ id "input", onSubmit PostMessage ]
            [ input [ onInput TypeMessage, value model.typing ] []
            , button [] [ text "Send" ]
            ]
        ]

messageView : Dict String String -> Message -> Html Msg
messageView pictures message =
    let
        authorURL = case Dict.get message.author pictures of
            Nothing -> "https://api.adorable.io/avatars/140/" ++ message.author ++ ".png"
            Just url -> url
    in
        div [ class "message" ]
            [ div [ class "author" ]
                [ img [ src authorURL ] []
                , text message.author
                ]
            , div [ class "text" ] [ text message.text ]
            ]

cardsView : Model -> Html Msg
cardsView model =
    div []
        (List.map (lazy cardView) model.cards)

cardView : Card -> Html Msg
cardView card =
    div [ class "card" ]
        [ b [] [ text card.name ]
        , p [] [ text card.desc ]
        ]
