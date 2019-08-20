# AOS_DIR must be set
INCLUDES = -I $(AOS_DIR)/src/host/include

CC = g++
CFLAGS = -std=c++11 -fpermissive -DCONFIG_LOGLEVEL=4 -g -Wall $(INCLUDES)
CLIENT_CFLAGS = -std=c++11 -fpermissive -DCONFIG_LOGLEVEL=4 -g -Wall

LDLIBS = -lpthread
CLIENT_LDLIBS = -lpthread

all: memdrive_build

memdrive_build: $(AOS_DIR)/src/host/include/aos.h memdrive_client.cpp
	$(CC) $(CLIENT_CFLAGS) $(CLIENT_LDLIBS) $(INCLUDES) memdrive_client.cpp -o memdrive_client

clean: memdrive_client
	rm -f memdrive_client