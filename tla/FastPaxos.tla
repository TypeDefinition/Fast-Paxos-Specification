--------------------------- MODULE FastPaxos -----------------------------
EXTENDS TLC, Naturals, FiniteSets, Integers

\*INSTANCE Paxos

MaxValue(A) == CHOOSE a \in A: \A b \in A: b <= a

(*
As there is only one coordinator thereofore,
Explicitly specify the name of the coordinator.
We are here also considering that the only coordinator is also the leader.
*)
CONSTANT Replicas, Coordinator
CONSTANT None, Any, Values
CONSTANT Ballots, Quorums(_), FaultTolerance
CONSTANT FastRoundNumber        \* Set of Fast Rounds.

\* round of participation for an acceptor. 0 means has not participated in any round
VARIABLE rounds

(*
Highest numbered round in which an acceptor has casted a vote.
Initially 0.
valueRound <= round, as acceptor can participate in rounds after casting vote.
*)
VARIABLE valueRounds

(* 
Value for which an acceptor casted a vote.
*)
VARIABLE values

(*
Highest numbered round a coordinator has begun.
*)
VARIABLE coordinatorRound

(*
This value is either none, if coordinator has not picked any value,
or is equal to the value picked by the coordinator in round coordinatorRound.
*)
VARIABLE coordinatorValue
VARIABLE messages
VARIABLE proposedValue
VARIABLE learnedValue
VARIABLE goodSet

RoundNumber == Nat \ {0}        \* set of positive round numbers

ASSUME IsFiniteSet(Replicas) \* Set of Replicas should be a Finite set.
ASSUME Coordinator \in Replicas \* Assumption related to coordinator that it should be a member of Replicas set.
ASSUME FastRoundNumber \subseteq RoundNumber


ASSUME \A i \in RoundNumber:
            /\ Quorums(i) \subseteq SUBSET Replicas
            /\ \A j \in RoundNumber:
                /\ \A q1 \in Quorums(i), q2 \in Quorums(j): q1 \intersect q2 # {}
                /\ (j \in FastRoundNumber) => 
                    \A q \in Quorums(i): \A q3,q4 \in Quorums(j): q \intersect q3 \intersect q4 #{}

(* All round numbers which are not fast rounds will be classic rounds*)
ClassicRoundRoundNumber == RoundNumber \ FastRoundNumber

P1aMessage == [type : {"P1a"},
               round : RoundNumber]                       \* round is in set round.

P1bMessage == [type : {"P1b"},
               round : RoundNumber,                       \* round is in set round.
               valueRound: RoundNumber \union {0},        \* round in which value is chosen
               acceptor : Replicas,                    \* Acceptor is in set Replicas.
               value: Values \union {Any}]

P2aMessage == [type : {"P2a"},
               round : RoundNumber,                       \* round value is in set round.
               value : Values]                         \* Value is in set Values.

P2bMessage == [type : {"P2b"},
               round : RoundNumber,                       \* round is in set round.
               acceptor : Replicas,                    \* Acceptor is in set Replicas.
               value : Values]                         \* Value is in set Values.

P3Message == [type : {"P3"},
              round : RoundNumber,                        \* round value is in set round.
              value : Values]                          \* Value is in set Values.

\* Message is the union of P1aMessage, P1bMessage, P2aMessage, P2bMessage and P3Message.
Message == P1aMessage \union P1bMessage \union P2aMessage \union P2bMessage \union P3Message

\* grouping all the variables together.
\* group of variables related to acceptor.
AcceptorVariables == <<rounds,valueRounds,values>>

\* group of variables related to coordinator.
CoordinatorVariables == <<coordinatorRound,coordinatorValue>>

\* group of all other variables
OtherVariables == <<proposedValue,learnedValue,goodSet>>

\* group containing all variables.
AllVarialbes == <<AcceptorVariables,CoordinatorVariables,OtherVariables,messages>>

\* Invariant for all the variables declared.
FastPaxosTypeOK == /\ rounds \in [Replicas -> Nat]
                   /\ valueRounds \in [Replicas -> Nat]
                   /\ values \in [Replicas -> Values \union {Any}]
                   /\ coordinatorRound \in  Nat
                   /\ coordinatorValue \in Values \union {Any, None}
                   /\ messages \in SUBSET Message
                   /\ proposedValue \in SUBSET  Values
                   /\ learnedValue \in SUBSET Values
                   /\ goodSet \subseteq Replicas

FastPaxosInit == /\ rounds = [Replicas |-> 0]
                 /\ valueRounds = [Replicas |-> 0]
                 /\ values = [Replicas |-> Any]
                 /\ rounds = [Replicas |-> 0]
                 /\ coordinatorRound = 0
                 /\ coordinatorValue = None
                 /\ messages = {}
                 /\ proposedValue = {}
                 /\ learnedValue = {}
                 /\ goodSet \in SUBSET Replicas

SendMessage(m) == messages' = messages \union {m}

(*Actions Taken by Coordinator*)

