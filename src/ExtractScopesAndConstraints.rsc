module ExtractScopesAndConstraints

import Node;
import ParseTree;
import String;
extend ScopeGraph;

data DefInfo
    = defInfo(AType atype)
    ;
    
data AType
    = typeof(loc src)                                          // type of source code fragment
    | typeof(loc base, loc src, str id, set[IdRole] idRoles)   // type of source code fragment in base type  
    | tvar(loc name)                                           // type variable
    | useType(Use use)                                         // Use a defined type
    | listType(list[AType] atypes)
    ;

str AType2String(typeof(loc src)) = "typeof(<src>)";
str AType2String(typeof(loc scope, loc src, str id, set[IdRole] idRoles)) = "typeof(<scope>, <src>, <id>, <idRoles>)";
str AType2String(tvar(loc name))    = "<name>";
str AType2String(useType(Use use)) = "<use.id>";
str AType2String(listType(list[AType] atypes)) = size(atypes) == 0 ? "empty list of types" : intercalate(", ", [AType2String(a) | a <- atypes]);

default str AType2String(AType tp) = "<tp>";

// Convenience function to avoid the need to fetch source location
//AType typeof(Tree tree) = typeof(tree@\loc);
AType typeof(Tree scope, Tree tree, set[IdRole] idRoles) = typeof(scope@\loc, tree@\loc, "<tree>", idRoles);

list[AType] typeof(list[Tree] trees) = [typeof(tree@\loc) | Tree tree <- trees];

data ErrorHandler
    = onError(loc where, str msg)
    ;
   
ErrorHandler onError(Tree t, str msg) = onError(t@\loc, msg);

data Fact
    = openFact(set[loc] dependsOn, set[loc] dependsOnTV, loc src, AType() makeType)
    ;

data Requirement
    = //require(str name, loc src, void() preds)
      openReq(str name, set[loc] dependsOn, set[loc] dependsOnTV, loc src, void() preds)
    ;
     
data Overload
    = overload(str name, loc src, list[loc] args, AType() resolve)
    ;

void reportError(Tree t, str msg){
    throw error(msg, t@\loc);
}

bool isTypeVariable(loc tv) = tv.scheme == "typevar"; 

int maxLocalTypeVars = 100;
loc localTypeVars = |typevar:///0000000100|;

bool isLocalTypeVar(loc tv) = tv.scheme == "typevar" && tv < localTypeVars;

bool isGlobalTypeVar(loc tv) = tv.scheme == "typevar" && tv >= localTypeVars;

bool isTypeofOrTVar(tvar(loc src)) = true;
bool isTypeofOrTVar(typeof(loc src)) = true;
bool isTypeofOrTVar(typeof(loc scope, loc src, str id, set[IdRole] idRoles)) = true;
default bool isTypeofOrTVar(AType atype) = false;

//tuple[set[loc] deps, set[loc] typeVars] extractTypeDependencies(typeof(loc l)) = <{}, {}>;
//tuple[set[loc] deps, set[loc] typeVars] extractTypeDependencies(tvar(loc l)) = <{}, {}>;
tuple[set[loc] deps, set[loc] typeVars] extractTypeDependencies(AType tp) 
    = <{ src | /typeof(loc src) := tp } + { scope /*, src*/ | /typeof(loc scope, loc src, str id, set[IdRole] idRoles) := tp },  
       { src | /tvar(loc src) := tp, isGlobalTypeVar(src) }
      >;

bool allDependenciesKnown(set[loc] deps, set[loc] tvdeps, map[loc,AType] facts)
    = (isEmpty(deps) || all(dep <- deps, facts[dep]?)) && (isEmpty(tvdeps) || all(tvdep <- tvdeps, facts[tvdep]?));

data ScopeGraph (
        map[loc,Overload] overloads = (),
        map[loc,AType] facts = (), 
        set[Fact] openFacts = {},
        set[Requirement] openReqs = {},
        map[loc,loc] tvScopes = ()
        );

alias REQUIREMENTS = ScopeGraph;

