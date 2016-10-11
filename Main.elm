port module App exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Json.Decode as J exposing ((:=))
import Platform.Cmd as Cmd
import Array exposing (Array)
import Dict exposing (Dict)
import Navigation exposing (Location)
import Cmd.Extra
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
        , subscriptions = \_ -> Sub.none
        }


-- MODEL

init : Location -> (Model, Cmd Msg)
init _ =
    ( Model
        (Author "fiatjaf" "https://secure.gravatar.com/avatar/b760f503c84d1bf47322f401066c753f.jpg?s=256")
        [] [] ""
    , Cmd.none
    )

type alias Model =
    { me : Author
    , cards : List Card
    , messages : List Message
    , typing : String
    }

type alias Card =
    { name : String
    , desc : String
    , comments : List Message
    }

type alias Message =
    { author : Author
    , text : String
    }

type alias Author =
    { name : String
    , imageURL : String
    }


-- UPDATE

type Msg
    = TypeMessage String
    | PostMessage
    | CreateCard Card


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        TypeMessage v ->
            { model | typing = v } ! []
        PostMessage ->
            let
                text = model.typing |> String.trim
                newmessage = (Message model.me text)
                action =
                    if String.left 5 text == "/card" then
                        Cmd.Extra.message
                            <| CreateCard (Card "" (String.dropLeft 5 text) [])
                    else Cmd.none
            in
                { model
                    | messages = newmessage :: model.messages
                    , typing = ""
                } ! [ action ]
        CreateCard card ->
                { model
                    | cards = card :: model.cards
                } ! []


-- VIEW

view : Model -> Html Msg
view model =
    node "html" []
        [ node "link" [ rel "stylesheet", href "style.css" ] []
        , node "main" []
            [ section [ id "chat" ] [ chatView <| log "model" model ]
            , section [ id "cards" ] [ cardsView model ]
            ]
        ]

chatView : Model -> Html Msg
chatView model =
    div []
        [ div [ id "messages" ]
            ( model.messages
                |> List.take 50
                |> List.reverse
                |> List.map (lazy messageView)
            )
        , node "form" [ id "input", onSubmit PostMessage ]
            [ input [ onInput TypeMessage, value model.typing ] []
            , button [] [ text "Send" ]
            ]
        ]

messageView : Message -> Html Msg
messageView message =
    div [ class "message" ]
        [ div [ class "author" ]
            [ img [ src message.author.imageURL ] []
            , text message.author.name
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
