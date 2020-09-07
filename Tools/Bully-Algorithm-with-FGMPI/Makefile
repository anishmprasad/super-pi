
MPICROOT:=/home/c/cs416/fgmpi
MPI_CC := $(MPICROOT)/bin/mpicc
MPIINC := $(MPICHROOT)/include
MPILIB := -L $(MPICROOT)/lib
MPICC := $(MPI_CC) -g -D_REENTRANT -W -Wall -O3
MPILD := $(MPICC) -lm

INC = 

CFILES := $(wildcard *.c)
APPSOBJS := $(patsubst %.c, %.o, $(CFILES)) 
HEADERS := $(wildcard *.h)

APPS = $(patsubst %.c, %, $(CFILES))

all: $(APPS)
	@echo Making $(APPS) ....

%.o: %.c $(HEADERS) Makefile
	$(MPICC) $(INC) -o $@ -c $<


$(APPS) : % : %.o $(MAKEDEPS) $(APPSOBJS) $(HEADERS)
	$(MPILD) $(INC) $(patsubst %, %.o, $@) -o $@ 



clean:
	rm -f *.o *.a core $(APPS)

demo: bully
	$(MPICROOT)/bin/mpirun  -nfg 10 -n 4 ./bully

begin:bully
	 $(MPICROOT)/bin/mpirun  -nfg 3 -n 3 ./bully 0 10 5 10 21
init:bully
	$(MPICROOT)/bin/mpirun  -nfg 2 -n 2 ./bully 1 5 3 0 21
init2:bully
	$(MPICROOT)/bin/mpirun  -nfg 2 -n 2 ./bully 0 5 3 0 21
FORCE:

first_target: all

.PHONY: all clean 
