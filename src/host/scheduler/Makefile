VPATH = src:include:$(HDK_DIR)/common/software/src:$(HDK_DIR)/common/software/include

INCLUDES = -I$(SDK_DIR)/userspace/include
INCLUDES += -I $(HDK_DIR)/common/software/include
INCLUDES += -I $(AOS_DIR)/src/host/include

CC = g++
CFLAGS = -std=c++11 -fpermissive -DCONFIG_LOGLEVEL=4 -g -Wall $(INCLUDES)
CLIENT_CFLAGS = -std=c++11 -fpermissive -DCONFIG_LOGLEVEL=4 -g -Wall

LDLIBS = -lfpga_mgmt -lrt -lpthread
CLIENT_LDLIBS = -lrt -lpthread

SRC = ${SDK_DIR}/userspace/utils/sh_dpi_tasks.c ${SDK_DIR}/userspace/fpga_libs/fpga_dma/fpga_dma_utils.c

all: aos_host_sched_build sched_test
	
aos_host_sched_build: aos_daemon.cpp $(AOS_DIR)/src/host/include/aos.h aos_scheduler.cpp aos_host_common.cpp aos_app_session.cpp
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC) aos_host_common.cpp aos_daemon.cpp aos_scheduler.cpp aos_app_session.cpp -o aos_host_sched

sched_test: aos_host_common.cpp aos_scheduler.cpp test_aos_scheduler.cpp 
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) aos_host_common.cpp aos_scheduler.cpp test_aos_scheduler.cpp -o test_aos_scheduler

clean: aos_host_sched test_aos_scheduler
	rm -f /tmp/aos_daemon.socket
	rm -f test_aos_scheduler
	rm -f aos_host_sched