module Types exposing (..)

import Json.Decode as JD exposing ((:=))
import Json.Encode as JE exposing (Value)
import Dict exposing (Dict)
import Time exposing (Time)
import ElmTextSearch as Search
import Array exposing (Array)
import String
import Debounce


type alias Card =
    { id : String
    , name : String
    , contents: Array Content
    , comments : List Message
    }

type Content = Text String | Conversation (List Message)

cardDecoder : JD.Decoder Card
cardDecoder = JD.object4 Card
    ("_id" := JD.string)
    ("name" := JD.string)
    ("contents" :=
        ( JD.array <|
            JD.oneOf
                [ JD.object1 Text JD.string
                , JD.object1 Conversation <| JD.list messageDecoder
                ]
        )
    )
    (JD.succeed [])

encodeCard : String -> Array Content -> Value
encodeCard name contents =
    JE.object
        [ ("name", JE.string <| String.trim name )
        , 
            ( "contents"
            , JE.array <|
                Array.map encodeContent contents
            )
        ]

encodeContent : Content -> Value
encodeContent content =
    let encodeMessageContent message =
        JE.object
            [ ("_id", JE.string message.id)
            , ("author", encodeUser message.author.name message.author.machineId message.author.pictureURL)
            , ("text", JE.string <| String.trim message.text)
            ]
    in case content of
        Text text -> JE.string text
        Conversation messages ->
            JE.list <| List.map encodeMessageContent messages


type alias Message =
    { id : String
    , author : User
    , text : String
    , selected : Bool
    }

messageDecoder : JD.Decoder Message
messageDecoder = JD.object4 Message
    ("_id" := JD.string)
    ("author" := userDecoder)
    ("text" := JD.string)
    (JD.succeed False)

encodeMessage : User -> String -> Value
encodeMessage author text =
    JE.object
        [ ("author", encodeUser author.name author.machineId author.pictureURL)
        , ("text", JE.string text)
        ]


type alias User =
    { machineId : String
    , name : String
    , pictureURL : String
    }

userDecoder : JD.Decoder User
userDecoder =
    JD.customDecoder
        ( JD.object3 User
            ("machineId" := JD.string)
            ("name" := JD.string)
            ("pictureURL" := JD.string)
        )
        (\r -> Ok { r | pictureURL = if r.pictureURL == "" then "https://api.adorable.io/avatars/140/" ++ r.name ++ ".png" else r.pictureURL })

encodeUser : String -> String -> String -> Value
encodeUser name machineId pictureURL =
    JE.object
        [ ("name", JE.string name)
        , ("machineId", JE.string machineId)
        , ("pictureURL", JE.string pictureURL)
        ]


type alias Channel =
    { name : String
    , websocket : String
    }


type PeerStatus
    = Connecting
    | Closed
    | Connected
        { replicating : Bool
        , lastSent : Time
        , lastReceived : Time
        }
    | Weird Int


-- MODEL

type alias Model =
    { channel : Channel
    , channels : List String
    , me : User
    , messages : List Message
    , menu : String
    , typing : String
    , prevTyping : String
    , cards : List Card
    , cardSearchIndex : Search.Index Card
    , cardMode : CardMode
    , users : List User
    , websocket : Bool
    , webrtc : Dict String PeerStatus
    , debouncer : Debounce.State
    }

type CardMode = Normal | SearchResults String (List String) | Focused Card CardMode Editing
type Editing = None | Name | Content Int
