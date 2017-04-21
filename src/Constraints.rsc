module Constraints

import Set; 
import Node;
import Map;
import IO;
import List; 
import ParseTree;
extend ScopeGraph;
extend ExtractScopesAndConstraints;
import Type;
import String;
import Message;

bool cdebug = true;

AType followInBindings(tvar(loc src), map[loc, AType] bindings)
    = followInBindings(src, bindings);

default AType followInBindings(AType tp,  map[loc, AType] bindings) = tp;

AType followInBindings(loc src, map[loc, AType] bindings){
    return isTypeVariable(src) && bindings[src]? ? followInBindings(bindings[src], bindings) 
                                                 :  tvar(src);
}

default AType followInBindings(AType tp,  map[loc, AType] bindings) = tp;

AType followInFacts(tvar(loc tv), map[loc, AType] facts){
    if(facts[tv]?){
       fct = facts[tv];
       if(tvar(loc other) := fct){
          return followInFacts(fct, facts);
       } else {
          return fct;
       }
    }
    return tvar(tv);
}
default AType followInFacts(AType tp, map[loc, AType] facts) = tp;

AType follow(AType atype, map[loc, AType] bindings, map[loc, AType] facts){
    res = follow1(atype, bindings, facts);
    println("follow <atype> ==\> <res>");
    return res;
}

AType follow1(AType atype, map[loc, AType] bindings, map[loc, AType] facts){
    switch(atype){
      case typeof(loc src): {
           atype1 = followInBindings(atype, bindings);
           if(atype1 != atype){
              return atype1;
           }
           return followInFacts(atype, facts);
      }     
      case tv: tvar(loc src): {
           atype1 = followInBindings(atype, bindings);
           if(atype1 != atype){
              return atype1;
           }
           return followInFacts(atype, facts);
      }
      default:
            return atype;
    }
}

AType instantiate(AType atype, map[loc, AType] bindings, map[loc, AType] facts){
   //println("instantiate: <ptype>, <bindings>");
   return
      visit(atype){
        case typeof(loc src): {
            //println("instantiate typeof: <src>, <bindings[src]?>, <facts[src]?>");
            insert follow(atype, bindings, facts); ///*facts[src]? ? */instantiate(facts[src], bindings, facts);// : typeof(src);
        }
        case tv: tvar(loc src): {
            //println("instantiate tv: <tv>, <facts[src]?>");
            insert follow(atype, bindings, facts); //followInBindings(followInFacts(tv, facts), bindings);
        }
      }
}

Requirement instantiate(Requirement req, map[loc, AType] bindings, map[loc, AType] facts)
    = visit(req) { case AType atype => instantiate(atype, bindings, facts) };
    
Fact instantiate(Fact fct, map[loc, AType] bindings, map[loc, AType] facts)
    = visit(fct) { case AType atype => instantiate(atype, bindings, facts) };

set[loc] typevarsOf(AType tp) = { src | /tvar(loc src) := tp };

// Unification, for now, without checks on variables
tuple[bool, map[loc, AType]] unify(AType t1, AType t2, map[loc, AType] bindings){
    //println("unify(<t1>, <t2>, <bindings>)");
    if(t1 == t2) return <true, bindings>;
   
    if(tvar(loc tv1) := t1){
       if(bindings[tv1]?){
          return unify(bindings[tv1], t2, bindings);
       } else {
          return <true, (tv1 : t2) + bindings>;
       }
    }
      
    if(tvar(loc tv2) := t2){
       if(bindings[tv2]?){
         return unify(bindings[tv2], t1, bindings); 
       } else {
        return <true, (tv2 : t1) + bindings>;
      }
    }
   
    c1 = getName(t1); c2 = getName(t2);
    a1 = arity(t1); a2 = arity(t2);
    if(c1 != c2 || a1 != a2) return <false, bindings>;
    
    kids1 = getChildren(t1); kids2 = getChildren(t2);
    for(int i <- [0 .. a1]){
        if(AType k1 := kids1[i], AType k2 := kids2[i]){
            <res, bindings1> = unify(k1, k2, bindings);
            if(!res) return <res, bindings>;
            bindings += bindings1;
        } else {
            throw "Non AType found while unifying: <kids1[i]>, <kids2[i]>";
        }
    }
    return <true, bindings>;
}

