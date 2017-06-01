module dtfun::DTFun

// Functional language with declared types

extend ExtractScopesAndConstraints;
extend Constraints;
extend TestFramework;

// ----  DTFun syntax ------------------------------------

lexical Id  = ([a-z][a-z0-9]* !>> [a-z0-9]) \ Reserved;
lexical Integer = [0-9]+ !>> [0-9]; 
lexical Boolean = "true" | "false";

keyword Reserved = "true" | "false" | "if" | "then" | "else" | "fi" | "let" | "in" | "fun" | "end";

layout Layout = WhitespaceAndComment* !>> [\ \t\n\r%];

lexical WhitespaceAndComment 
   = [\ \t\n\r]
   | @category="Comment" ws2:
    "%" ![%]+ "%"
   | @category="Comment" ws3: "{" ![\n}]*  "}"$
   ;

syntax Type 
   = "int" 
   | "bool"
   | Type from "-\>" Type to
   ; 
   
start syntax Expression 
   = 
     Id name
   | Integer intcon 
   | Boolean boolcon
   | bracket "(" Expression e ")"                   
   > left ( Expression lhs "+" Expression rhs                                          
          | Expression lhs "&&" Expression rhs  
          )
   | "fun" Id name ":" Type tp "{" Expression exp "}"
   | Expression exp1 "(" Expression exp2  ")"
   | "let" Id name ":" Type tp "=" Expression exp1 "in" Expression exp2 "end"
   | "if" Expression cond "then" Expression thenPart "else" Expression elsePart "fi" 
   ;

// ----  IdRoles, PathLabels and AType ------------------- 

data IdRole
    = variableId()
    ;

data AType   
    = intType()                                     // int type
    | boolType()                                    // bool type
    | functionType(AType from, AType to)            // function type
    ; 

AType transType((Type) `int`) = intType();
AType transType((Type) `bool`) = boolType(); 
AType transType((Type) `<Type from> -\> <Type to>`) = functionType(transType(from), transType(to)); 

str AType2String(intType()) = "int";
str AType2String(boolType()) = "bool";
str AType2String(functionType(AType from, AType to)) = "fun <AType2String(from)> -\> <AType2String(to)>";

// ----  Define --------------------------------------------------------

Tree define(e: (Expression) `fun <Id name> : <Type tp> { <Expression body> }`, Tree scope, SGBuilder sgb) {   
    sgb.define(e, "<name>", variableId(), name, defInfo(transType(tp)));
    sgb.fact(e, [body], [], AType(){ return functionType(transType(tp), typeof(body)); });
    return e;
}

Tree define(e: (Expression) `let <Id name> : <Type tp> = <Expression exp1> in <Expression exp2> end`, Tree scope, SGBuilder sgb) {  
    sgb.define(e, "<name>", variableId(), name, defInfo(transType(tp)));
    sgb.fact(e, [exp2], [], AType() { return typeof(exp2); } );
    return exp2;  
}

// ----  Collect uses & requirements ------------------------------------

 
void collect(e: (Expression) `<Id name>`, Tree scope, SGBuilder sgb){
    sgb.use(scope, name, {variableId()}, 0);
}

void collect(e: (Expression) `<Expression exp1> (<Expression exp2>)`, Tree scope, SGBuilder sgb) { 
    sgb.require("application", e, [exp1, exp2],
                () {  if(functionType(tau1, tau2) := typeof(exp1)){
                        equal(typeof(exp2), tau1, onError(exp2, "Incorrect type of actual parameter"));
                        fact(e, tau2);
                      } else {
                          reportError(exp1, "Function type expected");
                      }
                    });
}

void collect(e: (Expression) `if <Expression cond> then <Expression thenPart> else <Expression elsePart> fi`, Tree scope, SGBuilder sgb){
    sgb.require("if", e, [cond, thenPart, elsePart],
                () { equal(typeof(cond), boolType(), onError(cond, "Condition"));
                     equal(typeof(thenPart), typeof(elsePart), onError(e, "thenPart and elsePart should have same type"));
                     fact(e, typeof(thenPart));
                   }); 
}

void collect(e: (Expression) `<Expression lhs> + <Expression rhs>`, Tree scope, SGBuilder sgb){
     sgb.require("addition", e, [lhs, rhs],
                 () { equal(typeof(lhs), intType(), onError(lhs, "Lhs of +"));
                      equal(typeof(rhs), intType(), onError(rhs, "Rhs of +"));
                      fact(e, intType());
                    });
} 

void collect(e: (Expression) `<Expression lhs> && <Expression rhs>`, Tree scope, SGBuilder sgb){
     sgb.require("and", e, [lhs, rhs],
                 () { equal(typeof(lhs), boolType(), onError(lhs, "Lhs of &&"));
                      equal(typeof(rhs), boolType(), onError(rhs, "Rhs of &&"));
                      fact(e, intType());
                    });
} 

void collect(e :(Expression) `( <Expression exp> )`, Tree scope, SGBuilder sgb){
     sgb.fact(e, [exp], [], AType(){ return typeof(exp); });
}

void collect(e: (Expression) `<Boolean boolcon>`, Tree scope, SGBuilder sgb){
     sgb.atomicFact(e, boolType());
}

void collect(e: (Expression) `<Integer intcon>`, Tree scope, SGBuilder sgb){
     sgb.atomicFact(e, intType());
}

// ----  Examples & Tests --------------------------------

private Expression sample(str name) = parse(#Expression, |project://TypePal/src/dtfun/<name>.dt|);

set[Message] validateDT(str name) =
    validate(extractScopesAndConstraints(sample(name), scopeGraphBuilder()));

void testDT() {
    runTests(|project://TypePal/src/dtfun/tests.ttl|, #Expression);
}