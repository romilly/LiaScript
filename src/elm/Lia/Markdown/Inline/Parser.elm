module Lia.Markdown.Inline.Parser exposing
    ( annotations
    , combine
    , comment
    , comment_string
    , comments
    , inlines
    , javascript
    , line
    , lineWithProblems
    , parse_inlines
    )

import Combine
    exposing
        ( Parser
        , andMap
        , andThen
        , choice
        , ignore
        , keep
        , lazy
        , many
        , many1
        , manyTill
        , map
        , maybe
        , modifyState
        , optional
        , or
        , regex
        , runParser
        , skip
        , string
        , succeed
        , whitespace
        , withState
        )
import Combine.Char exposing (anyChar)
import Lia.Markdown.Effect.Model exposing (add_javascript)
import Lia.Markdown.Effect.Parser as Effect
import Lia.Markdown.Footnote.Parser as Footnote
import Lia.Markdown.HTML.Attributes as Attributes exposing (Parameters)
import Lia.Markdown.HTML.Parser as HTML
import Lia.Markdown.Inline.Multimedia as Multimedia
import Lia.Markdown.Inline.Parser.Formula exposing (formula)
import Lia.Markdown.Inline.Parser.Symbol exposing (arrows, smileys)
import Lia.Markdown.Inline.Types exposing (Inline(..), Inlines, Reference(..))
import Lia.Markdown.Macro.Parser as Macro
import Lia.Parser.Context exposing (Context, searchIndex)
import Lia.Parser.Helper exposing (spaces, stringTill)


parse_inlines : Context -> String -> Inlines
parse_inlines state str =
    case
        str
            |> String.replace "\n" " "
            |> runParser line state
    of
        Ok ( _, _, rslt ) ->
            rslt

        Err _ ->
            []


comment : Parser s a -> Parser s (List a)
comment p =
    string "<!--"
        |> ignore whitespace
        |> keep (manyTill p (string "-->"))


comment_string : Parser s String
comment_string =
    anyChar
        |> comment
        |> map (String.fromList >> String.trim)


comments : Parser Context ()
comments =
    Effect.hidden_comment
        |> or (skip (comment anyChar))
        |> many
        |> skip


annotations : Parser Context Parameters
annotations =
    let
        attr =
            withState (.defines >> .base >> succeed)
                |> andThen Attributes.parse
    in
    spaces
        |> keep (comment attr)
        |> map styling
        |> maybe
        |> map (Maybe.withDefault [])
        |> ignore comments


styling : Parameters -> Parameters
styling p =
    if p == [] then
        []

    else if List.any (Tuple.first >> (==) "style") p then
        p
            |> List.map
                (\( key, value ) ->
                    ( key
                    , if key == "style" then
                        "display: inline-block; " ++ value

                      else
                        value
                    )
                )

    else
        ( "style", "display: inline-block;" ) :: p


javascript : Parser s String
javascript =
    string "<script>"
        |> keep (stringTill (string "</script>"))


html : Parser Context Inline
html =
    let
        state script =
            modifyState
                (\s ->
                    { s
                        | effect_model =
                            add_javascript
                                (s.effect_number
                                    |> List.head
                                    |> Maybe.withDefault 0
                                )
                                script
                                s.effect_model
                    }
                )
    in
    javascript
        |> andThen state
        |> keep (succeed (Chars "" []))


combine : Inlines -> Inlines
combine list =
    case list of
        [] ->
            []

        [ xs ] ->
            [ xs ]

        x1 :: x2 :: xs ->
            case ( x1, x2 ) of
                ( Chars str1 [], Chars str2 [] ) ->
                    combine (Chars (str1 ++ str2) [] :: xs)

                _ ->
                    x1 :: combine (x2 :: xs)


line : Parser Context Inlines
line =
    inlines |> many1 |> map combine


lineWithProblems : Parser Context Inlines
lineWithProblems =
    or inlines (regex "." |> map (\x -> Chars x []))
        |> many1
        |> map combine


inlines : Parser Context Inline
inlines =
    lazy <|
        \() ->
            Macro.macro
                |> keep
                    ([ code
                     , Footnote.inline
                     , reference
                     , formula
                     , inlines |> Effect.inline |> map EInline
                     , strings
                     ]
                        |> choice
                        |> andMap (Macro.macro |> keep annotations)
                        |> or html
                    )


url : Parser s String
url =
    regex "[a-zA-Z]+://(/)?[a-zA-Z0-9\\.\\-\\_]+\\.([a-z\\.]{2,6})[^ \\]\\)\t\n]*"


