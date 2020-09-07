## CSPSC 416: Bully Elections with FGMPI.
[Fine Grain MPI](http://www.cs.ubc.ca/~humaira/fgmpi.html)

In this assignment you will again implement the bully election algorithm and you will use DLC to keep track of time. However, the focus this time is on using FGMPI which is a variant of MPI developed here at UBC to support message passing between a very large numbers of processes. (I did a test run of the provided demo program with over 20,000 processes.) NOTE: In this writeup the terms coordinator and leader mean the same thing as do the terms process and node. The Election Arguments Your program is to take the following arguments in the following order:

1. a 0 to indicate minimal output or a 1 to indicate debugging output. In minimal mode the application is to only print events to indicate that:
	- The leader declares itself dead
	- A communcation failure with the leader was detected 3. An election was called
	- A node declares itself the leader
	- A dead node comes back on line
Debugging output must include the above information as well as printouts of the messages
received by each process.
2. Timeout Value The timeout value, in seconds, for all timeout related events in your
program.
3. AYA timeThis is the average amount of time in seonds that a node waits before sending an
AYA message to the coordinator. See the sample code from A2 on how to do this .
4. SendFailure The probability that upon receipt of an AYA that the coordinator will declare
itself dead. (Note that even if the coordinator is dead it must still receive messages, but it
will simply ignore them.)
5. Return to lifeThis is the average amount of time in seconds, that the node waits before
coming back to life once it has "died".

One of the big challenges with MPI is timing out on receive operations. In fact, there is no easy way to do it. One approach is to use some of the MPI non-blocking primitives like MPI_Iprobe() another approach is to designate one of the process to be a clock and send messages to all the other processes periodically. Since these messages are arriving at fixed intervals the receivers can use them to mark time to deal with a time out event. Since timeout values are on the order of seconds, sending a "tick" to all processes once a second should be sufficient. You are free to reuse as much of your code from A2 as you want, however you must report in the coverpage.txt file the repo of the assignments you are reusing code from. If you are working with a different partner than you had for A2 it is fine to reuse code from either of your assignments as long as it is acknowledged.

### DLC
At a minimum you must increment your DLC on a message send and update it on a message receive. The one exception is that the clock process will not keep a DLC and as a result a message from the clock process will not contain DLC informaiton and will not cause a process to increment its clock.

### Event printing
When printing an event, each event must be on one line and containg the following information:

1. DLC time
2. EventIdentifier
3. ID of the node printing the message
4. Any additional information required to help interpret the event. Don't simply print a
number without a word or two to say what the number is.

The event identifiers are:

1. ELECTION - to indicate the calling of an election
2. DEAD - used by the leader/coordinator to log its death
3. ALIVE - used to indicate that a dead process is alive again
4. LEADER - printed by a node when it declares itself the leader.
5. LEADERDEAD - printed by a node when it detects a leader's death
6. PRIV_XXX - Any event you want to print of your own choosing. Replace the XXX with
something meaningful.

### To Start
To get going clone the repo and try the bully program out. You are welcome to download and install FGMPI on your own machine but you will then need to modify the makefile. Be sure you don't break the makefile for the code you handin. (To avoid breaking it you might simply want to make sure that you don't add the new version to your repo) Try the example, try running it manually and make sure to check the README file. You might want to try making a few minor changes to see how things behave before proceeding. Once you are ready to go consider how you are going to determine the clock process (I'd suggest process 0). You should consider drawing out a state machine to help with your design and the assigning of functionality. Ideally the provided code should have been broken up into smaller functions. For example the process everyone is sending to should really be in its own function and it probably wouldn't hurt if the various processing stages were in their own functions as well. Start small and test as you go. Initially just work with a few processes, 4 or 5. Debugging is somewhat more challenging and depends upon printfs. As you become more confident work with more and more processes. You should be able to handle paramaters like -nfg 100 and -n 10. You terminate a test by typing control-c where you launched things from. You can use the script command to log your output to a file for later analysis.
