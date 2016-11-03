module Types exposing (..)

import Json.Decode as JD exposing ((:=))
import Json.Encode as JE exposing (Value)
import Dict exposing (Dict)
import Time exposing (Time)
import Array exposing (Array)
import String


type alias Card =
    { id : String
    , name : String
    , contents: Array Content
    , comments : List Message
    }

type Content = Note String | Conversation (List Message)

cardDecoder : JD.Decoder Card
cardDecoder = JD.object4 Card
    ("_id" := JD.string)
    ("name" := JD.string)
    ("contents" :=
        ( JD.array <|
            JD.oneOf
                [ JD.object1 Note JD.string
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
        Note text -> JE.string text
        Conversation messages -> JE.list <| List.map encodeMessageContent messages


type alias Message =
    { id : String
    , author : User
    , text : String
    , torrent : Maybe Torrent
    , selected : Bool
    }

messageDecoder : JD.Decoder Message
messageDecoder = JD.object5 Message
    ("_id" := JD.string)
    ("author" := userDecoder)
    (JD.oneOf [ ("text" := JD.string), JD.succeed ""])
    (JD.maybe ("torrent" := torrentDecoder))
    (JD.succeed False)

encodeMessage : User -> String -> Maybe Torrent -> Value
encodeMessage author text t =
    let
        encaut = ("author", encodeUser author.name author.machineId author.pictureURL)
    in
        JE.object <| case t of
            Nothing ->
                [ encaut
                , ("text", JE.string text)
                ]
            Just torrent ->
                [ encaut
                , ("torrent", encodeTorrent torrent)
                ]


type alias Torrent =
    { magnet : String
    , files : Dict String TorrentFile
    , downloaded : Float
    , uploaded : Float
    , progress : Float
    , numPeers : Int
    }

torrentDecoder : JD.Decoder Torrent
torrentDecoder = JD.object6 Torrent
    ("magnet" := JD.string)
    ("files" := JD.dict torrentFileDecoder)
    (JD.oneOf [ ("downloaded" := JD.float), JD.succeed 0 ])
    (JD.oneOf [ ("uploaded" := JD.float), JD.succeed 0 ])
    (JD.oneOf [ ("progress" := JD.float), JD.succeed 0 ])
    (JD.oneOf [ ("numPeers" := JD.int), JD.succeed 0 ])

encodeTorrent : Torrent -> Value
encodeTorrent torrent =
    JE.object 
        [ ("magnet", JE.string torrent.magnet)
        , ("files", JE.object
            <| List.map (\f -> (f.name, encodeTorrentFile f))
            <| Dict.values torrent.files
          )
        ]

type alias TorrentFile =
    { name : String
    , length : Float
    , blobURL : String
    }

torrentFileDecoder : JD.Decoder TorrentFile
torrentFileDecoder = JD.object3 TorrentFile
    ("name" := JD.string)
    ("length" := JD.float)
    (JD.oneOf [ ("blobURL" := JD.string), JD.succeed "" ])

encodeTorrentFile : TorrentFile -> Value
encodeTorrentFile tfile =
    JE.object
        [ ("name", JE.string tfile.name)
        , ("length", JE.float tfile.length)
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
    , cardMode : CardMode
    , users : List User
    , websocket : Bool
    , webrtc : Dict String PeerStatus
    }

type CardMode = Normal | SearchResults (List Card) | Focused Card CardMode Editing
type Editing = None | Name | Content Int