email : Parser s String
email =
    string "mailto:"
        |> maybe
        |> keep (regex "[a-zA-Z0-9_.\\-]+@[a-zA-Z0-9_.\\-]+")
        |> map ((++) "mailto:")


inline_url : Parser s (Parameters -> Inline)
inline_url =
    map (\u -> Ref (Link [ Chars u [] ] u "")) url


ref_info : Parser Context Inlines
ref_info =
    string "["
        |> keep (manyTill inlines (string "]"))


ref_title : Parser s String
ref_title =
    spaces
        |> ignore (string "\"")
        |> keep (stringTill (string "\""))
        |> ignore spaces
        |> optional ""


ref_url_1 : Parser Context String
ref_url_1 =
    choice
        [ url
        , andMap (regex "#[\\w-]+") searchIndex
        , andMap (regex "#\\S+") searchIndex
        , regex "[^\\)\n \"]*"
        ]


ref_url_2 : Parser Context String
ref_url_2 =
    withState (\s -> succeed s.defines.base)
        |> map (++)
        |> andMap (regex "[^\\)\n \"]*")
        |> or url



--ref_pattern : (a -> String -> String -> b) -> Parser s a -> Parser s String -> Parser s b
--ref_pattern : a -> b -> c -> Parser Context Reference


ref_pattern :
    (m -> String -> String -> Reference)
    -> Parser Context m
    -> Parser Context String
    -> Parser Context Reference
ref_pattern ref_type info_type url_type =
    map (nicer_ref ref_type) info_type
        |> ignore (string "(")
        |> andMap url_type
        |> andMap ref_title
        |> ignore (string ")")


nicer_ref :
    (m -> String -> String -> Reference)
    -> m
    -> String
    -> String
    -> Reference
nicer_ref ref_type info_string url_string title_string =
    ref_type info_string
        url_string
        (if String.isEmpty title_string then
            url_string

         else
            title_string
        )


ref_audio : Parser Context Reference
ref_audio =
    map Audio ref_info
        |> ignore (string "(")
        |> andMap (map Multimedia.audio ref_url_2)
        |> andMap ref_title
        |> ignore (string ")")


ref_video : Parser Context Reference
ref_video =
    map Movie ref_info
        |> ignore (string "(")
        |> andMap (map Multimedia.movie ref_url_2)
        |> andMap ref_title
        |> ignore (string ")")


reference : Parser Context (Parameters -> Inline)
reference =
    let
        mail_ =
            ref_pattern Mail ref_info email

        link =
            ref_pattern Link ref_info ref_url_1

        image =
            string "!"
                |> keep (ref_pattern Image ref_info ref_url_2)

        audio =
            string "?"
                |> keep ref_audio

        movie =
            string "!?"
                |> keep ref_video

        embed =
            string "??"
                |> keep (ref_pattern Embed ref_info ref_url_1)
    in
    [ embed, movie, audio, image, mail_, link ]
        |> choice
        |> map Ref


between_ : String -> Parser Context Inline
between_ str =
    string str
        |> keep (manyTill inlines (string str))
        |> map toContainer


toContainer : List Inline -> Inline
toContainer inline_list =
    case combine inline_list of
        [ one ] ->
            one

        moreThanOne ->
            Container moreThanOne []


strings : Parser Context (Parameters -> Inline)
strings =
    lazy <|
        \() ->
            let
                base =
                    regex "[^*_~:;`!\\^\\[\\]\\(\\)|{}\\\\\\n\\-<>=$ ]+"
                        |> map Chars

                escape =
                    string "\\"
                        |> keep (regex "[\\^*_+-~`\\\\${}\\[\\]|#]")
                        |> map Chars

                italic =
                    or (between_ "*") (between_ "_")
                        |> map Italic

                bold =
                    or (between_ "**") (between_ "__")
                        |> map Bold

                strike =
                    between_ "~"
                        |> map Strike

                underline =
                    between_ "~~"
                        |> map Underline

                superscript =
                    between_ "^"
                        |> map Superscript

                characters =
                    regex "[~:_;\\-=${}\\[\\]\\(\\)]"
                        |> map Chars

                spaces =
                    regex "[ \\t]+"
                        |> map Chars

                base2 =
                    regex "[^\n*|+<>]+"
                        |> map Chars
            in
            choice
                [ inline_url
                , base
                , arrows
                , smileys
                , escape
                , bold
                , italic
                , underline
                , strike
                , superscript
                , spaces
                , HTML.parse inlines |> map IHTML
                , characters
                , base2
                ]


code : Parser s (Parameters -> Inline)
code =
    string "`"
        |> keep (regex "[^`\\n]+")
        |> ignore (string "`")
        |> map Verbatim