set[Message] validate(TENV tenv){
          
   overloads = tenv.overloads;
   facts = tenv.facts;
   set[Fact] openFacts = tenv.openFacts;
   openReqs = tenv.openReqs;
   tvScopes = tenv.tvScopes;
   
   map[Key, Key] defs = ();
   
   rel[loc, Requirement] triggersRequirement = {};
   rel[loc, Requirement] tvtriggersRequirement = {};
   
   rel[loc, Fact] triggersFact = {};
   rel[loc, Fact] tvtriggersFact = {};
   
   set[Use] unresolvedUses = {};
   set[Requirement] requirementJobs = {};
   
   if(cdebug){
      println("overloads:     <size(overloads)>");
      println("facts:         <size(facts)>");
      println("openFacts:     <size(openFacts)>");
      println("openReqs:      <size(openReqs)>");
      printScopeGraph(tenv);
   }
   
   set[Message] messages = {};
   iterations = 0;
   
   void printState(){
    println("facts:");
        for(Key fact <- facts){
            println("\t<fact>: <facts[fact]>");
        }
    println("triggersFact:");
        for(<loc k, f> <- triggersFact){
            println("<k> ===\> <f.src>, <f.tp>");
        }
    println("tvtriggersRequirement:");
        for(<loc k, r> <- tvtriggersRequirement){
            println("<k> ===\> <r.name>, <r.src>");
        }
    println("openFacts:");
       for(Fact fact <- openFacts){
            println("\t<fact>");
        }
    println("openReqs:");
        for(rq <- openReqs){
            println("\t<rq.name> at <rq.src>:");
            for(tp <- rq.dependsOn){
                println("\t  dependsOn: <tp>");
            }
            for(tp <- rq.dependsOnTV){
                println("\t  dependsOnTV: <tp>");
            }
            println("\t  preds:");
            for(pred <- rq.preds) println("\t    <pred>");
        }
   }
   
   void addFact(loc l, AType tp){
         if(cdebug)println("addFact: <l>, <tp>, <triggersFact[l]>, <triggersRequirement[l]>");
        
         //if(facts[l]? && facts[l] != tp){
         //   for(fkey <- facts){
         //       println("<fkey>: <facts[fkey]>");
         //   }
         //   throw "Overwrite facts[<l>]: old <facts[l]>, new <tp>";
         //}
         if(typeof(loc other) := tp){// || tvar(loc other) := tp){
            if(facts[other]?){
               if(cdebug)println("add: facts[<l>] = <facts[other]>");
               facts[l] = facts[other];
            } else {
               fct = openFact({other}, {}, l, tp);
               if(cdebug)println("add: <fct>");
               openFacts += fct;
               triggersFact += <other, fct>;
            }
         } else {
            if(cdebug)println("add: facts[<l>] = <tp>");
            facts[l] = tp;
         }
         
         for(req <- triggersRequirement[l]){
             if(allDependenciesKnown(req.dependsOn, req.dependsOnTV, facts)){
               requirementJobs += req;
               if(cdebug)println("adding requirementJob: <req.name>, <req.src>");
             }
         }
         
         for(fct <- triggersFact[l]){
             if(allDependenciesKnown(fct.dependsOn, fct.dependsOnTV, facts)){
                addFact(fct.src, instantiate(fct.tp, (), facts));
                openFacts -= fct;
             }
          }
   }
   
    tuple[bool ok, set[Message] messages, map[loc, AType] bindings] 
        satisfies(Requirement req, map[loc, loc] tvScopes){
        preds = req.preds;
        req_messages = {};
        bindings = ();
        for(pred <- preds){
            <ok, bindings1, messages1> = satisfies1(pred, bindings);
            if(cdebug){
               println("*** <pred>");
               println("ok: <ok>, messages: <messages1>");
               if(!isEmpty(bindings1)) println("bindings: <bindings1>");
            }
            
            if(!ok){
               return <false, messages + messages1, ()>;
            }
            req_messages += messages1;
            bindings += bindings1;
            for(b <- bindings1){
                if(cdebug && !facts[b]? && tvScopes[b]?) println("Consider <b>, <bindings[b]>, <isGlobalTypeVar(b)>, <!facts[b]?>, <req.src>, <tvScopes[b]>, <req.src <= tvScopes[b]>");
                if(isGlobalTypeVar(b) && !facts[b]? && (req.src <= tvScopes[b])){
                   addFact(b, bindings1[b]);
                   if(cdebug) println("Adding type var: <b> : <bindings1[b]>");
                }
            }
        }
        
        return <true, req_messages, bindings>;
    }

    tuple[bool ok, map[loc, AType] bindings, set[Message] messages] 
        satisfies1(match(AType pattern, AType subject, ErrorHandler onError), map[loc, AType] bindings){
         if(cdebug)println("match: <pattern>, <subject>, <bindings>");
         pname = getName(pattern);
         pargs = getChildren(pattern);
         
         subject = instantiate(subject, bindings, facts);     
         sname = getName(subject);
         sargs = getChildren(subject);
     
         if(pname != sname || size(pargs) != size(sargs)){
            println("match fail 1");
            return <false, (), {error("<onError.msg>, found <subject>", onError.where)}>;
         }
         bindings = ();
         for(int i <- index(pargs)){
            if(tvar(loc l) := pargs[i] && AType tp := sargs[i]){
                bindings[l] = tp;
            } else {
              throw "Cannot match <pargs[i]> and <sargs[i]>";
            }
         }
         //println("match returns: true, <bindings>");
         return <true, bindings, {}>;
    }
    
    tuple[bool ok, map[loc, AType] bindings, set[Message] messages] 
        satisfies1(equal(AType given, AType expected, ErrorHandler onError), map[loc, AType] bindings){
        //println("equal: <given>, <expected>");
        igiven = instantiate(given, bindings, facts);
        iexpected = instantiate(expected, bindings, facts);
        <ok, bindings1> = unify(igiven, iexpected, bindings);
        return ok ? <true, bindings1, {}> 
                  : <false, bindings, {error("<onError.msg>, expected <AType2String(iexpected)>, found <AType2String(igiven)>", onError.where)}>;
    }
    
    tuple[bool ok, map[loc, AType] bindings, set[Message] messages] 
        satisfies1(fact(loc l, AType tp), map[loc, AType] bindings){
        addFact(l, instantiate(tp, bindings, facts));
        return <true, (), {}>;
    }
    
   //println("Given facts:");
   //for(fkey <- facts){
   //  println("\t<fkey>: <facts[fkey]>");
   //}
   for(Fact f <- openFacts){
       if(allDependenciesKnown(f.dependsOn, f.dependsOnTV, facts)){
          addFact(f.src, instantiate(f.tp, (), facts));
          openFacts -= f;
       } else {
           for(dep <- f.dependsOn){
               if(cdebug)println("add: <dep>");
               triggersFact += <dep, f>;
           }
           for(tvdep <- f.dependsOnTV){
               tvtriggersFact += <tvdep, f>;
           }
       }
   } 
    
    for(Define d <- tenv.defines){
       addFact(d.defined, d.defInfo.tp);
    }
    
  
    for(oreq <- openReqs){
       for(dep <- oreq.dependsOn){
           triggersRequirement += {<dep, oreq>};
       }
       for(tvdep <- oreq.dependsOnTV){
           tvtriggersRequirement += {<tvdep, oreq>};
       }
    }

    for(oreq <- openReqs){
        if(allDependenciesKnown(oreq.dependsOn, oreq.dependsOnTV, facts)){
           requirementJobs += oreq;
        }
    }
    
    for(u <- tenv.uses){
        try {
           def = lookup(tenv, u.scope, u);
           defs[u.occ] = def;
           unresolvedUses += u;
        } catch noKey: {
            messages += error("Undefined variable <u.id>", u.occ);
        }
    }
   
    solve(facts, openReqs, openFacts, unresolvedUses, requirementJobs){
    
    //while(!(isEmpty(openFacts) && isEmpty(openReqs)) && iterations < 10){
       iterations += 1;
       
       if(cdebug){
          println("======================== iteration <iterations>");
          printState();
       }
       
       for(u <- unresolvedUses){
           if(cdebug)println("Consider use: <u>");
           def = defs[u.occ];
           if(facts[def]?){  // has type of def become available?
              fct1 = facts[def];
              <deps, tvdeps> = extractTypeDependencies(fct1);
              if(cdebug)println("<fct1>, <deps>, <tvdeps>");
              if(allDependenciesKnown(deps, tvdeps, facts)){ 
                 addFact(u.occ, instantiate(fct1, (), facts));
                 unresolvedUses -= {u};
              }
           }
      }
       
       // eliminate overloads for which argument types are known
       eliminate_overloads:
       for(ovl <- tenv.overloads){
          args = tenv.overloads[ovl].args;
          if(all(p <- args, facts[p]?)){
              for(<argTypes, resType> <- tenv.overloads[ovl].alternatives){
                  if(all(int i <- index(argTypes), argTypes[i] == facts[args[i]])){
                     addFact(ovl, resType);
                     overloads = delete(overloads, ovl);
                     continue eliminate_overloads;
                  }
              }
          }
       }  
       
       // Check open requirements when their predicate can be fully instantiated
       for(oreq <- requirementJobs){
          if(cdebug)println("\nchecking: <oreq.name>, <oreq.src>");
          if(allDependenciesKnown(oreq.dependsOn, oreq.dependsOnTV, facts)){          
             <ok, messages1, bindings1> = satisfies(oreq, tvScopes); 
             if(cdebug)println("<ok>, <messages1>, <bindings1>");
             messages += messages1;
             if(ok){
                if(cdebug)println("reqs: bindings: <bindings1>");
                tvars = domain(bindings1);
                treqs = tvtriggersRequirement[tvars];
                tfacts = triggersFact[tvars];
                for(r <- treqs){
                    if(cdebug)println("reqs, adding bound requirement: <instantiate(r, bindings1, facts)>");
                    breq = instantiate(r, bindings1, facts);
                    requirementJobs += { breq };
                }
                for(f <- tfacts){
                    if(cdebug)println("reqs, adding bound fact: <instantiate(f, bindings1, facts)>");
                    fct = instantiate(f, bindings1, facts);
                    addFact(f.src, fct.tp) ;
                }
                
             } else {
               if(cdebug)println("!ok: <messages1>");
               if(cdebug)println("deleting: <oreq.name>, <oreq.src>");
                  openReqs -= oreq;
             }
          }
      }
   }   
   
   if(size(overloads) > 0){
      for(l <- overloads){
          ovl = overloads[l];
          args = overloads[l].args;
          messages += error("<ovl.onError.msg> <for(int i <- index(args)){><facts[args[i]]? ? AType2String(facts[args[i]]) : "unknown"><i < size(args)-1 ? "," : ""> <}>", ovl.onError.where );
      }
   }
   if(cdebug){
       println("------");
       println("iterations: <iterations>");
       println("overloads:  <size(overloads)>");
       println("facts:      <size(facts)>");
       println("openFacts:  <size(openFacts)>");
       println("openReqs:   <size(openReqs)>");
       
       printState();
       
       println("------");
       if(isEmpty(messages) && isEmpty(openReqs) && isEmpty(openFacts)){
          println("No type errors found");
       } else {
          println("Errors:");
          for(msg <- messages){
              println(msg);
          }
          if(!isEmpty(openReqs)) println("*** <size(openReqs)> unresolved requirements ***");
          if(!isEmpty(openFacts)) println("*** <size(openFacts)> open facts ***");
       }
   }
   return messages;
}

