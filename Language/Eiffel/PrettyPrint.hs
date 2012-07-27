module Language.Eiffel.PrettyPrint where

import Data.Char

import Text.PrettyPrint

import Language.Eiffel.Syntax
import Language.Eiffel.Position

defaultIndent = 2
nestDef = nest defaultIndent

renderWithTabs = fullRender (mode style) (lineLength style) (ribbonsPerLine style) spacesToTabs ""
  where
    spacesToTabs :: TextDetails -> String -> String
    spacesToTabs (Chr c) s  = c:s
    spacesToTabs (Str s1) s2 = if s1 == replicate (length s1) ' ' && length s1 > 1 
      then replicate (length s1 `div` defaultIndent) '\t' ++ s2 
      else s1 ++ s2

newline = char '\n'
emptyLine = text ""

ups = map toUpper

toDoc :: Clas -> Doc
toDoc = toDocWith False routineBodyDoc

toInterfaceDoc :: ClasInterface -> Doc
toInterfaceDoc = toDocWith True interfaceBodyDoc

interfaceBodyDoc :: EmptyBody -> Doc
interfaceBodyDoc = const (text "do")

toDocWith fullAttr bodyDoc c =   
  let defer = if deferredClass c then text "deferred" else empty
      froz  = if frozenClass c then text "frozen" else empty
      expnd = if expandedClass c then text "expanded" else empty 
  in vsep [ notes (classNote c) $+$ (if null (classNote c) then empty else emptyLine)
          , defer <+> froz <+> expnd <+> text "class"
          , nestDef (text (ups $ className c)) <+> genericsDoc (generics c) <+> procGenDoc (procGeneric c)
          , emptyLine
          , inheritance (inherit c)
          , vsep (map createClause (creates c))
          , convertClause (converts c)
          , vsep (map (featureClause fullAttr bodyDoc) (featureClauses c))
          , invars (invnts c)
          , text "end"
          ]


inheritance is = vsep (map inheritanceClauses is)

inheritanceClauses (Inheritance nonConform cs) =
  let conformMark | nonConform = text "{NONE}"
                  | otherwise  = empty
  in (text "inherit" <+> conformMark) $+$ nestDef (vsep (map inheritClause cs))

inheritClause (InheritClause cls renames exports undefs redefs selects) = 
  let renameDoc (Rename orig new alias) =
        text orig <+> text "as" <+> text new <+> 
          maybe empty (\a -> text "alias" <+> doubleQuotes (text a)) alias
      exportListDoc (ExportFeatureNames l) = vCommaSep (map text l)
      exportListDoc ExportAll = text "all"
      exportDoc (Export to what) =
        braces (commaSep (map text to)) $+$ nestDef (exportListDoc what)
  in type' cls $+$ nestDef (vsep
          [ text "rename" $?$ nestDef (vCommaSep (map renameDoc renames))
          , text "export" $?$ nestDef (vsep (map exportDoc exports))
          , text "undefine" $?$ nestDef (vCommaSep (map text undefs))
          , text "redefine" $?$ nestDef (vCommaSep (map text redefs))
          , text "select" $?$ nestDef (vCommaSep (map text selects))
          , if null renames && null exports && null undefs && null redefs && null selects
            then empty else text "end"
          , emptyLine
          ])
      
createClause (CreateClause exports names) = 
  let exps = if null exports 
             then empty 
             else  braces (commaSep (map text exports))
  in (text "create" <+> exps) $+$ nestDef (commaSep (map text names)) $+$ emptyLine
  
