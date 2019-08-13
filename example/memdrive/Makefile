
INCLUDES = -I$(SDK_DIR)/userspace/include
INCLUDES += -I $(HDK_DIR)/common/software/include
INCLUDES += -I ./include

CC = g++
CFLAGS = -std=c++11 -fpermissive -DCONFIG_LOGLEVEL=4 -g -Wall $(INCLUDES)
CLIENT_CFLAGS = -std=c++11 -fpermissive -DCONFIG_LOGLEVEL=4 -g -Wall

LDLIBS = -lfpga_mgmt -lrt -lpthread
CLIENT_LDLIBS = -lrt -lpthread

all: memdrive_build

memdrive_build: aos.h memdrive_client.c
	$(CC) $(CLIENT_CFLAGS) $(CLIENT_LDLIBS) memdrive_client.c -o memdrive_client

clean: memdrive client
	rm -f memdrive_client