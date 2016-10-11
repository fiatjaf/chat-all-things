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


-- MODEL

init : Location -> (Model, Cmd Msg)
init _ =
    ( Model
        "fiatjaf"
        [] "" [] None
        ( Dict.fromList
            [ ("fiatjaf", "https://secure.gravatar.com/avatar/b760f503c84d1bf47322f401066c753f.jpg?s=140")
            ]
        )
    , Cmd.none
    )

type alias Model =
    { me : String
    , messages : List Message
    , typing : String
    , cards : List Card
    , selectedCard : SelectStatus
    , userPictures : Dict String String
    }

type alias Card =
    { id : String
    , name : String
    , desc : String
    , comments : List Message
    }

type alias Message =
    { id : String
    , author : String
    , text : String
    }

type SelectStatus = None | Loading String | Focused Card

-- UPDATE

type Msg
    = TypeMessage String
    | PostMessage | ClickCard String
    | AddMessage Message | AddCard Card | FocusCard Card
    | NoOp String

port pouchPut : Value -> Cmd msg
port pouchCreate : Value -> Cmd msg
port loadCard : String -> Cmd msg

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
        ClickCard id ->
            if id == "" then
                { model | selectedCard = None } ! []
            else
                case model.selectedCard of
                    None -> { model | selectedCard = Loading id } ! [ loadCard id ]
                    Loading loadingId ->
                        if loadingId == id then (model, Cmd.none)
                        else { model | selectedCard = Loading id } ! [ loadCard id ]
                    Focused focused ->
                        if focused.id == id then (model, Cmd.none)
                        else { model | selectedCard = Loading id } ! [ loadCard id ]
        FocusCard card ->
            ( case model.selectedCard of
                None -> { model | selectedCard = Focused card }
                Loading loadingId ->
                    if loadingId /= card.id then model
                    else { model | selectedCard = Focused card }
                Focused _ -> { model | selectedCard = Focused card }
            ) ! []
        AddMessage message ->
            { model | messages = message :: model.messages } ! []
        AddCard card ->
            { model | cards = card :: model.cards } ! []
        NoOp _ -> (model, Cmd.none)


-- SUBSCRIPTIONS

port pouchMessages : (Value -> msg) -> Sub msg
port pouchCards : (Value -> msg) -> Sub msg
port cardLoaded : (Value -> msg) -> Sub msg

subscriptions : Model -> Sub Msg
subscriptions model =
    let
        messageDecoder = JD.object3 Message
            ("_id" := JD.string)
            ("author" := JD.string)
            ("text" := JD.string)
        cardDecoder = JD.object4 Card
            ("_id" := JD.string)
            ("name" := JD.string)
            ("desc" := JD.string)
            (JD.succeed [])
        decodeOrFail : JD.Decoder a -> (a -> Msg) -> Value -> Msg
        decodeOrFail decoder tagger value =
            case decodeValue decoder value of
                Ok decoded -> tagger decoded
                Err err -> NoOp <| log ("error decoding " ++ (toString value)) err
    in
        Sub.batch
            [ pouchMessages <| decodeOrFail messageDecoder AddMessage
            , pouchCards <| decodeOrFail cardDecoder AddCard
            , cardLoaded <| decodeOrFail cardDecoder FocusCard
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
        div [ class "message", id message.id ]
            [ img [ src authorURL ] []
            , div []
                [ strong [] [ text message.author ]
                , div [ class "text" ] [ text message.text ]
                ]
            ]

cardsView : Model -> Html Msg
cardsView model =
  case model.selectedCard of
    Focused card -> div [ id "fullcard" ] [ lazy fullCardView card ]
    _ ->
        div [ id "cardlist" ]
            (model.cards
                |> List.take 10
                |> List.map (lazy briefCardView)
            )

briefCardView : Card -> Html Msg
briefCardView card =
    div [ class "card", id card.id ]
        [ b [ onClick <| ClickCard card.id ] [ text card.name ]
        , ( if card.desc == "" then text ""
            else p [] [ text (card.desc |> String.left 60 |> (++) "...") ]
          )
        ]

fullCardView : Card -> Html Msg
fullCardView card =
    div [ class "card", id card.id ]
        [ div []
            [ b [] [ text card.name ]
            , div [ class "close", onClick <| ClickCard "" ] [ text "x" ]
            ]
        , p [] [ text card.desc ]
        ]


main =
    Navigation.program
        (Navigation.makeParser (\l -> l))
        { init = init
        , view = view
        , update = update
        , urlUpdate = \msg model -> model ! []
        , subscriptions = subscriptions
        }
