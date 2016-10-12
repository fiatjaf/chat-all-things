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
import ElmTextSearch as Search
import Debounce
import String
import Task
import Debug exposing (log)


-- MODEL

init : Location -> (Model, Cmd Msg)
init _ =
    { me = "fiatjaf"
    , messages = [], typing = "", cards = []
    , cardMode = MostRecent
    , cardSearchIndex =
        Search.new
            { ref = .id
            , fields =
                [ ( .name, 5.0 )
                , ( .desc, 3.0 )
                ]
            , listFields =
                [ ( .comments >> List.map .text, 1.0 )
                , ( .comments >> List.map .author, 0.2 )
                ]
            }
    , userPictures = Dict.fromList
        [ ("fiatjaf", "https://secure.gravatar.com/avatar/b760f503c84d1bf47322f401066c753f.jpg?s=140")
        ]
    , debouncer = Debounce.init
    } ! []

type alias Model =
    { me : String
    , messages : List Message
    , typing : String
    , cards : List Card
    , cardSearchIndex : Search.Index Card
    , cardMode : CardMode
    , userPictures : Dict String String
    , debouncer : Debounce.State
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

type CardMode = MostRecent | SearchResults String (List String) | Focused Card CardMode

-- UPDATE

type Msg
    = Deb (Debounce.Msg Msg)
    | TypeMessage String
    | SearchCard String
    | PostMessage | ClickCard String | UpdateCardDesc String String
    | AddMessage Message | AddCard Card | FocusCard Card
    | NoOp String

port pouchUpdate : (String, String, Value) -> Cmd msg
port pouchCreate : Value -> Cmd msg
port loadCard : String -> Cmd msg

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        Deb a -> Debounce.update debCfg a model
        TypeMessage v ->
            ( { model | typing = v }
            , case model.cardMode of
                Focused _ _ -> Cmd.none
                _ -> Debounce.debounceCmd debCfg <| SearchCard v
            )
        SearchCard v ->
            if v == "" then
                { model | cardMode = MostRecent } ! []
            else
                case Search.search v model.cardSearchIndex of
                    Err e ->
                        let _ = log "error searching" e
                        in (model, Cmd.none)
                    Ok (index, results) ->
                        { model
                            | cardSearchIndex = index
                            , cardMode = SearchResults v (List.map fst results)
                        } ! []
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
                { model
                    | typing = ""
                    , cardMode =
                        case model.cardMode of
                            SearchResults _ _ -> MostRecent
                            _ -> model.cardMode
                } ! [ newmessage, newcard ]
        ClickCard id ->
            if id == "" then
                { model | cardMode =
                    case model.cardMode of
                        Focused _ previous -> previous
                        _ -> MostRecent
                } ! []
            else
                model ! [ loadCard id ]
        UpdateCardDesc id desc ->
            model !
            [ pouchUpdate (id, "desc", JE.string desc) ]
        FocusCard card ->
            { model | cardMode = Focused card model.cardMode } ! []
        AddMessage message ->
            { model | messages = message :: model.messages } ! []
        AddCard card ->
            { model
                | cards =
                    if List.any (.id >> (==) card.id) model.cards then
                        List.map (\c -> if c.id == card.id then card else c) model.cards
                    else
                        card :: model.cards
                , cardSearchIndex =
                    case Search.addOrUpdate card model.cardSearchIndex of
                        Ok index -> index
                        Err _ -> model.cardSearchIndex
            } ! []
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
        [ Keyed.node "div" [ id "messages" ]
            ( model.messages
                |> List.take 50
                |> List.reverse
                |> List.map (\m -> (m.id, lazy2 messageView model.userPictures m))
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
  case model.cardMode of
    Focused card _ -> div [ id "fullcard" ] [ lazy fullCardView card ]
    SearchResults query ids ->
        div [ id "searching" ] <|
            if List.length ids == 0 then
                [ h1 [] [ text <| "no cards were found for '" ++ query ++ "'." ] ]
            else
                [ h1 [] [ text <| "search results for '" ++ query ++ "':" ]
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
        [ b [ onClick <| ClickCard card.id ] [ text card.name ]
        , ( if card.desc == "" then text ""
            else p []
                [ text <|
                    if String.length card.desc < 148 then card.desc
                    else card.desc |> String.left 145 |> flip (++) "..."
                ]
          )
        ]

fullCardView : Card -> Html Msg
fullCardView card =
    div [ class "card", id card.id ]
        [ div []
            [ b []
              [ text card.name
              , div [ class "close", onClick <| ClickCard "" ] [ text "x" ]
              ]
            ]
        , p
            [ contenteditable True
            , on "blur" <|
                JD.object1
                    (UpdateCardDesc card.id)
                    (JD.at [ "target", "innerText" ] JD.string)
            ] [ text card.desc ]
        ]


-- HELPERS

debCfg : Debounce.Config Model Msg
debCfg = Debounce.config .debouncer (\m s -> { m | debouncer = s }) Deb 400

main =
    Navigation.program
        (Navigation.makeParser (\l -> l))
        { init = init
        , view = view
        , update = update
        , urlUpdate = \msg model -> model ! []
        , subscriptions = subscriptions
        }
