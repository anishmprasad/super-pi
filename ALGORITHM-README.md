Distributed Algorithm is a algorithm that runs on a distributed system. Distributed system is a collection of independent computers that do not share their memory. Each processor has its own memory and they communicate via communication networks. Communication in networks is implemented in a process on one machine communicating with a process on other machine. Many algorithms used in distributed system require a coordinator that performs functions needed by other processes in the system. Election algorithms are designed to choose a coordinator.

Election Algorithms:
Election algorithms choose a process from group of processors to act as a coordinator. If the coordinator process crashes due to some reasons, then a new coordinator is elected on other processor. Election algorithm basically determines where a new copy of coordinator should be restarted.

Election algorithm assumes that every active process in the system has a unique priority number. The process with highest priority will be chosen as a new coordinator. Hence, when a coordinator fails, this algorithm elects that active process which has highest priority number.Then this number is send to every active process in the distributed system.

We have two election algorithms for two different configurations of distributed system.


1. The Bully Algorithm –
This algorithm applies to system where every process can send a message to every other process in the system.

Algorithm – Suppose process P sends a message to the coordinator.

If coordinator does not respond to it within a time interval T, then it is assumed that coordinator has failed.
Now process P sends election message to every process with high priority number.
It waits for responses, if no one responds for time interval T then process P elects itself as a coordinator.
Then it sends a message to all lower priority number processes that it is elected as their new coordinator.
However, if an answer is received within time T from any other process Q,
(I) Process P again waits for time interval T’ to receive another message from Q that it has been elected as coordinator.
(II) If Q doesn’t responds within time interval T’ then it is assumed to have failed and algorithm is restarted.



2. The Ring Algorithm –
This algorithm applies to systems organized as a ring(logically or physically). In this algorithm we assume that the link between the process are unidirectional and every process can message to the process on its right only. Data structure that this algorithm uses is active list, a list that has priority number of all active processes in the system.

Algorithm –

If process P1 detects a coordinator failure, it creates new active list which is empty initially. It sends election message to its neighbour on right and adds number 1 to its active list.
If process P2 receives message elect from processes on left, it responds in 3 ways:
(I) If message received does not contain 1 in active list then P1 adds 2 to its active list and forwards the message.
(II) If this is the first election message it has received or sent, P1 creates new active list with numbers 1 and 2. It then sends election message 1 followed by 2.
(III) If Process P1 receives its own election message 1 then active list for P1 now contains numbers of all the active processes in the system. Now Process P1 detects highest priority number from list and elects it as the new coordinator.
