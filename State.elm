port module State exposing (..)

import String
import Array exposing (Array)
import Dict exposing (Dict)
import Platform.Cmd as Cmd
import Json.Encode as JE exposing (Value)
import Navigation exposing (Location)
import Debounce
import ElmTextSearch as Search
import Debug exposing (log)

import Types exposing (Card, Message, Content(..),
                       cardDecoder, messageDecoder,
                       encodeCard, encodeContent, encodeMessage)

-- UPDATE

type Msg
    = Deb (Debounce.Msg Msg)
    | TypeMessage String
    | SearchCard String
    | PostMessage | SelectMessage String
    | ClickCard String | UpdateCardContents Action
    | AddMessage Message | AddToCard Card (List Message)
    | AddCard Card | FocusCard Card
    | NoOp String

type Action = Add | Edit Int Content | Delete Int

port pouchCreate : Value -> Cmd msg
port loadCard : String -> Cmd msg
port updateCardContents: (String, Int, Value) -> Cmd msg

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
                newmessage = pouchCreate <| encodeMessage model.me text
                newcard =
                    if String.left 5 text == "/card" then
                        pouchCreate <|
                            encodeCard (String.dropLeft 5 text) []
                    else Cmd.none
            in
                { model
                    | typing = ""
                    , cardMode =
                        case model.cardMode of
                            SearchResults _ _ -> MostRecent
                            _ -> model.cardMode
                } ! [ newmessage, newcard ]
        SelectMessage id ->
            { model | messages =
                List.map
                    (\m -> if m.id == id then { m | selected = not m.selected } else m)
                    model.messages
            } ! []
        ClickCard id ->
            if id == "" then
                { model | cardMode =
                    case model.cardMode of
                        Focused _ previous -> previous
                        _ -> MostRecent
                } ! []
            else
                model ! [ loadCard id ]
        UpdateCardContents action ->
            case model.cardMode of
                Focused card prev ->
                    case action of
                        Edit index content ->
                            model !
                            [ updateCardContents
                                (card.id, index, encodeContent content)
                            ]
                        Add ->
                            { model | cardMode = Focused
                                { card | contents = Text "" :: card.contents }
                                prev
                            } ! []
                        _ -> model ! []
                _ -> model ! []
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
        AddToCard card messages ->
            { model
                | messages = List.map (\m -> { m | selected = False }) model.messages
                --, card
            } ! []
        NoOp _ -> (model, Cmd.none)


-- MODEL

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

type CardMode = MostRecent | SearchResults String (List String) | Focused Card CardMode

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

debCfg : Debounce.Config Model Msg
debCfg = Debounce.config .debouncer (\m s -> { m | debouncer = s }) Deb 400