convertClause []    = empty
convertClause convs =
  let go (ConvertFrom fname ts) = text fname <+> 
                                  parens (braces (commaSep (map type' ts)))
      go (ConvertTo fname ts) = text fname <> colon <+> 
                                braces (commaSep (map type' ts))
  in text "convert" $+$ nestDef (vCommaSep (map go convs)) $+$ emptyLine

featureClause fullAttr bodyDoc (FeatureClause exports featrs attrs consts) = 
  let exps = if null exports 
             then empty 
             else  braces (commaSep (map text exports))
  in vsep [ text "feature" <+> exps
          , emptyLine
          , nestDef $ vsep $ map (($+$ emptyLine) . routineDoc bodyDoc) featrs
          , nestDef $ vsep $ map (($+$ emptyLine) . attrDoc fullAttr) attrs
          , nestDef $ vsep $ map (($+$ emptyLine) . constDoc) consts
          ]


vsep = foldr ($+$) empty
commaSep = hsep . punctuate comma
vCommaSep = vsep . punctuate comma
angles d = langle <> d <> rangle
langle = char '<'
rangle = char '>'
squareQuotes t = text "\"[" <> t <> text "]\""
                      
anyStringLiteral s = case s of
  '\n':_      -> squareQuotes $ text s
  '\r':'\n':_ -> squareQuotes $ text s
  _           -> doubleQuotes $ stringLiteral s


stringLiteral s = text s'
  where s' = go s
        go ('\n':cs) = "%N" ++ go cs
        go ('\r':cs) = "%R" ++ go cs
        go ('\t':cs) = "%T" ++ go cs
        go ('"': cs) = "%\"" ++ go cs
        go (c:cs) = c : go cs
        go [] = []

procDoc (Proc s) = text s

genericsDoc [] = empty
genericsDoc gs = brackets (commaSep (map go gs))
  where go (Generic name constr createsMb) = 
          text name <+> constraints constr <+> maybe empty creates createsMb
        constraints []  = empty
        constraints [t] = text "->" <+> type' t
        constraints ts  = text "->" <+> braces (commaSep (map type' ts))
        creates cs = hsep [ text "create"
                          , commaSep (map text cs)
                          , text"end"
                          ]
                            
notes [] = empty
notes ns = vsep [ text "note"
                , nestDef (vsep $ map note ns)
                ]

note (Note tag content) = text tag <> colon <+> commaSep (map (expr' 0) content)

invars is = text "invariant" $?$ clausesDoc is
                 

procGenDoc [] = empty
procGenDoc ps = go ps
  where go = angles . hsep . punctuate comma . map procDoc

decl :: Decl -> Doc
decl (Decl label typ) = text label <> typeDoc typ

typeDoc NoType = empty
typeDoc t = text ":" <+> type' t

frozen b = if b then text "frozen" else empty

require (Contract inh c) = (if inh then text "require else" else text "require") $?$ clausesDoc c
ensure (Contract inh c) = (if inh then text "ensure then" else text "ensure") $?$ clausesDoc c

constDoc :: Constant Expr -> Doc
constDoc (Constant froz d val) = frozen froz <+> decl d <+> text "=" <+> expr val

attrDoc :: Bool -> Attribute Expr -> Doc
attrDoc fullAttr (Attribute froz d assn ns reqs ens) = 
  frozen froz <+> decl d <+> assignText assn $+$
  nestDef (vsep [ notes ns
       , require reqs
       , attrKeyword
       , ensure ens
       , endKeyword
       ])
  where assignText Nothing  = empty
        assignText (Just a) = text "assign" <+> text a
        hasBody     = not (null (contractClauses ens) && null (contractClauses reqs) && null ns)
        attrKeyword | hasBody || fullAttr = text "attribute"
                    | otherwise = empty
        endKeyword  | hasBody || fullAttr = text "end"
                    | otherwise = empty

type' :: Typ -> Doc
type' (ClassType str gens) = text (ups str) <+> genDoc gens
type' VoidType   = text "NONE"
type' (Like s)   = text "like" <+> text s
type' NoType     = empty
type' (Sep mP ps str) = sepDoc <+> procM mP <+> procs ps <+> text str
type' (TupleType typeDecls) = 
  let typeArgs = 
        case typeDecls of
          Left types -> commaSep (map type' types)
          Right decls -> hcat (punctuate (text ";") (map decl decls))
      tupleGen | isEmpty typeArgs = empty
               | otherwise        = text "[" <> typeArgs <> text "]"
  in text "TUPLE" <+> tupleGen

routineDoc :: (body -> Doc) -> AbsRoutine body Expr -> Doc
routineDoc bodyDoc f 
    = let header = frozen (routineFroz f) <+>
                   text (routineName f) <+>
                   alias <+>
                   formArgs (routineArgs f) <> 
                   typeDoc (routineResult f) <+>
                   procs (routineProcs f)
          alias = 
            case routineAlias f of
              Nothing   -> empty
              Just name -> text "alias" <+> doubleQuotes (text name)
          assign =
            case routineAssigner f of
              Nothing -> empty
              Just name -> text "assign" <+> text name
          rescue =
            case routineRescue f of
              Nothing -> empty
              Just stmts -> text "rescue" $+$
                nestDef (vsep $ map stmt stmts)
      in header <+> assign $+$ 
          (nestDef $ vsep 
           [ notes (routineNote f)
           , require (routineReq f)
           , text "require-order" $?$ nestDef (procExprs f)
           , text "lock" $?$ nestDef (locks (routineEnsLk f))
           , bodyDoc $ routineImpl f
           , ensure (routineEns f)
           , rescue
           , text "end"
           ]
          )

routineBodyDoc RoutineDefer = text "deferred"
routineBodyDoc (RoutineExternal s aliasMb) = 
  vcat [ text "external" 
       , nestDef (anyStringLiteral s)
       , text "alias" $?$ maybe empty anyStringLiteral aliasMb
       ]
routineBodyDoc ft = vsep [ locals ft
                         , text "do"
                         , nestDef $ stmt $ routineBody ft
                         ]

locals ft = text "local" $?$ nestDef (vsep $ map decl (routineLocal ft))

procExprs = vCommaSep . map procExprD . routineReqLk

($?$) :: Doc -> Doc -> Doc
($?$) l e 
    | isEmpty e = empty
    | otherwise = l $+$ e

(<?>) :: Doc -> Doc -> Doc
(<?>) l e 
    | isEmpty e = empty
    | otherwise = l <?> e


clausesDoc :: [Clause Expr] -> Doc
clausesDoc cs = nestDef (vsep $ map clause cs)

clause :: Clause Expr -> Doc
clause (Clause nameMb e) = maybe empty (\n -> text n <> colon) nameMb <+> expr e

stmt = stmt' . contents

stmt' (Assign l e) = expr l <+> text ":=" <+> expr e
stmt' (AssignAttempt l e) = expr l <+> text "?=" <+> expr e
stmt' (CallStmt e) = expr e
stmt' (If cond body elseParts elseMb) = 
  let elsePart = case elseMb of
        Just elsee -> vsep [text "else", nestDef (stmt elsee)]
        Nothing -> empty
      elseifPart (ElseIfPart c s) =
        vsep [ text "elseif" <+> expr c <+> text "then"
             , nestDef (stmt s)
             ]
      elseifParts es = vsep (map elseifPart es)
  in vsep [ text "if" <+> expr cond <+> text "then"
          , nestDef (stmt body)
          , elseifParts elseParts
          , elsePart
          , text "end"
          ]
stmt' (Inspect e whens elseMb) =
  let elsePart = case elseMb of
        Nothing -> empty
        Just s -> text "else" $+$ nestDef (stmt s)
      whenParts (es', s) = 
        (text "when" <+> commaSep (map expr es') <+> text "then") $+$ 
        nestDef (stmt s)
  in vsep [ text "inspect" <+> expr e
          , vsep (map whenParts whens)
          , elsePart
          , text "end"
          ]
stmt' (Across e asIdent body) =
  vcat [ text "across"
       , nestDef (expr e <+> text "as" <+> text asIdent)
       , text "loop"
       , nestDef (stmt body)
       , text "end"
       ]
stmt' (BuiltIn)  = text "builtin"
stmt' (Create t tar n es) = text "create" <+> maybe empty (braces . type') t <+> 
  if n == defaultCreate then expr tar else expr' 0 (QualCall tar n es)
stmt' (Block ss) = vsep (map stmt ss)
stmt' (Check cs) = vsep [ text "check"
                        , nestDef (vsep (map clause cs))
                        , text "end"
                        ]
stmt' (CheckBlock cs body) = 
  vsep [ text "check" <+> vsep (map clause cs) <+> text "then"
       , stmt body
       , text "end"
       ]
stmt' (Loop from invs cond loop var) = 
  vsep [ text "from"
       , nestDef (stmt from)
       , text "invariant" $?$ clausesDoc invs
       , text "until"
       , nestDef (expr cond)
       , text "loop"
       , nestDef (stmt loop)
       , text "variant" $?$ maybe empty (nestDef . expr) var
       , text "end"
       ]
stmt' (Debug str body) = 
  vsep [ text "debug" <+> (if null str then empty else (parens . anyStringLiteral) str)
       , nestDef (stmt body)
       , text "end"
       ]
stmt' Retry = text "retry"
stmt' s = error ("PrettyPrint.stmt': " ++ show s)

expr = exprPrec 0

exprPrec :: Int -> Expr -> Doc
exprPrec i = expr' i . contents

expr' _ (UnqualCall n es) = text n <+> actArgs es
expr' _ (QualCall t n es) = target <> text n <+> actArgs es
    where 
      target = case contents t of
                 CurrentVar -> empty
                 _ -> exprPrec 13 t <> char '.'
expr' _ (PrecursorCall cname es) = 
  text "Precursor" <+> maybe empty (braces . text) cname <+> actArgs es
expr' i (AcrossExpr e as q body) =
  hsep [ text "across"
       , exprPrec i e
       , text "as"
       , text as
       , quant q
       , expr body
       , text "end"
       ]
expr' i (UnOpExpr uop e) = condParens (i > 12) $ text (unop uop) <+> exprPrec 12 e
expr' i (Lookup targ args) = case targ of
  Pos _ (Lookup _ _) -> parens (exprPrec i targ) <+> brackets (commaSep (map expr args))
  _ -> exprPrec i targ <+> brackets (commaSep (map expr args))
expr' i (BinOpExpr (SymbolOp op) e1 e2)
  | op == "[]" = exprPrec i e1 <+> brackets (expr e2)
  | otherwise =  condParens (i > 11) 
                 (exprPrec 11 e1 <+> text op <+> exprPrec 12 e2)
expr' i (BinOpExpr bop e1 e2) = 
  condParens (i > p) 
             (exprPrec lp e1 <+> text op <+> exprPrec rp e2)
  where (op, p) = binop bop
        lp = p
        rp = p + 1
expr' _ (Attached t e asVar) = 
  text "attached" <+> maybe empty (braces . type') t <+> 
  expr e <+> maybe empty (\s -> text "as" <+> text s) asVar
expr' _ (CreateExpr t n es) = 
  text "create" <+> braces (type' t) <> if n == defaultCreate then empty else char '.' <> text n <+> actArgs es
expr' _ (StaticCall t i args) = 
  braces (type' t) <> char '.' <> text i <+> actArgs args
expr' _ (LitArray es) = text "<<" <> commaSep (map expr es) <> text ">>"
expr' _ (ManifestCast t e) = braces (type' t) <+> expr e
expr' _ (OnceStr s)   = text "once" <+> text s
expr' _ (Address e)   = text "$" <> expr e
expr' _ (VarOrCall s) = text s
expr' _ ResultVar     = text "Result"
expr' _ CurrentVar    = text "Current"
expr' _ LitVoid       = text "Void"
expr' _ (LitChar c)   = quotes (char c)
expr' _ (LitString s) = anyStringLiteral s
expr' _ (LitInt i)    = integer i
expr' _ (LitBool b)   = text (show b)
expr' _ (LitDouble d) = double d
expr' i (LitType t)   = condParens (i > 12) $ braces (type' t)
expr' _ (Tuple es)    = brackets (hcat $ punctuate comma (map expr es))
expr' _ (Agent e)     = text "agent" <+> case contents e of
  QualCall t n es -> case contents t of
    VarOrCall s -> expr e
    _ -> parens (expr t) <> char '.' <> text n <+> actArgs es
  _ -> expr e
expr' _ (InlineAgent ds resMb ss args)  = 
  let decls = formArgs ds
      res   = maybe empty (\t -> colon <+> type' t) resMb
  in vsep [ text "agent" <+> decls <+> res
          , text "do"
          , nestDef $ vsep (map stmt ss)
          , text "end" <+> condParens (not $ null args)
                                      (commaSep (map expr args))
          ]
expr' _ s                 = error ("expr': " ++ show s)

quant All = text "all"
quant Some = text "some"

condParens True  e = parens e
condParens False e = e

unop Neg = "-"
unop Not = "not"
unop Old = "old"

opList = [ (Pow, ("^", 10))
         , (Mul, ("*", 9))
         , (Div, ("/", 9))
         , (Quot, ("//", 9))
         , (Rem, ("\\\\", 9))
         , (Add, ("+", 8))
         , (Sub, ("-", 8))
         , (And, ("and", 5))
         , (AndThen, ("and then", 5))
         , (Or,  ("or", 4))
         , (Xor, ("xor", 4))
         , (OrElse,  ("or else", 4))
         , (Implies, ("implies", 3))
         ]

binop :: BinOp -> (String, Int)
binop (SymbolOp o) = (o, 11)
binop (RelOp r _)  = (relop r, 6)
binop o = 
  case lookup o opList of
    Just (n,p) -> (n,p)
    Nothing -> error "binop: could not find operator"

relop Lt  = "<"
relop Lte = "<="
relop Gt  = ">"
relop Gte = ">="
relop Eq  = "="
relop Neq = "/="
relop TildeEq = "~"
relop TildeNeq = "/~"

actArgs [] = empty
actArgs es = parens $ hsep $ punctuate comma (map expr es)

formArgs [] = empty
formArgs ds = parens $ hsep $ punctuate semi (map decl ds) 

genDoc :: [Typ] -> Doc
genDoc [] = empty
genDoc ps = brackets $ hcat $ punctuate comma (map type' ps)

procExprD (LessThan a b) = proc a <+> langle <+> proc b
locks [] = empty
locks ps = hsep $ punctuate comma (map proc ps)

procs [] = empty
procs ps = angles $ locks ps
proc (Proc p) = text p
proc Dot      = text "dot_proc"
procM = maybe empty (angles . proc)
sepDoc = text "separate"