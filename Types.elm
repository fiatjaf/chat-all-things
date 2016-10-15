module Types exposing (..)

import Json.Decode as JD exposing ((:=))
import Json.Encode as JE exposing (Value)
import Array exposing (Array)

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
        [ ("type", JE.string "card")
        , ("name", JE.string name )
        , 
            ( "contents"
            , JE.array <|
                Array.map encodeContent contents
            )
        ]

encodeContent : Content -> Value
encodeContent content =
    case content of
        Text text -> JE.string text
        Conversation messages ->
            JE.list <| List.map (\m -> encodeMessage m.author m.text) messages

type alias Message =
    { id : String
    , author : String
    , text : String
    , selected : Bool
    }

messageDecoder : JD.Decoder Message
messageDecoder = JD.object4 Message
    ("_id" := JD.string)
    ("author" := JD.string)
    ("text" := JD.string)
    (JD.succeed False)

encodeMessage : String -> String -> Value
encodeMessage author text =
    JE.object
        [ ("type", JE.string "message")
        , ("author", JE.string author)
        , ("text", JE.string text)
        ]
