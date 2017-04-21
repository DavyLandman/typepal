module Pico

import Prelude;
extend Constraints;

// ---- Pico syntax

lexical Id  = [a-z][a-z0-9]* !>> [a-z0-9];
lexical Natural = [0-9]+ ;
lexical String = "\"" ![\"]*  "\"";

layout Layout = WhitespaceAndComment* !>> [\ \t\n\r%];

lexical WhitespaceAndComment 
   = [\ \t\n\r]
   | @category="Comment" ws2:
    "%" ![%]+ "%"
   | @category="Comment" ws3: "%%" ![\n]* $
   ;
 
start syntax Program 
   = program: "begin" Declarations decls {Statement  ";"}* body "end"
   ;

syntax Declarations 
   = "declare" {Declaration ","}* decls ";" ;  
 
syntax Declaration 
    = decl: Id id ":" Type tp
    ;  
 
syntax Type 
   = natural:"natural" 
   | string :"string"
   ;

syntax Statement 
   = Id var ":=" Expression val                                                                      
   | "if" Expression cond "then" {Statement ";"}*  thenPart "else" {Statement ";"}* elsePart "fi"   
   | "while" Expression cond "do" {Statement ";"}* body "od"                                   
   ;  
     
syntax Expression 
   = Id name                                    
   | String string                          
   | Natural natcon                         
   | bracket "(" Expression e ")"                   
   > left ( Expression lhs "+" Expression rhs                                          
          | Expression lhs "-" Expression rhs  
          )
   ;
 
 // ---- Pico static semantics
   
// Declare Id roles: there are only variables
data IdRole
    = variableId()
    ;

// Pico types (with concrete <-> abstract mappings)

data AType = intType() |  strType() ;  

AType transType((Type) `natural`) = intType();
AType transType((Type) `string`) = strType(); 

str AType2String(intType()) = "`int`";
str AType2String(strType()) = "`str`";

// Rules for def/use
 
Tree define(d:(Declaration) `<Id id> : <Type tp>`,  Tree scope, SGBuilder sgb) {
     sgb.define(scope, "<d.id>", variableId(), d, defInfo(transType(tp)));
     return scope; 
}

void use(e: (Expression) `<Id name>`, Tree scope, SGBuilder sgb){
     sgb.use(scope, "<name>", name, {variableId()}, 0);
}

void use((Statement) `<Id var> := <Expression val>`, Tree scope, SGBuilder sgb){
     sgb.use(scope, "<var>", var, {variableId()}, 0);
}

// Requirements and facts for typing

void require(s: (Statement) `<Id var> :=  <Expression val>`, SGBuilder sgb){
     sgb.require("assignment", s, 
                 [ equal(typeof(var), typeof(val), onError(s, "Lhs <var> should have same type as rhs")) ]);
}

void require(s: (Statement) `if <Expression cond> then <{Statement ";"}*  thenPart> else <{Statement ";"}* elsePart> fi` , SGBuilder sgb){
     sgb.require("int_condition", s, 
                 [ equal(typeof(s.cond), intType(), onError(s.cond, "Condition")) ]);
}

void require(s: (Statement) `while <Expression cond> do <{Statement ";"}* body> od` , SGBuilder sgb){
     sgb.require("int_condition", s, 
                 [ equal(typeof(s.cond), intType(), onError(s.cond, "Condition")) ]);
}

void require(e: (Expression) `<Expression lhs> + <Expression rhs>`, SGBuilder sgb){
     sgb.overload("addition", e, 
                  [lhs, rhs], [<[intType(), intType()], intType()>, <[strType(), strType()], strType()>],
                  onError(e, "No version of + exists for given argument types"));
}

void require(e: (Expression) `<Expression lhs> - <Expression rhs>`, SGBuilder sgb){
     sgb.require("subtraction", e, 
                 [ equal(typeof(lhs), intType(), onError(lhs, "Lhs of -")),
                   equal(typeof(rhs), intType(), onError(rhs, "Rhs of -")),
                   fact(e, intType())
                 ]);
}

void require(e: (Expression) `<String string>`, SGBuilder sgb){
    sgb.fact(e, strType());
}

void require(e: (Expression) `<Natural natcon>`, SGBuilder sgb){
    sgb.fact(e, intType());
}


//----------------

set[Message] validatePico() = typecheck(exp1());

set[Message] typecheck(Program p) = validate(extractScopesAndConstraints(p));

public Program exp1() = parse(#Program, |project://TypePal/src/examples/pico/e1.pico|);

public Program exp2() = parse(#Program, |project://TypePal/src/examples/pico/fac.miniml|);