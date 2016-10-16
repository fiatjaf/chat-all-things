module Helpers exposing (..)


findIndex : (a -> Bool) -> List a -> Int
findIndex pred list =
    let
        findIndex_ pred list currentIndex =
            case list of
                [] -> currentIndex + 1
                x::xs ->
                    if pred x then currentIndex
                    else findIndex_ pred xs currentIndex + 1
    in 
        findIndex_ pred list 0
