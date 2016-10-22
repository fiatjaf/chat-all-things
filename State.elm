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

import Types exposing (Card, Message, User, Channel, Content(..),
                       cardDecoder, messageDecoder, userDecoder,
                       encodeCard, encodeContent, encodeMessage, encodeUser,
                       Model, CardMode(..), Editing(..))
import Helpers exposing (findIndex)

-- UPDATE

type Msg
    = Deb (Debounce.Msg Msg)
    | OpenMenu String
    | TypeMessage String
    | SearchCard String
    | PostMessage | SelectMessage String Bool | UnselectMessages
    | ClickCard String | UpdateCardContents Action
    | StartEditing Editing | StopEditing String
    | GotMessage Message
    | AddToCard String (List Message) | AddToNewCard (List Message)
    | GotCard Card | FocusCard Card
    | GotUser User | SelectUser User | SetUser String String
    | SelectChannel String | SetChannel String
    | NoOp String

type Action = Add | Edit Int Content | Delete Int

port pouchCreate : Value -> Cmd msg
port setUserPicture : (String, String) -> Cmd msg
port setChannel : Channel -> Cmd msg
port loadCard : String -> Cmd msg
port updateCardContents : (String, Int, Value) -> Cmd msg

port moveToChannel : String -> Cmd msg
port userSelected : String -> Cmd msg
port focusField : String -> Cmd msg
port scrollChat : Int -> Cmd msg
port deselectText : Int -> Cmd msg

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        Deb a -> Debounce.update debCfg a model
        OpenMenu menu -> { model | menu = menu } ! []
        TypeMessage v ->
            let
                search = 
                    case model.cardMode of
                        Focused _ _ _ -> Cmd.none
                        _ -> Debounce.debounceCmd debCfg <| SearchCard v
                vlen = String.length v
            in
                if model.typing == "" && vlen > 1 then
                    if vlen == (String.length model.prevTyping) + 1 then
                        { model | prevTyping = model.typing } ! []
                    else
                        { model | typing = v, prevTyping = model.typing } ! [ search ]
                else
                    { model | typing = v, prevTyping = model.typing } ! [ search ]
        SearchCard v ->
            if v == "" then
                { model | cardMode = Normal } ! []
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
                    , prevTyping = model.typing
                    , cardMode =
                        case model.cardMode of
                            SearchResults _ _ -> Normal
                            _ -> model.cardMode
                } ! [ newmessage, newcard, scrollChat 90 ]
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
                    ! [ deselectText 30 ]
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
                        Focused _ previous _ -> previous
                        _ -> Normal
                } ! []
            else
                model ! [ loadCard id ]
        StartEditing editingState ->
            case model.cardMode of
                Focused card prev _ ->
                    { model | cardMode = Focused card prev editingState } !
                    [ focusField <| "#" ++ card.id ++ " .name input" ]
                _ -> model ! []
        StopEditing val ->
            case model.cardMode of
                Focused card prev editingState ->
                    { model | cardMode =
                        Focused card prev None
                    } !
                    [ updateCardContents
                        (card.id, -1, JE.string <| String.trim val)
                    ]
                _ -> model ! []
        UpdateCardContents action ->
            case model.cardMode of
                Focused card prev _ ->
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
                                None
                            } ! []
                        Delete index ->
                            model !
                            [ updateCardContents (card.id, index, JE.null) ]
                _ -> model ! []
        FocusCard card ->
            { model | cardMode = Focused card model.cardMode None } ! []
        GotMessage message ->
            { model | messages = message :: model.messages } ! [ scrollChat 10 ]
        GotCard card ->
            { model
                | cards =
                    if List.any (.id >> (==) card.id) model.cards then
                        List.map (\c -> if c.id == card.id then card else c) model.cards
                    else
                        card :: model.cards
                , cardMode =
                    case model.cardMode of
                        Focused _ prev  _ -> Focused card prev None
                        _ -> model.cardMode
                , cardSearchIndex =
                    case Search.addOrUpdate card model.cardSearchIndex of
                        Ok index -> index
                        Err _ -> model.cardSearchIndex
            } ! []
        AddToCard id messages ->
            { model | messages = List.map (\m -> { m | selected = False }) model.messages }
            ! [ updateCardContents (id, 999, encodeContent <| Conversation messages) ]
        AddToNewCard messages ->
            { model | messages = List.map (\m -> { m | selected = False }) model.messages }
            ! [
                pouchCreate <|
                    encodeCard "" (Array.fromList [ Conversation messages ])
            ]
        GotUser user ->
            { model
                | users =
                    if List.any (.name >> (==) user.name) model.users then
                        List.map (\c -> if c.name == user.name then user else c) model.users
                    else
                        user :: model.users
                , me =
                    if model.me.machineId == user.machineId then
                        if model.me.machineId == model.me.name then user
                        else if model.me.name == user.name then user
                        else model.me
                    else model.me
            } ! []
        SelectUser user -> { model | me = user } ! [ userSelected user.name ]
        SetUser name pictureURL ->
            model ! [ setUserPicture (name, pictureURL) ]
        SetChannel websocket ->
            let
                channel = Channel model.channel.name websocket
            in
                { model | channel = channel } ! [ setChannel channel ]
        SelectChannel channelName -> model ! [ moveToChannel channelName ]
        NoOp _ -> (model, Cmd.none)


-- SUBSCRIPTIONS

port pouchMessages : (Value -> msg) -> Sub msg
port pouchCards : (Value -> msg) -> Sub msg
port pouchUsers : (Value -> msg) -> Sub msg
port cardLoaded : (Value -> msg) -> Sub msg
port currentUser : (Value -> msg) -> Sub msg

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
            [ pouchMessages <| decodeOrFail messageDecoder GotMessage
            , pouchCards <| decodeOrFail cardDecoder GotCard
            , pouchUsers <| decodeOrFail userDecoder GotUser
            , cardLoaded <| decodeOrFail cardDecoder FocusCard
            , currentUser <| decodeOrFail userDecoder SelectUser
            ]

debCfg : Debounce.Config Model Msg
debCfg = Debounce.config .debouncer (\m s -> { m | debouncer = s }) Deb 400