alias Key = loc;

default Tree define(Tree tree, Tree scope, SGBuilder sgb) {
   //println("Default define <tree>");
   return scope;
}

default void collect(Tree tree, Tree scope, SGBuilder sgb) { 
    //println("Default collect <tree>");
}

ScopeGraph extractScopesAndConstraints(Tree root, SGBuilder sgb){
    extract2(root, root, sgb);
    sg = sgb.build();
    if(debug) printScopeGraph(sg);
    int n = 0;
    while(!isEmpty(sg.referPaths) && n < 3){    // explain this iteration count
        n += 1;
        for(c <- sg.referPaths){
            try {
                def = lookup(sg, c.use);
                if(debug) println("extract1: resolve <c.use> to <def>");
                sg.paths += {<c.use.scope, c.pathLabel, def>};
                sg.referPaths -= {c}; 
            }
            catch:; 
        }
    }
    if(!isEmpty(sg.referPaths)){
        println("Could not solve path contributions");
    }
    return sg;
}

void extract2(currentTree: appl(Production prod, list[Tree] args), Tree currentScope, SGBuilder sgb){
   newScope = define(currentTree, currentScope, sgb);
   sgb.addScope(newScope, currentScope);
   collect(currentTree, newScope, sgb);
   bool nonLayout = true;
   for(Tree arg <- args){
       if(nonLayout && !(arg is char))
          extract2(arg, newScope, sgb);
       nonLayout = !nonLayout;
   }
}

default void extract2(Tree root, Tree currentScope, SGBuilder sgb) {
    //println("default extract2: <getName(root)>");
}

data SGBuilder 
    = sgbuilder(
        void (Tree scope, Idn id, IdRole idRole, Tree root, DefInfo info) define,
        void (Tree scope, Tree occ, set[IdRole] idRoles, int defLine) use,
        void (Tree scope, Tree occ, set[IdRole] idRoles, PathLabel pathLabel, int defLine) use_ref,
        void (Tree scope, list[Idn] ids, Tree occ, set[IdRole] idRoles, set[IdRole] qualifierRoles, int defLine) use_qual,
        void (Tree scope, list[Idn] ids, Tree occ, set[IdRole] idRoles, set[IdRole] qualifierRoles, PathLabel pathLabel, int defLine) use_qual_ref,   
        void (Tree inner, Tree outer) addScope,
       
        void (str name, Tree src, list[Tree] dependencies, void() preds) require,
        void (Tree src, AType tp) atomicFact,
        void (Tree src, list[Tree] dependencies, list[AType] typeVars, AType() makeType) fact,
        void (str name, Tree src, list[Tree] args, AType() resolver) overload,
        void (Tree src, str msg) error,
        AType (Tree scope) newTypeVar,
        ScopeGraph () build
      ); 
                           
