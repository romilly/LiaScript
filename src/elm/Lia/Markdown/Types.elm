module Lia.Markdown.Types exposing (Markdown(..), MarkdownS)

import Lia.Markdown.Chart.Types exposing (Chart)
import Lia.Markdown.Code.Types exposing (Code)
import Lia.Markdown.Effect.Types exposing (Effect)
import Lia.Markdown.HTML.Attributes exposing (Parameters)
import Lia.Markdown.HTML.Types exposing (Node)
import Lia.Markdown.Inline.Types exposing (Inlines)
import Lia.Markdown.Quiz.Types exposing (Quiz)
import Lia.Markdown.Survey.Types exposing (Survey)
import Lia.Markdown.Table.Types exposing (Table)


type Markdown
    = HLine Parameters
    | Quote Parameters MarkdownS
    | Paragraph Parameters Inlines
    | BulletList Parameters (List MarkdownS)
    | OrderedList Parameters (List ( String, MarkdownS ))
    | Table Parameters Table
    | Quiz Parameters Quiz (Maybe ( MarkdownS, Int ))
    | Effect Parameters (Effect Markdown)
    | Comment ( Int, Int )
    | Survey Parameters Survey
    | Chart Parameters Chart
    | Code Parameters Code
    | ASCII Parameters String
    | HTML Parameters (Node Markdown)
    | Skip


type alias MarkdownS =
    List Markdown
