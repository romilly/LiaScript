module Lia.Definition.Parser exposing (parse)

import Combine exposing (..)
import Lia.Definition.Types exposing (Definition, add_translation)
import Lia.Helper exposing (..)
import Lia.Macro.Parser as Macro
import Lia.Markdown.Inline.Parser exposing (comment, comments)
import Lia.PState exposing (PState, ident_skip, identation, identation_append, identation_pop)
import Lia.Utils exposing (string_replace)


parse : Parser PState ()
parse =
    lazy <|
        \() ->
            definition
                |> keep (modifyState (\s -> { s | defines_updated = True }))
                |> maybe
                |> ignore whitespace
                |> skip


definition : Parser PState ()
definition =
    lazy <|
        \() ->
            let
                list =
                    choice
                        [ string "author:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | author = x })))
                        , string "base:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | base = x })))
                        , string "comment:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | comment = string_replace ( "\n", " " ) x })))
                        , string "date:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | date = x })))
                        , string "email:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | email = x })))
                        , string "language:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | language = x })))
                        , string "logo:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | logo = x })))
                        , string "narrator:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | narrator = x })))
                        , string "script:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | scripts = append_to x def.base def.scripts })))
                        , string "link:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | links = append_to x def.base def.links })))
                        , string "translation:"
                            |> keep (ending |> andThen (\x -> set (add_translation x)))
                        , string "version:"
                            |> keep (ending |> andThen (\x -> set (\def -> { def | version = x })))
                        , string "debug:"
                            |> keep
                                (ending
                                    |> andThen
                                        (\x ->
                                            set
                                                (\def ->
                                                    { def
                                                        | debug =
                                                            if x == "true" then
                                                                True

                                                            else
                                                                False
                                                    }
                                                )
                                        )
                                )
                        , regex "@onload[\t ]*\\n"
                            |> keep (stringTill (string "\n@end"))
                            |> andThen (\x -> set (\def -> { def | onload = String.trim x }))
                        , Macro.pattern
                            |> ignore (regex "[\t ]*:[\t ]*")
                            |> map (,)
                            |> andMap (regex ".+")
                            |> ignore newline
                            |> andThen (\x -> set (Macro.add x))
                        , Macro.pattern
                            |> ignore (regex "[\t ]*\\n")
                            |> map (,)
                            |> andMap (stringTill (string "\n@end"))
                            |> andThen (\x -> set (Macro.add x))
                        ]
            in
            (whitespace |> keep list)
                |> many1
                |> ignore whitespace
                |> comment
                |> skip


ending : Parser PState String
ending =
    identation_append "  "
        |> ignore ident_skip
        |> keep (many1 (identation |> keep (regex ".+\\n")))
        |> ignore identation_pop
        |> map (\list -> list |> List.map String.trimLeft |> String.concat |> String.trimRight)


base : String -> Parser PState ()
base x =
    set
        (\def ->
            { def | base = toURL def.base x }
        )


toURL : String -> String -> String
toURL base url =
    if String.startsWith "http" url then
        url

    else
        base ++ url


set : (Definition -> Definition) -> Parser PState ()
set fct =
    modifyState (\s -> { s | defines = fct s.defines })


append_to : String -> String -> List String -> List String
append_to x base list =
    x
        |> String.split "\n"
        |> List.map (toURL base)
        |> List.append list
