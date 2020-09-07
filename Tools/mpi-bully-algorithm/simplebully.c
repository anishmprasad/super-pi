#include <stdio.h>
#include "simplebully.h"

int MAX_ROUNDS = 6;
double TX_PROB = 1.0 - ERROR_PROB;

unsigned long int get_PRNG_seed() {
	struct timeval tv;
	gettimeofday(&tv,NULL);
	unsigned long time_in_micros = 1000000 * tv.tv_sec + tv.tv_usec + getpid();

	return time_in_micros;
}

bool try_leader_elect() {

	double prob = rand() / (double) RAND_MAX;
	bool leader_elect = (prob > THRESHOLD);

	return leader_elect;
}


int main(int argc, char *argv[]) {

	int myrank, np;
	int current_leader = 0;
	int *recv_buf = (int *) malloc(2 * sizeof(int));
	int hello = HELLO_MSG;

	// user input argv[1]: designated initial leader
	current_leader = atoi(argv[1]);
	// user input argv[2]: how many rounds to run the algorithm
	MAX_ROUNDS = atoi(argv[2]);
	// user input argv[3]: packet trasnmission success/failure probability
	TX_PROB = atoi(argv[3]);

	printf("\n*******************************************************************");
	printf("\n*******************************************************************");
	printf("\n Initialization parameters:: \n\tMAX_ROUNDS = %d \n\tinitial leader = %d \n\tTX_PROB = %f\n", MAX_ROUNDS, current_leader, TX_PROB);
	printf("\n*******************************************************************");
	printf("\n*******************************************************************\n\n");

  // MPI Initiliazation
	MPI_Init(&argc, &argv);
	MPI_Comm_rank(comm, &myrank);
	MPI_Comm_size(comm, &np);

  MPI_Status status;

	srand(get_PRNG_seed());

	int succ, pred;
	int mytoken;

	// Since our nodes are arranged in the form of a ring, if we are rank 0
	// Then we loop around to the end of the ring to get our predecessor
	// Which is number of procs - 1, so if we are 0 and np is 6, our pred is 5

	// But if we are not rank 0, then our pred is just one below us, myrank - 1
	if (myrank == 0)
	{
			pred = np - 1;
	}
	else
	{
			pred = myrank - 1;
	}

	// Again, since the nodes are in a ring, if we are the highest rank, we loop around
	// To the start, which is 0
	// But if we are not the highest rank, our succ is just one above us myrank + 1
	if (myrank == (np - 1))
	{
			succ = 0;
	}
	else
	{
			succ = myrank + 1;
	}

	// Main loop, each iteration is a round
	for (int round = 0; round < MAX_ROUNDS; round++) {
		printf("\n*********************************** ROUND %d ******************************************\n", round);

		// Check if we are the current leader
		if (myrank == current_leader) {
					// If we are current leader, then we can do two things:
					// Send a hello message to succ or transmit leader_election_message to succ
        	if (try_leader_elect()) {
					// Our method to figuring out which to do is try_leader_elect
					// If we decide to try leader elect:
					// 1. Generate random TOKEN
					// 2. Transmit leader_election_msg to succ
					// 2.1 leader_election_msg contains rank of token and token value
				mytoken = generate_token();
				recv_buf[0] = myrank;
				recv_buf[1] = mytoken;

				MPI_Send(recv_buf, 2, MPI_INT, succ, LEADER_ELECTION_MSG_TAG, comm);
				printf("\n[rank %d][%d] SENT LEADER ELECTION MSG to node %d with TOKEN = %d, tag = %d\n", myrank, round, succ, mytoken, LEADER_ELECTION_MSG_TAG);
				fflush(stdout);
			} else {
				MPI_Send(&hello, 1, MPI_INT, succ, HELLO_MSG_TAG, comm);
				printf("\n[rank %d][%d] SENT HELLO MSG to node %d with TOKEN = %d, tag = %d\n", myrank, round, succ, mytoken, HELLO_MSG_TAG);
				fflush(stdout);
			}

			// We wait for hello or LEADER_ELECT_MSG using MPI_Irecv() and MPI_Test()
			MPI_Request request;
			int recv_buf[2];
			int flag = 0;
			MPI_Irecv(recv_buf, 2, MPI_INT, pred, MPI_ANY_TAG, comm, &request);

			while (!flag)
			{
					MPI_Test(&request, &flag, &status);
			}

			if (flag) {
				// We got a message
				switch (status.MPI_TAG) {
					case HELLO_MSG_TAG:
						// We sent the hello message and recieved from our pred, it hit all nodes
						printf("\n[rank %d][%d] HELLO MESSAGE completed ring traversal!\n", myrank, round);
						fflush(stdout);
						break;
					case LEADER_ELECTION_MSG_TAG:
						// We got an election msg, change current_leader to msg[0] and send result to success
						// Wait for result to come back from pred
						current_leader = recv_buf[0];
						MPI_Send(recv_buf,	2, MPI_INT, succ, LEADER_ELECTION_RESULT_MSG_TAG, comm);
						MPI_Recv(recv_buf, 2, MPI_INT, pred, LEADER_ELECTION_RESULT_MSG_TAG, comm, MPI_STATUS_IGNORE);
						printf("\n[rank %d][%d] NEW LEADER FOUND! new leader = %d, with token = %d\n", myrank, round, current_leader, recv_buf[1]);
						fflush(stdout);
						break;
					default: ;
				}
			}
		} else {
			// We are not the current leader
			int flag = 0;

			while (!flag)
			{
					MPI_Iprobe(MPI_ANY_SOURCE, MPI_ANY_TAG, comm, &flag, &status);
			}

			if (flag) {

				// Wait for message
				MPI_Recv(recv_buf, 2, MPI_INT, pred, MPI_ANY_TAG, comm, &status);

				if (status.MPI_TAG == HELLO_MSG_TAG) {
					// Pass hello message to succ
					MPI_Send(&hello, 1, MPI_INT, succ, HELLO_MSG_TAG, comm);
					printf("\n\t[rank %d][%d] Received and Forwarded HELLO MSG to next node = %d\n", myrank, round, succ);
					fflush(stdout);
				} else if (status.MPI_TAG == LEADER_ELECTION_MSG_TAG) {
					// We got the leader_election msg
					if (try_leader_elect()) {
						// Check if we will participate, same method as the leader uses
						// If yes, generate token and check my values against current received
						mytoken = generate_token();
						if ((mytoken > recv_buf[1]) || ((mytoken == recv_buf[1]) && (myrank > recv_buf[0])))
						{
								recv_buf[0] = myrank;
								recv_buf[1] = mytoken;
						}
						printf("\n\t[rank %d][%d] My new TOKEN = %d\n", myrank, round, mytoken);
						fflush(stdout);
					} else {
						// We are not going to participate, do nothing
							printf("\n\t[rank %d][%d] Will not participate in Leader Election.\n", myrank, round);
							fflush(stdout);
					}

					// Regardless of if we participate or not, we send LEADER_ELECT_MSG to succ
					MPI_Send(recv_buf, 2,	MPI_INT, succ, LEADER_ELECTION_MSG_TAG, comm);

					// Then issue a blocking MPI_RECV call and wait for results of election
					MPI_Recv(recv_buf, 2, MPI_INT, MPI_ANY_SOURCE, LEADER_ELECTION_RESULT_MSG_TAG, comm, MPI_STATUS_IGNORE);

					// When we receive the result, update current_leader to msg[0]
					current_leader = recv_buf[0];

					printf("\n\t[rank %d][%d] NEW LEADER :: node %d with TOKEN = %d\n", myrank, round, current_leader, recv_buf[1]);
					fflush(stdout);


					MPI_Send(recv_buf, 2, MPI_INT, succ, LEADER_ELECTION_RESULT_MSG_TAG, comm);
				}
			}
		}
		// End of steps, each node issues a MPI_Barrier()
		MPI_Barrier(comm);
	}
	printf("\n** Leader for NODE %d = %d\n", myrank, current_leader);


	MPI_Finalize();
	return 0;
}