\* Implementing Phase 1a for round i
FastPaxosPrepare(i) == /\ coordinatorRound < i          \* coordinator's round number is less than the current round number i.
                       /\ \/ coordinatorRound = 0       \* if coordinator has not participated in any of the rounds yet.
                          \/ \E msg \in messages : /\ coordinatorRound < msg.round
                                                   /\ msg.round < i
                          \/ /\ coordinatorRound \in FastRoundNumber        \* coordinator previouslt participated in a fast round.
                             /\ i \in ClassicRoundRoundNumber               \* but the current round is a classic round.
                       /\ coordinatorRound' = i
                       /\ coordinatorValue = None
                       /\ SendMessage([type |-> "P1a",round |-> i])
                       /\ UNCHANGED <<AcceptorVariables,OtherVariables>>

\* returns the set of all the messages for a particular phase and round and from acceptors of a particular quorum
FilterMessagesForQuorumRoundAndPhase(quorum,round,phase) == {m \in messages : (m.type = phase) /\ (m.round = round) /\ (m.acceptor \in quorum)}

\* msgs are p1b messages sent in the round by all the acceptors of quorum.
IsValueInQuorum(quorum,round,msgs,val) == LET AcceptorRound(a) == (CHOOSE msg \in msgs : msg.acceptor = a).round        \*extract the round number in which acceptor sent the msg.
                                              AcceptorValue(a) == (CHOOSE msg \in msgs : msg.acceptor = a).value        \*extract the value for which acceptor sent the msg.
                                              HighestRound == MaxValue({AcceptorRound(acceptor):acceptor \in quorum})         \*extract hightest round number in which the acceptors in quorum send p1b msg.
                                              HighestRoundValue == {AcceptorValue(acceptor) : acceptor \in {qAcceptor \in quorum: AcceptorRound(qAcceptor) = HighestRound}}
                                              IsValueChosen(val_) == \E quorum_ \in Quorums(HighestRound) :
                                                                        \A a \in quorum \intersect quorum_ :
                                                                            (AcceptorRound(a) = HighestRound) /\ (AcceptorValue(a) = val_)
                                          IN IF HighestRound = 0 THEN \/ val \in proposedValue
                                                                      \/ /\ round \in FastRoundNumber
                                                                         /\ val = Any
                                                                 ELSE IF Cardinality(HighestRoundValue) = 1
                                                                      THEN val \in HighestRoundValue
                                                                      ELSE IF \E val_ \in HighestRoundValue: IsValueChosen(val_)
                                                                           THEN val = CHOOSE val_ \in HighestRoundValue: IsValueChosen(val_)
                                                                           ELSE val \in proposedValue

\* Implementing phase 2a for a value.
FastPaxosAccept(value) == /\ coordinatorRound # 0
                          /\ coordinatorValue # None
                          /\ \E quorum \in Quorum(coordinatorRound):
                                /\ \A r \in quorum: \E msg \in FilterMessagesForQuorumRoundAndPhase(quorum,coordinatorRound,"P1b"): msg.acceptor = r
                                /\ IsValueInQuorum(quorum, coordinatorRound, FilterMessagesForQuorumRoundAndPhase(quorum,coordinatorRound,"P1b"),value)
                          /\ coordinatorValue' = value
                          /\ SendMessage([type |-> "P2a",round |-> coordinatorRound, value |-> value])
                          /\ UNCHANGED <coordinatorRound, AcceptorVariables,OtherVariables>

\* P2b => P1b
P1bImpliedByP2b(quorum, round) == {[type |-> "P1b",round |-> round+1, valueRound |-> round,
                                        value |-> msg.value, acceptor |-> msg.acceptor] : msg \in FilterMessagesForQuorumRoundAndPhase(quorum,round,"P2b")}


RecoverFromCollision(value) == /\ coordinatorValue = Any
                               /\ \E quorum \in Quorum(coordinatorRound+1):
                                    /\ \A r \in quorum: \E msg \in P1bImpliedByP2b(quorum,coordinatorRound): msg.acceptor=r
                                    /\ IsValueInQuorum(quorum, coordinatorRound+1, P1bImpliedByP2b(quorum,coordinatorRound),value)
                               /\ coordinatorValue' = value
                               /\ coordinatorRound' = coordinatorRound+!
                               /\ SendMessage([type |-> "P2a", round|-> coordinatorRound+1,value |-> value])
                               /\ UNCHANGED <AcceptorVariables,OtherVariables>

LastMessageOfCoordinator == IF coordinatorValue = None
                            THEN [type |-> "P1a", round |-> coordinatorRound]
                            ELSE [type |-> "P2a", round |-> coordinatorRound, value |-> coordinatorValue]


RetransmitLastMessageOfCoordinator == /\ coordinatorRound # 0
                                      /\ SendMessage(LastMessageOfCoordinator)
                                      /\ UNCHANGED <AcceptorVariables,CoordinatorVariables,OtherVariables>

FastPaxosCoordinatorNext == \/ \E round \in RoundNumber: FastPaxosPrepare(round)        \* Implementing Phase 1a of Coordinator
                            \/ \E value \in Values \union {Any}: FastPaxosAccept(value)
                            \/ \E value \in Values RecoverFromCollision(value)
                            \/ RetransmitLastMessageOfCoordinator


(* Actions Taken by Acceptor*)


FastPaxosSpec == /\ FastPaxosInit

===============================================================