#ifndef SIMPLEBULLY_H_
#define SIMPLEBULLY_H_

	#include <stdio.h>
	#include <stdlib.h>
	#include <time.h>
	#include <sys/time.h>
	#include <stdbool.h>
	#include <mpi.h>
	#include <unistd.h>

	#define ERROR_PROB 0.05					// probability of error in transmission ==> probability of packet loss
	#define THRESHOLD 0.5					// probability of a node deciding to partipicating in a leader election
	#define MAX_TOKEN_VALUE 10000			// maximum value of a token in the leader election process
	#define TIME_OUT_INTERVAL 3             // in secs

	#define HELLO_MSG 9999					

	#define HELLO_MSG_TAG 0001
	#define LEADER_ELECTION_MSG_TAG 0002
	#define LEADER_ELECTION_RESULT_MSG_TAG 0003

	MPI_Comm comm = MPI_COMM_WORLD;

	inline double get_prob() {
    	double prob = rand() / (double) RAND_MAX;       // number between [0.0, 1.0]
    	return prob;
	}

	inline int generate_token() {
    	return rand() % MAX_TOKEN_VALUE;
	}


#endif
