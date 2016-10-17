port module State exposing (..)

import String
import Array exposing (Array)
import Dict exposing (Dict)
import Json.Decode as JD exposing ((:=), decodeValue)
import Json.Encode as JE exposing (Value)
import Platform.Cmd as Cmd
import Json.Encode as JE exposing (Value)
import Debounce
import ElmTextSearch as Search
import Debug exposing (log)

import Types exposing (Card, Message, Content(..),
                       cardDecoder, messageDecoder,
                       encodeCard, encodeContent, encodeMessage)
import Helpers exposing (findIndex)

-- UPDATE

type Msg
    = Deb (Debounce.Msg Msg)
    | TypeMessage String
    | SearchCard String
    | PostMessage | SelectMessage String Bool | UnselectMessages
    | ClickCard String | UpdateCardContents Action
    | AddMessage Message | AddToCard String (List Message)
    | GotCard Card | FocusCard Card
    | NoOp String

type Action = Add | Edit Int Content | Delete Int

port pouchCreate : Value -> Cmd msg
port loadCard : String -> Cmd msg
port updateCardContents: (String, Int, Value) -> Cmd msg

port deselectText : Bool -> Cmd msg

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
                            encodeCard (String.dropLeft 5 text) Array.empty
                    else Cmd.none
            in
                { model
                    | typing = ""
                    , cardMode =
                        case model.cardMode of
                            SearchResults _ _ -> MostRecent
                            _ -> model.cardMode
                } ! [ newmessage, newcard ]
        SelectMessage id shiftPressed ->
            if shiftPressed then
                let
                    mapcomplex : List String -> Message -> Message
                    mapcomplex acc m =
                        if List.any ((==) m.id) acc then { m | selected = True }
                        else { m | selected = False }
                    accumulator m acc =
                        if (List.any ((==) id) acc) then acc -- past the point of clicked
                        else if List.isEmpty acc then
                            if m.selected then m.id :: acc -- where the selection starts
                            else acc -- the selection hasn't started yet
                        else m.id :: acc -- the selection just keeps going

                    firstselectedindex = findIndex .selected model.messages
                    clickedindex = findIndex (.id >> (==) id) model.messages
                    (reduce, messages) =
                        if firstselectedindex > List.length model.messages then
                            case model.messages of
                                [] -> (List.foldl, model.messages)
                                x::xs ->
                                    (List.foldl, { x | selected = True } :: xs)
                        else if firstselectedindex >= clickedindex then
                            (List.foldr, model.messages)
                        else
                            (List.foldl, model.messages)
                    acc = reduce accumulator [] messages
                in
                    { model | messages = List.map (mapcomplex acc) model.messages }
                    ! [ deselectText True ]
            else
                { model | messages = List.map
                    (\m -> if m.id == id then { m | selected = not m.selected } else m)
                    model.messages
                } ! []
        UnselectMessages ->
            { model | messages =
                List.map (\m -> { m | selected = False }) model.messages
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
                                { card | contents = Array.push (Text "") card.contents }
                                prev
                            } ! []
                        Delete index ->
                            model !
                            [ updateCardContents (card.id, index, JE.null) ]
                _ -> model ! []
        FocusCard card ->
            { model | cardMode = Focused card model.cardMode } ! []
        AddMessage message ->
            { model | messages = message :: model.messages } ! []
        GotCard card ->
            { model
                | cards =
                    if List.any (.id >> (==) card.id) model.cards then
                        List.map (\c -> if c.id == card.id then card else c) model.cards
                    else
                        card :: model.cards
                , cardMode =
                    case model.cardMode of
                        Focused _ prev -> Focused card prev
                        _ -> model.cardMode
                , cardSearchIndex =
                    case Search.addOrUpdate card model.cardSearchIndex of
                        Ok index -> index
                        Err _ -> model.cardSearchIndex
            } ! []
        AddToCard id messages ->
            { model | messages = List.map (\m -> { m | selected = False }) model.messages }
            ! [ updateCardContents (id, 999, encodeContent <| Conversation messages) ]
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


-- SUBSCRIPTIONS

port pouchMessages : (Value -> msg) -> Sub msg
port pouchCards : (Value -> msg) -> Sub msg
port cardLoaded : (Value -> msg) -> Sub msg

subscriptions : Model -> Sub Msg
subscriptions model =
    let
        decodeOrFail : JD.Decoder a -> (a -> Msg) -> Value -> Msg
        decodeOrFail decoder tagger value =
            case decodeValue decoder value of
                Ok decoded -> tagger decoded
                Err err -> NoOp <| log ("error decoding " ++ (toString value)) err
    in
        Sub.batch
            [ pouchMessages <| decodeOrFail messageDecoder AddMessage
            , pouchCards <| decodeOrFail cardDecoder GotCard
            , cardLoaded <| decodeOrFail cardDecoder FocusCard
            ]

debCfg : Debounce.Config Model Msg
debCfg = Debounce.config .debouncer (\m s -> { m | debouncer = s }) Deb 400