SGBuilder scopeGraphBuilder(){
        
    Defines defines = {};
    Scopes scopes = ();
    Paths paths = {};
    ReferPaths referPaths = {};
    Uses uses = [];
    
    overloads = ();
    facts = ();
    openFacts = {};
    reqs = {};
    binds = ();
    openReqs = {};
    ntypevar = maxLocalTypeVars - 1;
    tvScopes = ();
    
    void _define(Tree scope, Idn id, IdRole idRole, Tree d, DefInfo info){
        defines += {<scope@\loc, id, idRole, d@\loc, info>};
    }
       
    void _use(Tree scope, Tree occ, set[IdRole] idRoles, int defLine) {
        uses += [use("<occ>", occ@\loc, scope@\loc, idRoles, defLine=defLine)];
    }
    
    void _use_ref(Tree scope, Tree occ, set[IdRole] idRoles, PathLabel pathLabel, int defLine) {
        u = use("<occ>", occ@\loc, scope@\loc, idRoles, defLine=defLine);
        uses += [u];
        referPaths += {refer(u, pathLabel)};
    }
    
    void _use_qual(Tree scope, list[Idn] ids, Tree occ, set[IdRole] idRoles, set[IdRole] qualifierRoles, int defLine){
        uses += [usen(ids, occ@\loc, scope@\loc, idRoles, qualifierRoles, defLine=defLine)];
    }
     void _use_qual_ref(Tree scope, list[Idn] ids, Tree occ, set[IdRole] idRoles, set[IdRole] qualifierRoles, PathLabel pathLabel, int defLine){
        u = usen(ids, occ@\loc, scope@\loc, idRoles, qualifierRoles, defLine=defLine);
        uses += [u];
        referPaths += {refer(u, pathLabel)};
    }
    
    void _addScope(Tree inner, Tree outer) { if(inner@\loc != outer@\loc) scopes[inner@\loc] = outer@\loc; }
     
    void _require(str name, Tree src, list[Tree] dependencies, void() preds){        
        deps = {d@\loc | d <- dependencies};
        tvdeps = {};
        
        //if(isEmpty(deps + tvdeps)){
        //   reqs += { require(name, src@\loc, preds) };
        //} else {
           openReqs += { openReq(name, deps, tvdeps, src@\loc, preds) };
        //}
    } 
    
    void _fact1(Tree tree, AType tp){
        <deps, tvdeps> = extractTypeDependencies(tp);
        //println("_fact: <tree@\loc>, <tp>, <typeof(loc other) := tp>, <deps>, <tvdeps>");
        //openFacts += { openFact(deps, tvdeps, tree@\loc, AType() { return tp; }) };
        if(typeof(loc src) := tp){
           //println("add: <openFact({src}, {}, tree@\loc, tp)>");
           if(src != tree@\loc)
              openFacts += { openFact({src}, {}, tree@\loc, AType() { return tp; }) };
        } else if(typeof(loc scope, loc src, str id, set[IdRole] idRoles) := tp){
           if(src != tree@\loc){
              println("_fact add: <openFact({scope}, {}, tree@\loc, AType() { return tp; })>");
              openFacts += { openFact({scope /*, src */}, {}, tree@\loc, AType() { return tp; } ) };
           }
        } else if(tvar(loc tv) := tp){
           openFacts += { openFact({}, {tv}, tree@\loc, AType() { return tp; }) };
        } else if(isEmpty(deps)){
           //println("add facts[<tree@\loc>] = <tp>");
           facts[tree@\loc] = tp;
        } else {
           openFacts += { openFact(deps, tvdeps, tree@\loc, AType() { return tp; }) };
        }
    }
    
    void _fact2(Tree tree, list[Tree] dependencies, list[AType] typeVars, AType() makeType){
        deps = { d@\loc | d <- dependencies };
        tvs  = { l | tvar(l) <- typeVars };
        openFacts += { openFact(deps, tvs, tree@\loc, makeType) };
    }
    
    void _overload(str name, Tree src, list[Tree] args, AType() resolver){
        overloads[src@\loc] = overload(name, src@\loc, [arg@\loc | arg <- args], resolver);
    }
    
    void _error(Tree src, str msg){
        openReqs += { openReq("", {}, {}, src@\loc, (){ reportError(src, msg); }) };
    }
    
    AType _newTypeVar(Tree scope){
        ntypevar +=1;
        s = right("<ntypevar>", 10, "0");
        tv = |typevar:///<s>|;
        tvScopes[tv] = scope@\loc;
        return tvar(tv);
    }
    
    REQUIREMENTS _build(){
       sg = scopeGraph();
       sg.defines = defines;
       sg.scopes = scopes;
       sg.paths = paths;
       sg.referPaths = referPaths;
       sg.uses = uses;
       
       sg.overloads = overloads;
       sg.facts = facts;
       sg.openFacts = openFacts;
       sg.openReqs = openReqs;
       sg.tvScopes = tvScopes;
       return sg; 
    }
    
    return sgbuilder(_define, _use, _use_ref, _use_qual, _use_qual_ref, _addScope, _require, _fact1, _fact2, _overload, _error, _newTypeVar, _build); 
}